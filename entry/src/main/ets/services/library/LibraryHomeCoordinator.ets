import { common } from '@kit.AbilityKit'
import { MediaItem } from '../../core/media/MediaItem'
import { MediaSection } from '../../core/media/MediaSection'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { ProviderHomeSnapshot } from '../../models/ProviderHomeSnapshot'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { PreferencesStore } from '../../store/PreferencesStore'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'

const HOME_CACHE_KEY: string = 'libraryHomeSnapshotsV1'

/** 首页数据编排：本地优先、远程并发、单来源失败隔离，并缓存安全媒体元数据。 */
export class LibraryHomeCoordinator {
  async load(context: common.UIAbilityContext | null = null): Promise<ProviderHomeSnapshot[]> {
    const sources = await MediaSourceStore.getAll()
    const cached = await this.readCache()
    const result: ProviderHomeSnapshot[] = []
    const pending: Promise<ProviderHomeSnapshot | null>[] = []
    for (let i = 0; i < sources.length; i++) {
      const source = sources[i]
      if (!source.enabled && source.id !== 'local') continue
      if (source.id === 'local') {
        const local = await this.loadSource(source, context)
        if (local !== null) result.push(local)
      } else {
        pending.push(this.loadSourceWithFallback(source, cached.get(source.id) ?? null, context))
      }
    }
    const remote = await Promise.all(pending)
    for (let i = 0; i < remote.length; i++) if (remote[i] !== null) result.push(remote[i] as ProviderHomeSnapshot)
    await this.writeCache(result)
    return result
  }

  private async loadSourceWithFallback(source: MediaSourceInstance,
    fallback: ProviderHomeSnapshot | null, context: common.UIAbilityContext | null): Promise<ProviderHomeSnapshot | null> {
    const current = await this.loadSource(source, context)
    return current === null ? fallback : current
  }

  private async loadSource(source: MediaSourceInstance,
    context: common.UIAbilityContext | null): Promise<ProviderHomeSnapshot | null> {
    const provider = await ProviderRegistry.get(source.id, context)
    if (provider === null || !provider.hasCapability(ProviderCapability.HOME)) return null
    try {
      const sections = await provider.getHome()
      const snapshot = new ProviderHomeSnapshot()
      snapshot.sourceId = source.id
      snapshot.sourceName = source.name
      snapshot.updatedAt = Date.now()
      snapshot.sections = this.sanitizeSections(sections)
      return snapshot
    } catch (_) {
      return null
    }
  }

  private sanitizeSections(sections: MediaSection[], includeRuntimeArtwork: boolean = true): MediaSection[] {
    const result: MediaSection[] = []
    for (let i = 0; i < sections.length; i++) {
      const source = sections[i]
      if (source === null || typeof source !== 'object') continue
      const section = new MediaSection()
      section.id = source.id
      section.title = source.title
      for (let j = 0; j < source.items.length; j++) {
        const value = source.items[j]
        if (value === null || typeof value !== 'object' || value.id.length === 0) continue
        const item = new MediaItem()
        item.sourceId = value.sourceId
        item.id = value.id
        item.parentId = value.parentId
        item.title = value.title
        item.subtitle = value.subtitle
        item.overview = value.overview
        item.type = value.type
        item.artworkRef = value.artworkRef
        item.backdropRef = value.backdropRef
        // Runtime poster URLs may contain provider credentials (for example
        // Emby's api_key). They are useful for the live snapshot, but must
        // never be written to the persistent home cache.
        item.poster = includeRuntimeArtwork ? value.poster : ''
        item.backdrop = includeRuntimeArtwork ? value.backdrop : ''
        item.durationMs = value.durationMs
        item.positionMs = value.positionMs
        item.variantId = value.variantId
        item.variants = value.variants
        item.year = value.year
        item.playable = value.playable
        item.browsable = value.browsable
        section.items.push(item)
      }
      if (section.items.length > 0) result.push(section)
    }
    return result
  }

  private async readCache(): Promise<Map<string, ProviderHomeSnapshot>> {
    const result = new Map<string, ProviderHomeSnapshot>()
    try {
      const raw = await PreferencesStore.getInstance().getString(HOME_CACHE_KEY, '{}')
      const parsed = JSON.parse(raw) as Record<string, Object>
      const keys = Object.keys(parsed)
      for (let i = 0; i < keys.length; i++) {
        const value = parsed[keys[i]]
        if (value === null || typeof value !== 'object') continue
        const snapshot = this.decodeSnapshot(value as Record<string, Object>)
        if (snapshot !== null) result.set(snapshot.sourceId, snapshot)
      }
    } catch (_) {
    }
    return result
  }

  private async writeCache(snapshots: ProviderHomeSnapshot[]): Promise<void> {
    const payload: Record<string, Object> = {}
    for (let i = 0; i < snapshots.length; i++) {
      const source = snapshots[i]
      const snapshot = new ProviderHomeSnapshot()
      snapshot.sourceId = source.sourceId
      snapshot.sourceName = source.sourceName
      snapshot.updatedAt = source.updatedAt
      snapshot.sections = this.sanitizeSections(source.sections, false)
      payload[snapshot.sourceId] = snapshot as Object
    }
    try {
      await PreferencesStore.getInstance().setString(HOME_CACHE_KEY, JSON.stringify(payload))
    } catch (_) {
    }
  }

  private decodeSnapshot(value: Record<string, Object>): ProviderHomeSnapshot | null {
    const sourceId = typeof value['sourceId'] === 'string' ? value['sourceId'] as string : ''
    if (sourceId.trim().length === 0) return null
    const snapshot = new ProviderHomeSnapshot()
    snapshot.sourceId = sourceId.trim()
    snapshot.sourceName = typeof value['sourceName'] === 'string' ? value['sourceName'] as string : ''
    snapshot.updatedAt = typeof value['updatedAt'] === 'number' ? value['updatedAt'] as number : 0
    const rawSections = value['sections']
    if (Array.isArray(rawSections)) snapshot.sections = this.sanitizeSections(rawSections as MediaSection[], false)
    return snapshot
  }
}
