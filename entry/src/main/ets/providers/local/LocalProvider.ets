import { common } from '@kit.AbilityKit'
import { MediaItem, MediaItemType } from '../../core/media/MediaItem'
import { MediaSection } from '../../core/media/MediaSection'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import type { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import type { PlaybackSession } from '../../core/playback/PlaybackSession'
import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import type { MediaProvider } from '../base/MediaProvider'
import { LocalPlaybackResolver } from './LocalPlaybackResolver'
import { LocalPlaybackReporter } from './LocalPlaybackReporter'
import { LocalPlaybackIdentity } from './LocalPlaybackIdentity'
import { UserDownloadFolder, UserFolderEntry } from '../../services/UserDownloadFolder'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'

/** 迁移期 Local Provider：复用现有本地文件与权限服务。 */
export class LocalProvider implements MediaProvider {
  private resolver: LocalPlaybackResolver
  private context: common.UIAbilityContext
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private records: Map<string, LocalVideoRecord> = new Map()

  constructor(context: common.UIAbilityContext) {
    this.context = context
    this.resolver = new LocalPlaybackResolver(context)
  }

  getSourceId(): string { return 'local' }

  hasCapability(capability: ProviderCapability): boolean {
    return capability === ProviderCapability.HOME || capability === ProviderCapability.BROWSE ||
      capability === ProviderCapability.RESUME || capability === ProviderCapability.PROGRESS_SYNC
  }

  async getHome(): Promise<MediaSection[]> {
    const section = new MediaSection()
    section.id = ''
    section.title = '本机文件夹'
    section.items = await this.getChildren('')
    return [section]
  }

  async getChildren(parentId: string): Promise<MediaItem[]> {
    const entries = await UserDownloadFolder.listOwnDirectory(this.context, LocalProvider.normalizeText(parentId))
    if (entries === null) return []
    const historyByKey = await this.loadHistoryByKey()
    const result: MediaItem[] = []
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (entry.isDirectory) {
        result.push(this.toFolderItem(entry))
        continue
      }
      const record = this.mergeHistory(entry.video, historyByKey.get(this.fileKey(entry.video)))
      this.cacheRecord(record)
      result.push(this.toVideoItem(record))
    }
    return result
  }

  async search(_keyword: string): Promise<MediaItem[]> { return [] }

  async getItem(itemId: string): Promise<MediaItem | null> {
    const record = await this.findRecord(itemId)
    return record === null ? null : this.toVideoItem(record)
  }

  async resolvePlayback(item: PlaybackQueueItem): Promise<PlaybackSession> {
    const mediaId = LocalProvider.normalizeText(item.mediaId)
    if (LocalProvider.normalizeText(item.sourceId) !== 'local' || mediaId.length === 0) {
      throw new Error('媒体来源或媒体标识不匹配')
    }
    item.sourceId = 'local'
    item.mediaId = mediaId
    const record = await this.findRecord(mediaId)
    if (record === null) throw new Error('本地视频不存在，请重新选择')
    // Keep the Provider-side cache in sync with the resolver so a session
    // opened from a persisted opaque id can still create its reporter.
    this.cacheRecord(record)
    this.resolver.remember(record)
    if (item.startFromBeginning) item.positionMs = 0
    return this.resolver.resolve(item)
  }

  async resolve(item: PlaybackQueueItem): Promise<PlaybackSession> {
    return this.resolvePlayback(item)
  }

  async refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]> {
    return this.resolver.refreshQueue(session)
  }

  createReporterForSession(session: PlaybackSession): PlaybackReporter | null {
    const sourceId = LocalProvider.normalizeText(session.media.sourceId)
    const mediaId = LocalProvider.normalizeText(session.media.mediaId)
    if (sourceId !== 'local' || mediaId.length === 0) return null
    const record = this.records.get(mediaId)
    return record === undefined ? null : new LocalPlaybackReporter(record)
  }

  /** 将页面持有的本地记录登记到当前 Provider，临时 URI 不进入公共队列。 */
  rememberRecord(record: LocalVideoRecord): MediaItem {
    const cached = this.cacheRecord(record)
    this.resolver.remember(cached)
    return this.toVideoItem(cached)
  }

  private async findRecord(rawItemId: string): Promise<LocalVideoRecord | null> {
    const itemId = LocalProvider.normalizeText(rawItemId)
    if (itemId.length === 0) return null
    const cached = this.records.get(itemId)
    if (cached !== undefined) return cached
    try {
      const history = await this.historyStore.getByFileKey(itemId)
      if (history !== null) return this.cacheRecord(history)
    } catch (_) {}
    if (itemId.startsWith('local_')) {
      try {
        const history = await this.historyStore.getAll()
        for (let i = 0; i < history.length; i++) {
          if (LocalPlaybackIdentity.fromRecord(history[i]) === itemId) return this.cacheRecord(history[i])
        }
      } catch (_) {}
    }
    const delimiter = itemId.indexOf('|')
    if (delimiter <= 0) return null
    const fileUri = itemId.substring(0, delimiter)
    const siblings = await UserDownloadFolder.listSiblingVideoRecords(this.context, fileUri)
    if (siblings === null) return null
    for (let i = 0; i < siblings.length; i++) {
      if (this.fileKey(siblings[i]) === itemId || LocalPlaybackIdentity.fromRecord(siblings[i]) === itemId) {
        return this.cacheRecord(siblings[i])
      }
    }
    return null
  }

  private async loadHistoryByKey(): Promise<Map<string, LocalVideoRecord>> {
    const records = new Map<string, LocalVideoRecord>()
    try {
      const history = await this.historyStore.getAll()
      for (let i = 0; i < history.length; i++) records.set(this.fileKey(history[i]), history[i])
    } catch (_) {}
    return records
  }

  private mergeHistory(record: LocalVideoRecord, history: LocalVideoRecord | undefined): LocalVideoRecord {
    if (history === undefined) return record
    const merged = new LocalVideoRecord()
    merged.fileKey = this.fileKey(record)
    merged.fileUri = record.fileUri
    merged.fileName = record.fileName
    merged.fileSize = record.fileSize
    merged.coverUri = history.coverUri.length > 0 ? history.coverUri : record.coverUri
    merged.durationMs = history.durationMs > 0 ? history.durationMs : record.durationMs
    const historyPositionMs = Number.isFinite(history.positionMs) ? Math.max(0, Math.floor(history.positionMs)) : 0
    merged.positionMs = merged.durationMs > 0
      ? Math.min(historyPositionMs, merged.durationMs) : historyPositionMs
    merged.externalSubtitleFileName = history.externalSubtitleFileName
    merged.externalSubtitleUri = history.externalSubtitleUri
    return merged
  }

  private cacheRecord(record: LocalVideoRecord): LocalVideoRecord {
    record.sourceId = 'local'
    record.fileKey = this.fileKey(record)
    this.records.set(LocalPlaybackIdentity.fromRecord(record), record)
    if (record.fileKey.length > 0) this.records.set(record.fileKey, record)
    return record
  }

  private toFolderItem(entry: UserFolderEntry): MediaItem {
    const item = new MediaItem()
    item.sourceId = 'local'
    item.id = entry.relativePath
    item.title = entry.name
    item.subtitle = entry.isM3u8Package ? '媒体文件夹' :
      String(entry.childDirectoryCount) + ' 个文件夹 · ' + String(entry.childVideoCount) + ' 个视频'
    item.type = MediaItemType.FOLDER
    item.browsable = true
    return item
  }

  private toVideoItem(record: LocalVideoRecord): MediaItem {
    const item = new MediaItem()
    item.sourceId = 'local'
    item.id = LocalPlaybackIdentity.fromRecord(record)
    item.title = record.fileName
    item.poster = record.coverUri
    item.durationMs = record.durationMs
    item.positionMs = record.positionMs
    item.subtitle = this.describeVideo(record)
    item.type = MediaItemType.VIDEO
    item.playable = true
    return item
  }

  private fileKey(record: LocalVideoRecord): string {
    const storedKey = LocalProvider.normalizeText(record.fileKey)
    return storedKey.length > 0 ? storedKey :
      LocalProvider.safeText(record.fileUri) + '|' + LocalProvider.safeNumber(record.fileSize) + '|' + LocalProvider.safeText(record.fileName)
  }

  private describeVideo(record: LocalVideoRecord): string {
    const fileSize = LocalProvider.safeNumber(record.fileSize)
    if (fileSize <= 0) return '本地视频'
    const units = ['B', 'KB', 'MB', 'GB']
    let value = fileSize
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
    return value.toFixed(unit === 0 ? 0 : 1) + ' ' + units[unit]
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static safeText(value: string): string {
    return typeof value === 'string' ? value : ''
  }

  private static safeNumber(value: number): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0
  }
}
