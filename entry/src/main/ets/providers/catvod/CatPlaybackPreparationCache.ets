import { CatVodVideo } from './CatVodModels'

class PreparationScope {}
class DetailEntry {
  scope: Object | null = null
  storedAt: number = 0
  json: string = ''
  fromDisk: boolean = false
}
class DetailTask {
  scope: Object | null = null
  promise: Promise<CatVodVideo | null> | null = null
  fromDisk: boolean = false
}
class PreferredVariant {
  id: string = ''
  storedAt: number = 0
}
class InitializationEntry {
  scope: Object | null = null
  storedAt: number = 0
  path: string = ''
  promise: Promise<string> | null = null
}

/** Process cache; Node loaders may restore persistent metadata. Final PlaybackStream objects are excluded. */
export class CatPlaybackPreparationCache {
  static readonly defaultScope: Object = new PreparationScope()
  private static details: Map<string, DetailEntry> = new Map()
  private static pending: Map<string, DetailTask> = new Map()
  private static variants: Map<string, PreferredVariant> = new Map()
  private static initializations: Map<string, InitializationEntry> = new Map()
  private static liveDetails: Map<string, Object> = new Map()
  private static cacheRevision: number = 0
  private static readonly DETAIL_TTL_MS: number = 120000
  private static readonly MAX_ENTRIES: number = 24
  private static readonly MAX_CHARS: number = 2 * 1024 * 1024

  static async detail(scope: Object, key: string, videoId: string,
    load: (report: (status: string) => void) => Promise<CatVodVideo | null>, force: boolean = false,
    trace: (status: string) => void = () => {}, requireLive: boolean = false): Promise<CatVodVideo | null> {
    if (force) { CatPlaybackPreparationCache.details.delete(key); CatPlaybackPreparationCache.pending.delete(key) }
    const entry = CatPlaybackPreparationCache.details.get(key)
    const age = entry === undefined ? -1 : Date.now() - entry.storedAt
    if (entry !== undefined && entry.scope === scope && age >= 0 && age < CatPlaybackPreparationCache.DETAIL_TTL_MS &&
      (!requireLive || !entry.fromDisk)) {
      CatPlaybackPreparationCache.details.delete(key); CatPlaybackPreparationCache.details.set(key, entry)
      trace(entry.fromDisk ? 'disk_hit' : 'hit')
      return JSON.parse(entry.json) as CatVodVideo
    }
    if (entry !== undefined) trace('invalidated reason=' + (entry.scope !== scope ? 'runtime_changed' :
      requireLive && entry.fromDisk ? 'live_detail_required' : 'expired'))
    CatPlaybackPreparationCache.details.delete(key)
    const active = CatPlaybackPreparationCache.pending.get(key)
    if (active !== undefined && active.scope === scope && active.promise !== null) {
      trace('joined')
      const video = await active.promise
      if (requireLive && active.fromDisk) {
        return CatPlaybackPreparationCache.detail(scope, key, videoId, load, false, trace, true)
      }
      if (active.fromDisk) trace('disk_hit')
      return video === null ? null : JSON.parse(JSON.stringify(video)) as CatVodVideo
    }
    trace(force ? 'refresh' : 'miss')
    const task = new DetailTask()
    task.scope = scope
    CatPlaybackPreparationCache.pending.set(key, task)
    task.promise = CatPlaybackPreparationCache.loadDetail(task, scope, key, videoId, load, trace)
    const video = await task.promise
    return video === null ? null : JSON.parse(JSON.stringify(video)) as CatVodVideo
  }

  private static async loadDetail(task: DetailTask, scope: Object, key: string, videoId: string,
    load: (report: (status: string) => void) => Promise<CatVodVideo | null>, trace: (status: string) => void): Promise<CatVodVideo | null> {
    try {
      const video = await load((status: string) => {
        if (status === 'disk_hit') task.fromDisk = true
        trace(status)
      })
      if (video !== null && video.id === videoId && video.name.trim().length > 0 &&
        CatPlaybackPreparationCache.pending.get(key) === task) {
        const json = JSON.stringify(video)
        // A long episode list may exceed 256Ki. Use the existing total budget as
        // the entry ceiling instead of silently excluding otherwise valid details.
        if (json.length <= CatPlaybackPreparationCache.MAX_CHARS) {
          const entry = new DetailEntry()
          entry.scope = scope; entry.storedAt = Date.now(); entry.json = json
          entry.fromDisk = task.fromDisk
          CatPlaybackPreparationCache.details.delete(key); CatPlaybackPreparationCache.details.set(key, entry)
          let size = 0
          CatPlaybackPreparationCache.details.forEach((value: DetailEntry) => { size += value.json.length })
          while (CatPlaybackPreparationCache.details.size > CatPlaybackPreparationCache.MAX_ENTRIES ||
            size > CatPlaybackPreparationCache.MAX_CHARS) {
            for (const oldest of CatPlaybackPreparationCache.details.keys()) {
              size -= CatPlaybackPreparationCache.details.get(oldest)?.json.length ?? 0
              CatPlaybackPreparationCache.details.delete(oldest)
              break
            }
          }
          trace('stored chars=' + json.length)
        } else {
          trace('not_stored reason=size_limit chars=' + json.length)
        }
      } else {
        trace('not_stored reason=' + (video === null ? 'empty' :
          video.id !== videoId || video.name.trim().length === 0 ? 'identity_or_title' : 'invalidated'))
      }
      return video
    } catch (error) {
      trace('not_stored reason=load_failed')
      if (error instanceof Error) throw error
      throw new Error('来源请求失败')
    } finally {
      if (CatPlaybackPreparationCache.pending.get(key) === task) CatPlaybackPreparationCache.pending.delete(key)
    }
  }

  /** Successful init negotiation is reusable by independent clients of the same runtime/config. */
  static async initialize(scope: Object, key: string, load: () => Promise<string>,
    trace: (status: string) => void = () => {}): Promise<string> {
    const entry = CatPlaybackPreparationCache.initializations.get(key)
    if (entry !== undefined && entry.scope === scope) {
      if (entry.promise !== null) { trace('joined'); return entry.promise }
      const age = Date.now() - entry.storedAt
      if (age >= 0 && age < CatPlaybackPreparationCache.DETAIL_TTL_MS && entry.path.length > 0) {
        CatPlaybackPreparationCache.initializations.delete(key)
        CatPlaybackPreparationCache.initializations.set(key, entry)
        trace('hit'); return entry.path
      }
    }
    trace('miss')
    const task = new InitializationEntry(); task.scope = scope
    CatPlaybackPreparationCache.initializations.set(key, task)
    while (CatPlaybackPreparationCache.initializations.size > 64) {
      for (const oldest of CatPlaybackPreparationCache.initializations.keys()) {
        CatPlaybackPreparationCache.initializations.delete(oldest); break
      }
    }
    task.promise = CatPlaybackPreparationCache.loadInitialization(task, key, load)
    return task.promise
  }

  private static async loadInitialization(task: InitializationEntry, key: string,
    load: () => Promise<string>): Promise<string> {
    try {
      const path = await load()
      if (path.length === 0) throw new Error('来源初始化未返回有效路径')
      task.path = path; task.storedAt = Date.now(); task.promise = null
      return path
    } catch (error) {
      if (CatPlaybackPreparationCache.initializations.get(key) === task) {
        CatPlaybackPreparationCache.initializations.delete(key)
      }
      if (error instanceof Error) throw error
      throw new Error('来源初始化失败')
    }
  }

  static preferredVariant(key: string): string {
    const entry = CatPlaybackPreparationCache.variants.get(key)
    if (entry === undefined) return ''
    const age = Date.now() - entry.storedAt
    if (age < 0 || age >= 30 * 60 * 1000) { CatPlaybackPreparationCache.variants.delete(key); return '' }
    return entry.id
  }

  static rememberVariant(key: string, id: string): void {
    if (id.length === 0) return
    const entry = new PreferredVariant(); entry.id = id; entry.storedAt = Date.now()
    CatPlaybackPreparationCache.variants.delete(key); CatPlaybackPreparationCache.variants.set(key, entry)
    while (CatPlaybackPreparationCache.variants.size > 64) {
      for (const oldest of CatPlaybackPreparationCache.variants.keys()) {
        CatPlaybackPreparationCache.variants.delete(oldest)
        break
      }
    }
  }

  static revision(): number { return CatPlaybackPreparationCache.cacheRevision }

  static hasLiveDetail(scope: Object, key: string): boolean {
    return CatPlaybackPreparationCache.liveDetails.get(key) === scope
  }

  static markLiveDetail(scope: Object, key: string): void {
    CatPlaybackPreparationCache.liveDetails.delete(key)
    CatPlaybackPreparationCache.liveDetails.set(key, scope)
    while (CatPlaybackPreparationCache.liveDetails.size > 64) {
      for (const oldest of CatPlaybackPreparationCache.liveDetails.keys()) {
        CatPlaybackPreparationCache.liveDetails.delete(oldest); break
      }
    }
  }

  static clear(): void {
    CatPlaybackPreparationCache.cacheRevision++
    CatPlaybackPreparationCache.details.clear(); CatPlaybackPreparationCache.pending.clear()
    CatPlaybackPreparationCache.variants.clear()
    CatPlaybackPreparationCache.initializations.clear()
    CatPlaybackPreparationCache.liveDetails.clear()
  }
}
