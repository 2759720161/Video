import { MediaItem, MediaItemType } from '../../core/media/MediaItem'
import { MediaSection } from '../../core/media/MediaSection'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { PlaybackSession } from '../../core/playback/PlaybackSession'
import { PlaybackSubtitle } from '../../core/playback/PlaybackSubtitle'
import { PlaybackHistoryReporter } from '../../core/playback/PlaybackHistoryReporter'
import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import type { MediaProvider } from '../base/MediaProvider'
import { WebDavClient } from './WebDavClient'
import { WebDavEntry } from './WebDavModels'
import { WebDavSourceConfigCodec } from './WebDavSourceConfig'
import { SecureCredentialStore } from '../../services/security/SecureCredentialStore'
import { ProviderHealth } from '../../core/media/ProviderHealth'

export class WebDavProvider implements MediaProvider {
  private source: MediaSourceInstance
  private client: WebDavClient

  private constructor(source: MediaSourceInstance, client: WebDavClient) {
    this.source = source
    this.client = client
  }

  static async fromSource(source: MediaSourceInstance): Promise<WebDavProvider> {
    const config = WebDavSourceConfigCodec.decode(source.configJson)
    if (config === null) throw new Error('WebDAV 配置无效')
    const credential = await SecureCredentialStore.getInstance().get(source.id)
    if (credential !== null) {
      const password = credential.values['password']
      if (typeof password === 'string') config.password = password
    }
    return new WebDavProvider(source, new WebDavClient(config))
  }

  getSourceId(): string { return this.source.id }

  hasCapability(capability: ProviderCapability): boolean {
    return capability === ProviderCapability.HOME || capability === ProviderCapability.BROWSE ||
      capability === ProviderCapability.RESUME
  }

  async getHome(): Promise<MediaSection[]> {
    const section = new MediaSection()
    section.id = ''
    section.title = this.source.name
    section.items = await this.getChildren('')
    return [section]
  }

  async getChildren(parentId: string): Promise<MediaItem[]> {
    const normalizedParentId = WebDavProvider.normalizeText(parentId)
    const entries = await this.client.list(normalizedParentId)
    const result: MediaItem[] = []
    const seen: Record<string, boolean> = {}
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      const normalizedHref = WebDavProvider.normalizeText(entry.href)
      if (normalizedHref.length === 0 || normalizedHref === normalizedParentId) continue
      if (seen[normalizedHref] === true) continue
      seen[normalizedHref] = true
      entry.href = normalizedHref
      result.push(this.toMediaItem(entry))
    }
    result.sort((left: MediaItem, right: MediaItem) => {
      if (left.browsable !== right.browsable) return left.browsable ? -1 : 1
      return left.title.toLowerCase().localeCompare(right.title.toLowerCase())
    })
    return result
  }

  async search(_keyword: string): Promise<MediaItem[]> { return [] }

  async getResumeItems(limit: number = 0): Promise<MediaItem[]> {
    const records = await new PlaybackHistoryStore().getAll()
    const result: MediaItem[] = []
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      if (record.sourceId !== this.source.id) continue
      if (record.durationMs > 0 && record.positionMs / record.durationMs >= 0.995) continue
      const item = new MediaItem()
      item.sourceId = this.source.id
      item.id = record.mediaId
      item.title = record.title
      item.subtitle = record.subtitle
      item.poster = record.artwork
      item.positionMs = record.positionMs
      item.durationMs = record.durationMs
      item.playable = true
      result.push(item)
      if (limit > 0 && result.length >= limit) break
    }
    return result
  }

  async testConnection(): Promise<ProviderHealth> {
    const health = new ProviderHealth()
    const started = Date.now()
    try {
      await this.client.list('')
      health.ok = true
      health.message = 'WebDAV 连接正常'
    } catch (err) {
      health.ok = false
      health.message = err instanceof Error ? err.message : 'WebDAV 连接失败'
    }
    health.latencyMs = Math.max(0, Date.now() - started)
    return health
  }
  async getItem(itemId: string): Promise<MediaItem | null> {
    const normalizedItemId = WebDavProvider.normalizeText(itemId)
    if (normalizedItemId.length === 0) return null
    const slash = normalizedItemId.lastIndexOf('/')
    const parentId = slash <= 0 ? '/' : normalizedItemId.substring(0, slash + 1)
    const items = await this.getChildren(parentId)
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === normalizedItemId) return items[i]
    }
    return null
  }

  async resolvePlayback(item: PlaybackQueueItem): Promise<PlaybackSession> {
    const mediaId = WebDavProvider.normalizeText(item.mediaId)
    if (WebDavProvider.normalizeText(item.sourceId) !== this.source.id || mediaId.length === 0) {
      throw new Error('媒体来源或媒体标识不匹配')
    }
    const session = new PlaybackSession()
    session.media.sourceId = this.source.id
    session.media.mediaId = mediaId
    session.media.title = item.title
    session.media.subtitle = item.subtitle
    session.media.artwork = item.artwork
    const durationMs = Number.isFinite(item.durationMs) && item.durationMs > 0 ? Math.floor(item.durationMs) : 0
    session.media.durationMs = durationMs
    session.stream.url = this.client.streamUrl(mediaId)
    session.stream.headers = await this.client.streamHeaders(mediaId)
    let resumePositionMs = Number.isFinite(item.positionMs) ? Math.max(0, Math.floor(item.positionMs)) : 0
    if (!item.startFromBeginning && resumePositionMs <= 0) {
      try {
        const history = await new PlaybackHistoryStore().get(this.source.id, mediaId)
        if (history !== null && Number.isFinite(history.positionMs)) {
          resumePositionMs = Math.max(0, Math.floor(history.positionMs))
        }
      } catch (_) {
        // History is an optional resume hint; a database failure must not
        // prevent the remote stream from opening.
      }
    }
    if (durationMs > 0) resumePositionMs = Math.min(resumePositionMs, durationMs)
    session.startPositionMs = item.startFromBeginning ? 0 : resumePositionMs
    session.durationMs = durationMs
    session.subtitles = await this.findSidecarSubtitles(mediaId)
    return session
  }

  async refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]> {
    const sessionSourceId = WebDavProvider.normalizeText(session.media.sourceId)
    const sessionMediaId = WebDavProvider.normalizeText(session.media.mediaId)
    const sessionQueue: PlaybackQueueItem[] = Array.isArray(session.queue) ? session.queue : []
    if (sessionSourceId !== this.source.id || sessionMediaId.length === 0) {
      return sessionQueue
    }
    const slash = sessionMediaId.lastIndexOf('/')
    const parentId = slash <= 0 ? '/' : sessionMediaId.substring(0, slash + 1)
    const items = await this.getChildren(parentId)
    const queue: PlaybackQueueItem[] = []
    for (let i = 0; i < items.length; i++) {
      const media = items[i]
      if (!media.playable) continue
      const queueItem = this.toQueueItem(media)
      for (let j = 0; j < sessionQueue.length; j++) {
        const previous = sessionQueue[j]
        if (previous === null || typeof previous !== 'object' || Array.isArray(previous)) continue
        if (WebDavProvider.normalizeText(previous.sourceId) === queueItem.sourceId &&
          WebDavProvider.normalizeText(previous.mediaId) === queueItem.mediaId) {
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
    const currentIndex = queue.findIndex((item: PlaybackQueueItem) =>
      item.sourceId === sessionSourceId && item.mediaId === sessionMediaId)
    if (currentIndex < 0) return sessionQueue
    return queue
  }

  createReporterForSession(session: PlaybackSession): PlaybackReporter | null {
    if (WebDavProvider.normalizeText(session.media.sourceId) !== this.source.id) return null
    return new PlaybackHistoryReporter(session.media)
  }

  private toMediaItem(entry: WebDavEntry): MediaItem {
    const item = new MediaItem()
    const href = WebDavProvider.normalizeText(entry.href)
    const name = WebDavProvider.normalizeText(entry.name)
    item.sourceId = this.source.id
    item.id = href
    item.title = name.length > 0 ? name : href
    item.playable = !entry.isFolder && this.isPlayableMedia(entry)
    item.browsable = entry.isFolder
    item.type = entry.isFolder ? MediaItemType.FOLDER : MediaItemType.VIDEO
    item.subtitle = entry.isFolder ? '文件夹' : this.describeFile(entry)
    return item
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

  private isPlayableMedia(entry: WebDavEntry): boolean {
    const contentType = WebDavProvider.normalizeText(entry.contentType).toLowerCase()
    if (contentType.startsWith('video/')) return true
    if (contentType.startsWith('audio/')) return true
    const name = WebDavProvider.normalizeText(entry.name).toLowerCase()
    return /\.(mp4|mkv|webm|mov|avi|m4v|ts|m3u8|mp3|flac|aac|wav|ogg|m4a)$/.test(name)
  }

  private async findSidecarSubtitles(mediaId: string): Promise<PlaybackSubtitle[]> {
    const slash = mediaId.lastIndexOf('/')
    if (slash < 0) return []
    const parentId = mediaId.substring(0, slash + 1)
    let mediaName = mediaId.substring(slash + 1)
    try { mediaName = decodeURIComponent(mediaName) } catch (_) {}
    const dot = mediaName.lastIndexOf('.')
    const baseName = (dot > 0 ? mediaName.substring(0, dot) : mediaName).toLowerCase()
    let entries: WebDavEntry[]
    try {
      entries = await this.client.list(parentId)
    } catch (_) {
      // Sidecar subtitles are optional. A directory listing failure must not
      // prevent the already playable video stream from being opened.
      return []
    }
    const subtitles: PlaybackSubtitle[] = []
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (entry.isFolder || !this.isSubtitleFile(entry.name)) continue
      let subtitleName = entry.name
      try { subtitleName = decodeURIComponent(subtitleName) } catch (_) {}
      const subtitleBase = subtitleName.substring(0, subtitleName.lastIndexOf('.')).toLowerCase()
      if (subtitleBase !== baseName && !subtitleBase.startsWith(baseName + '.')) continue
      const subtitle = new PlaybackSubtitle()
      subtitle.id = entry.href
      subtitle.displayName = subtitleName
      const suffix = subtitleBase.length > baseName.length ? subtitleBase.substring(baseName.length + 1) : ''
      subtitle.language = suffix
      subtitle.title = suffix.length > 0 ? suffix : subtitleName
      subtitle.isDefault = suffix.length === 0 || suffix === 'default'
      subtitle.url = this.client.streamUrl(entry.href)
      try {
        subtitle.headers = await this.client.subtitleHeaders(entry.href)
      } catch (_) {
        // Subtitle authentication is optional for playback. Keep the
        // candidate with empty headers so public sidecars remain usable, and
        // let the player continue to the next candidate if this one fails.
        subtitle.headers = {}
      }
      subtitles.push(subtitle)
    }
    return subtitles
  }

  private isSubtitleFile(name: string): boolean {
    return /\.(srt|ass|ssa|vtt|sub)$/i.test(name)
  }

  private describeFile(entry: WebDavEntry): string {
    const name = WebDavProvider.normalizeText(entry.name)
    const contentType = WebDavProvider.normalizeText(entry.contentType)
    const contentLength = WebDavProvider.safeNumber(entry.contentLength)
    if (/\.(srt|ass|ssa|vtt|sub|idx)$/i.test(name)) return '字幕文件'
    if (contentLength <= 0) return contentType
    const units = ['B', 'KB', 'MB', 'GB']
    let value = contentLength
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
    return value.toFixed(unit === 0 ? 0 : 1) + ' ' + units[unit]
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static safeNumber(value: number): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0
  }
}
