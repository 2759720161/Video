import { CatNodeSearchUnavailableError } from '../../providers/catvod/CatNodeClient'
import { CatNodeRequestControl } from '../../providers/catvod/CatNodeRequestControl'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { MediaSearchSession } from './MediaSearchSession'
import { MediaSearchItem, MediaSearchPage, MediaSearchPresentation } from './MediaSearchPresentation'
import { MediaSearchScopeSelection } from './MediaSearchScopeSelection'

export const MEDIA_SEARCH_ALL: string = '/aggregate'

class SearchDirectory {
  key: string = ''
  page: number = 0
  pageCount: number = 1
  failed: boolean = false
  unavailable: boolean = false
}

export class MediaSearchAggregateState {
  items: MediaSearchItem[] = []
  completed: number = 0
  total: number = 0
  failed: number = 0
  unavailable: number = 0
  succeeded: number = 0
  hasMore: boolean = false
}

/** Four directory requests at a time; each round fetches at most one page per directory. */
export class MediaSearchAggregate {
  private session: MediaSearchSession
  private word: string
  private directories: SearchDirectory[]
  private items: MediaSearchItem[] = []
  private controls: CatNodeRequestControl[] = []
  private cancelled: boolean = false
  private running: boolean = false
  private completed: number = 0
  private total: number = 0
  private timeoutMs: number

  constructor(session: MediaSearchSession, word: string, timeoutMs: number = 12000, selectedKeys: string[] | null = null) {
    this.session = session; this.word = MediaSearchPresentation.normalize(word)
    this.timeoutMs = Math.max(1, Math.min(12000, timeoutMs))
    const keys = MediaSearchScopeSelection.normalize(selectedKeys ?? session.scopes.map((site: CatNodeSite) => site.key), session.scopes)
    this.directories = keys.map((key: string) => {
      const value = new SearchDirectory(); value.key = key; return value
    })
  }

  cancel(): void {
    this.cancelled = true
    const controls = this.controls; this.controls = []
    for (let i = 0; i < controls.length; i++) controls[i].cancel()
  }

  snapshot(): MediaSearchAggregateState {
    const value = new MediaSearchAggregateState()
    value.items = this.items.slice(); value.completed = this.completed; value.total = this.total
    value.failed = this.directories.filter((task: SearchDirectory) => task.failed).length
    value.unavailable = this.directories.filter((task: SearchDirectory) => task.unavailable).length
    value.succeeded = this.directories.filter((task: SearchDirectory) => task.page > 0).length
    value.hasMore = !this.cancelled && this.directories.some((task: SearchDirectory) => this.pending(task))
    return value
  }

  private pending(task: SearchDirectory): boolean { return !task.unavailable && (task.failed || task.page < task.pageCount) }

  private async fetch(task: SearchDirectory): Promise<void> {
    const control = new CatNodeRequestControl()
    this.controls.push(control)
    let timer = -1
    let abort: () => void = () => {}
    const cancelled = new Promise<MediaSearchPage>((_resolve, reject) => {
      abort = (): void => { reject(new Error('搜索已停止或超时')) }
      control.onCancel(abort)
      timer = setTimeout(() => control.cancel(), this.timeoutMs)
    })
    try {
      const result = await Promise.race([this.session.forScope(task.key, control).search(this.word, task.page + 1), cancelled])
      if (this.cancelled) return
      task.page = result.page; task.pageCount = result.pageCount; task.failed = false
      this.items = MediaSearchPresentation.merge(this.items, result.items)
    } catch (error) {
      if (this.cancelled) return
      task.unavailable = error instanceof CatNodeSearchUnavailableError
      task.failed = !task.unavailable
    } finally {
      clearTimeout(timer); control.offCancel(abort)
      this.controls = this.controls.filter((value: CatNodeRequestControl) => value !== control)
    }
  }

  async round(onProgress: (state: MediaSearchAggregateState) => void): Promise<MediaSearchAggregateState> {
    if (this.running || this.cancelled || this.word.length === 0) return this.snapshot()
    const queue = this.directories.filter((task: SearchDirectory) => this.pending(task))
    this.running = true; this.completed = 0; this.total = queue.length
    let cursor = 0
    const worker = async (): Promise<void> => {
      while (!this.cancelled && cursor < queue.length) {
        const task = queue[cursor++]
        await this.fetch(task)
        if (this.cancelled) return
        this.completed++
        onProgress(this.snapshot())
      }
    }
    try {
      onProgress(this.snapshot())
      const workers: Promise<void>[] = []
      for (let i = 0; i < Math.min(4, queue.length); i++) workers.push(worker())
      await Promise.all(workers)
      return this.snapshot()
    } finally { this.running = false }
  }
}
