import { MediaItem, MediaItemType } from '../../core/media/MediaItem'
import { MediaSection } from '../../core/media/MediaSection'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { PlaybackSession } from '../../core/playback/PlaybackSession'
import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { PlaybackMedia } from '../../core/playback/PlaybackMedia'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import type { MediaProvider } from '../base/MediaProvider'
import type { PlaybackResolver } from '../../core/playback/PlaybackResolver'
import { EmbyClient } from './EmbyClient'
import { EmbyItem, EmbyPlaybackContext, EmbyServerConfig } from './EmbyModels'
import { EmbyPlaybackReporter } from './EmbyPlaybackReporter'
import { EmbySourceConfigCodec } from './EmbySourceConfig'

/** Emby API 和通用媒体模型之间的适配层。 */
export class EmbyProvider implements MediaProvider, PlaybackResolver {
  private source: MediaSourceInstance
  private config: EmbyServerConfig
  private client: EmbyClient

  private constructor(source: MediaSourceInstance, config: EmbyServerConfig) {
    this.source = source
    this.config = config.copy()
    this.client = new EmbyClient(this.config)
  }

  static fromSource(source: MediaSourceInstance): EmbyProvider {
    const config = EmbySourceConfigCodec.decode(source.configJson)
    if (config === null) throw new Error('Emby 配置无效')
    return new EmbyProvider(source, config)
  }

  getSourceId(): string { return this.source.id }

  /** Emby 浏览页仍需要保留 Emby 专属元数据；由 Provider 负责访问客户端。 */
  async getLibrariesRaw(): Promise<EmbyItem[]> { return this.client.getLibraries() }

  async getLatestItemsRaw(limit: number = 0): Promise<EmbyItem[]> {
    return this.client.getLatestItems(limit)
  }

  async getResumeItemsRaw(): Promise<EmbyItem[]> { return this.client.getResumeItems() }

  async getLibraryItemsRaw(parentId: string, limit: number = 0,
    collectionType: string = ''): Promise<EmbyItem[]> {
    return this.client.getLibraryItems(EmbyProvider.normalizeText(parentId), limit,
      EmbyProvider.normalizeText(collectionType))
  }

  async getItemsRaw(parentId: string): Promise<EmbyItem[]> {
    return this.client.getItems(EmbyProvider.normalizeText(parentId))
  }

  async getItemRaw(itemId: string): Promise<EmbyItem | null> {
    const normalizedItemId = EmbyProvider.normalizeText(itemId)
    if (normalizedItemId.length === 0) return null
    return this.client.getItem(normalizedItemId)
  }

  imageUrlFor(item: EmbyItem, maxWidth: number = 500): string {
    return this.client.imageUrl(item, maxWidth)
  }

  hasCapability(capability: ProviderCapability): boolean {
    return capability === ProviderCapability.HOME || capability === ProviderCapability.SEARCH ||
      capability === ProviderCapability.BROWSE || capability === ProviderCapability.RESUME ||
      capability === ProviderCapability.PROGRESS_SYNC || capability === ProviderCapability.TRANSCODE
  }

  async getHome(): Promise<MediaSection[]> {
    const sections: MediaSection[] = []
    const libraries = await this.client.getLibraries()
    const librarySection = new MediaSection()
    librarySection.id = 'libraries'
    librarySection.title = '媒体库'
    for (let i = 0; i < libraries.length; i++) librarySection.items.push(this.toMediaItem(libraries[i]))
    sections.push(librarySection)
    const latest = await this.client.getLatestItems()
    const latestSection = new MediaSection()
    latestSection.id = 'latest'
    latestSection.title = '最近添加'
    for (let i = 0; i < latest.length; i++) latestSection.items.push(this.toMediaItem(latest[i]))
    sections.push(latestSection)
    return sections
  }

  async getChildren(parentId: string): Promise<MediaItem[]> {
    const values = await this.client.getItems(parentId)
    return this.toMediaItems(values)
  }

  async search(keyword: string): Promise<MediaItem[]> {
    return this.toMediaItems(await this.client.searchItems(keyword))
  }

  async getItem(itemId: string): Promise<MediaItem | null> {
    const normalizedItemId = EmbyProvider.normalizeText(itemId)
    if (normalizedItemId.length === 0) return null
    const item = await this.client.getItem(normalizedItemId)
    return item === null ? null : this.toMediaItem(item)
  }

  async resolvePlayback(item: PlaybackQueueItem): Promise<PlaybackSession> {
    const mediaId = EmbyProvider.normalizeText(item.mediaId)
    if (EmbyProvider.normalizeText(item.sourceId) !== this.source.id || mediaId.length === 0) {
      throw new Error('媒体来源或媒体标识不匹配')
    }
    const embyItem = await this.client.getItem(mediaId)
    if (embyItem === null || embyItem.isFolder) throw new Error('Emby 媒体不存在或不可播放')
    const route = await this.client.getPlaybackRoute(embyItem)
    const session = new PlaybackSession()
    session.media.sourceId = this.source.id
    session.media.mediaId = embyItem.id
    session.media.title = embyItem.name
    session.media.subtitle = embyItem.subtitle()
    session.media.artwork = this.client.imageUrl(embyItem)
    session.media.durationMs = embyItem.durationMs()
    session.stream.url = route.url
    // Emby UserData is authoritative. The local unified-history cache is only
    // used for displaying the home page and must not override a newer server
    // resume position when the item is opened again.
    session.startPositionMs = item.startFromBeginning ? 0 : embyItem.resumePositionMs()
    session.durationMs = embyItem.durationMs()
    // Keep the queue metadata aligned with the authoritative session values;
    // a later queue refresh must not reintroduce a stale entry-point position.
    item.positionMs = session.startPositionMs
    item.durationMs = session.durationMs
    session.contextJson = route.context.encode()
    session.queue = [item]
    session.queueIndex = 0
    return session
  }

  async resolve(item: PlaybackQueueItem): Promise<PlaybackSession> {
    return this.resolvePlayback(item)
  }

  async refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]> {
    const sessionSourceId = EmbyProvider.normalizeText(session.media.sourceId)
    const sessionMediaId = EmbyProvider.normalizeText(session.media.mediaId)
    const sessionQueue: PlaybackQueueItem[] = Array.isArray(session.queue) ? session.queue : []
    if (sessionSourceId !== this.source.id || sessionMediaId.length === 0) {
      return sessionQueue
    }
    if (sessionQueue.length > 1) {
      return sessionQueue
    }
    // A single-item launch (for example from Continue Watching) has no page
    // list to reuse. For episodes, rebuild the queue from the owning season so
    // auto-next still works without crossing libraries or Emby sources.
    const current = await this.client.getItem(sessionMediaId)
    const parentId = current === null ? '' : EmbyProvider.normalizeText(current.parentId)
    if (current === null || current.type !== 'Episode' || parentId.length === 0) {
      return sessionQueue
    }
    const siblings = await this.client.getItems(parentId, 0, false, 'Episode', 'IndexNumber', 'Ascending')
    const queue: PlaybackQueueItem[] = []
    for (let i = 0; i < siblings.length; i++) {
      const sibling = siblings[i]
      if (sibling.isFolder) continue
      const queueItem = this.toQueueItem(this.toMediaItem(sibling))
      for (let j = 0; j < sessionQueue.length; j++) {
        const previous = sessionQueue[j]
        if (previous === null || typeof previous !== 'object' || Array.isArray(previous)) continue
        if (EmbyProvider.normalizeText(previous.sourceId) === queueItem.sourceId &&
          EmbyProvider.normalizeText(previous.mediaId) === queueItem.mediaId) {
          queueItem.positionMs = PlaybackQueueItem.normalizePositionMs(previous.positionMs)
          const previousDurationMs = PlaybackQueueItem.normalizeDurationMs(previous.durationMs)
          if (previousDurationMs > 0) queueItem.durationMs = previousDurationMs
          if (queueItem.durationMs > 0) {
            queueItem.positionMs = Math.min(queueItem.positionMs, queueItem.durationMs)
          }
          queueItem.startFromBeginning = previous.startFromBeginning
          queueItem.variantId = previous.variantId
          break
        }
      }
      queue.push(queueItem)
    }
    return queue.some((item: PlaybackQueueItem) => item.mediaId === sessionMediaId) ? queue : sessionQueue
  }

  createReporter(media: PlaybackMedia, context: EmbyPlaybackContext): EmbyPlaybackReporter {
    return new EmbyPlaybackReporter(this.config, media, context)
  }

  createReporterForSession(session: PlaybackSession): EmbyPlaybackReporter | null {
    const context = EmbyPlaybackContext.decode(session.contextJson)
    if (context === null || EmbyProvider.normalizeText(session.media.sourceId) !== this.source.id) return null
    return this.createReporter(session.media, context)
  }

  private toMediaItems(values: EmbyItem[]): MediaItem[] {
    const result: MediaItem[] = []
    for (let i = 0; i < values.length; i++) result.push(this.toMediaItem(values[i]))
    return result
  }

  private toMediaItem(item: EmbyItem): MediaItem {
    const result = new MediaItem()
    result.sourceId = this.source.id
    result.id = item.id
    result.title = item.name
    result.subtitle = item.subtitle()
    result.overview = item.overview
    result.poster = this.client.imageUrl(item)
    result.durationMs = item.durationMs()
    result.positionMs = item.resumePositionMs()
    result.year = item.productionYear
    result.playable = !item.isFolder
    result.browsable = item.isFolder
    result.type = EmbyProvider.mapType(item.type)
    return result
  }

  private toQueueItem(item: MediaItem): PlaybackQueueItem {
    const queueItem = new PlaybackQueueItem()
    queueItem.sourceId = item.sourceId
    queueItem.mediaId = item.id
    queueItem.title = item.title
    queueItem.subtitle = item.subtitle
    queueItem.artwork = item.poster
    queueItem.positionMs = PlaybackQueueItem.normalizePositionMs(item.positionMs)
    queueItem.durationMs = PlaybackQueueItem.normalizeDurationMs(item.durationMs)
    queueItem.variantId = item.variantId
    return queueItem
  }

  private static mapType(type: string): MediaItemType {
    switch (type) {
      case 'Movie': return MediaItemType.MOVIE
      case 'Series': return MediaItemType.SERIES
      case 'Season': return MediaItemType.SEASON
      case 'Episode': return MediaItemType.EPISODE
      case 'CollectionFolder': return MediaItemType.COLLECTION
      case 'Folder': return MediaItemType.FOLDER
      default: return MediaItemType.VIDEO
    }
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
