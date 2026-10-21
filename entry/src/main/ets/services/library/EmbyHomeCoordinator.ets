import { EmbyItem } from '../../providers/emby/EmbyModels'
import { PreferencesStore } from '../../store/PreferencesStore'
import { EmbyHomeSnapshot, EmbyHomeSection } from './EmbyHomeSnapshot'
import { EmbyHomeCache } from './EmbyHomeCache'
import type { EmbyHomeSource } from '../../providers/emby/EmbyHomeSource'

export interface EmbyHomePersistence {
  read(key: string): Promise<string>
  write(key: string, value: string): Promise<void>
}

class PreferencesHomePersistence implements EmbyHomePersistence {
  async read(key: string): Promise<string> { return PreferencesStore.getInstance().getString(key, '') }
  async write(key: string, value: string): Promise<void> { await PreferencesStore.getInstance().setString(key, value) }
}

/** A session belongs to exactly one server/account; disposing invalidates every late response. */
export class EmbyHomeCoordinator {
  private generation: number = 0
  private cacheKey: string
  private provider: EmbyHomeSource
  private persistence: EmbyHomePersistence
  private snapshot: EmbyHomeSnapshot = new EmbyHomeSnapshot()

  constructor(provider: EmbyHomeSource, cacheKey: string,
    persistence: EmbyHomePersistence = new PreferencesHomePersistence()) {
    this.provider = provider; this.cacheKey = cacheKey; this.persistence = persistence
  }
  dispose(): void { this.generation++ }

  async load(onChange: (value: EmbyHomeSnapshot) => void): Promise<void> {
    const generation = ++this.generation
    const cached = await this.persistence.read(this.cacheKey)
    if (generation !== this.generation) return
    if (cached.length > 0) {
      try { this.snapshot = EmbyHomeCache.decode(cached) } catch (_) {}
    }
    this.snapshot.librariesLoading = true
    this.snapshot.resumeLoading = true
    this.snapshot.librariesError = ''
    this.snapshot.resumeError = ''
    onChange(this.copy())
    await Promise.all([this.loadLibraries(generation, onChange), this.loadResume(generation, onChange),
      this.loadNextUp(generation, onChange)])
    if (generation !== this.generation) return
    if (this.snapshot.librariesError.length === 0 && this.snapshot.resumeError.length === 0 &&
      this.snapshot.sections.every((section: EmbyHomeSection) => section.error.length === 0)) {
      this.snapshot.timestamp = Date.now()
      onChange(this.copy())
      await this.persistence.write(this.cacheKey, EmbyHomeCache.encode(this.snapshot))
    }
  }

  private async loadResume(generation: number, onChange: (value: EmbyHomeSnapshot) => void): Promise<void> {
    try {
      const items = await this.provider.getResumeItemsRaw()
      if (generation !== this.generation) return
      this.snapshot.resumeItems = items.filter((item: EmbyItem) => !item.userData.played &&
        item.resumePositionMs() > 0).slice(0, 12)
    } catch (_) {
      if (generation !== this.generation) return
      this.snapshot.resumeError = '观看进度暂未更新'
    } finally {
      if (generation === this.generation) {
        this.snapshot.resumeLoading = false
        onChange(this.copy())
      }
    }
  }

  private async loadNextUp(generation: number, onChange: (value: EmbyHomeSnapshot) => void): Promise<void> {
    try {
      const items = await this.provider.getNextUpItemsRaw(12)
      if (generation !== this.generation) return
      this.snapshot.nextUpItems = items.filter((item: EmbyItem) => item.type === 'Episode' &&
        !item.userData.played && item.resumePositionMs() === 0)
      onChange(this.copy())
    } catch (_) {
      // Optional on older Emby versions. Never fabricate next episodes from an unplayed list.
      if (generation === this.generation) { this.snapshot.nextUpItems = []; onChange(this.copy()) }
    }
  }

  private async loadLibraries(generation: number, onChange: (value: EmbyHomeSnapshot) => void): Promise<void> {
    try {
      const libraries = await this.provider.getLibrariesRaw()
      if (generation !== this.generation) return
      this.snapshot.libraries = libraries
      this.snapshot.sections = libraries.map((library: EmbyItem) => {
        const section = new EmbyHomeSection()
        section.id = library.id
        section.title = library.name
        section.collectionType = library.collectionType
        section.items = this.snapshot.sections.find((old: EmbyHomeSection) => old.id === library.id)?.items ?? []
        section.loading = true
        return section
      })
      this.snapshot.librariesLoading = false
      onChange(this.copy())
      // Bound concurrent preview requests instead of flooding servers with many libraries.
      let next = 0
      const worker = async (): Promise<void> => {
        while (next < libraries.length && generation === this.generation) {
          const index = next++
          await this.loadPreview(libraries[index], index, generation, onChange)
        }
      }
      await Promise.all([worker(), worker()])
    } catch (_) {
      if (generation !== this.generation) return
      this.snapshot.librariesError = '媒体库暂未更新'
    } finally {
      if (generation === this.generation) {
        this.snapshot.librariesLoading = false
        onChange(this.copy())
      }
    }
  }

  private async loadPreview(library: EmbyItem, index: number, generation: number,
    onChange: (value: EmbyHomeSnapshot) => void): Promise<void> {
    try {
      const items = await this.provider.getLatestLibraryItemsRaw(library.id, 10)
      if (generation !== this.generation) return
      this.snapshot.sections[index].items = items
    } catch (_) {
      if (generation !== this.generation) return
      this.snapshot.sections[index].error = '此栏目暂未更新'
    } finally {
      if (generation === this.generation) {
        this.snapshot.sections[index].loading = false
        onChange(this.copy())
      }
    }
  }

  private copy(): EmbyHomeSnapshot {
    const result = new EmbyHomeSnapshot()
    result.libraries = this.snapshot.libraries.slice()
    result.resumeItems = this.snapshot.resumeItems.slice()
    result.nextUpItems = this.snapshot.nextUpItems.slice()
    result.latestItems = this.snapshot.latestItems.slice()
    result.sections = this.snapshot.sections.map((value: EmbyHomeSection) => {
      const section = new EmbyHomeSection()
      section.id = value.id; section.title = value.title; section.collectionType = value.collectionType
      section.items = value.items.slice(); section.loading = value.loading; section.error = value.error
      return section
    })
    result.timestamp = this.snapshot.timestamp
    result.librariesLoading = this.snapshot.librariesLoading; result.resumeLoading = this.snapshot.resumeLoading
    result.librariesError = this.snapshot.librariesError; result.resumeError = this.snapshot.resumeError
    return result
  }
}
