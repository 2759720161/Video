import { common } from '@kit.AbilityKit'
import type { PlaybackResolver } from '../../core/playback/PlaybackResolver'
import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { PlaybackSession } from '../../core/playback/PlaybackSession'
import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { UserDownloadFolder } from '../../services/UserDownloadFolder'
import { LocalPlaybackQueueAdapter } from './LocalPlaybackQueueAdapter'

/** 迁移期本地解析器：URI 仅保留在来源内部，公共队列使用稳定的 opaque mediaId。 */
export class LocalPlaybackResolver implements PlaybackResolver {
  private records: Map<string, LocalVideoRecord> = new Map()

  private context: common.UIAbilityContext

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  remember(record: LocalVideoRecord): PlaybackQueueItem {
    const item = LocalPlaybackQueueAdapter.fromRecord(record)
    const snapshot = new LocalVideoRecord()
    snapshot.fileKey = item.mediaId
    snapshot.fileUri = LocalPlaybackResolver.normalizeText(record.fileUri)
    snapshot.fileName = LocalPlaybackResolver.normalizeText(record.fileName)
    snapshot.fileSize = LocalPlaybackResolver.safeNumber(record.fileSize)
    snapshot.coverUri = LocalPlaybackResolver.safeText(record.coverUri)
    this.records.set(item.mediaId, snapshot)
    const legacyKey = LocalPlaybackResolver.normalizeText(record.fileKey)
    if (legacyKey.length > 0 && legacyKey !== item.mediaId) this.records.set(legacyKey, snapshot)
    return item
  }

  async resolve(item: PlaybackQueueItem): Promise<PlaybackSession> {
    const sourceId = LocalPlaybackResolver.normalizeText(item.sourceId)
    const mediaId = LocalPlaybackResolver.normalizeText(item.mediaId)
    const record = this.records.get(mediaId)
    if (sourceId !== 'local' || mediaId.length === 0 || record === undefined || record.fileUri.length === 0) {
      throw new Error('本地视频不存在，请重新选择')
    }
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri) &&
      !await LocalFilePicker.authorizeExistingUri(this.context, record.fileUri)) {
      throw new Error('无法访问视频，请重新授权或选择文件')
    }
    const session = new PlaybackSession()
    session.media.sourceId = 'local'
    session.media.mediaId = mediaId
    session.media.title = item.title
    session.media.subtitle = item.subtitle
    session.media.artwork = item.artwork
    const durationMs = PlaybackQueueItem.normalizeDurationMs(item.durationMs)
    const normalizedPositionMs = PlaybackQueueItem.normalizePositionMs(item.positionMs)
    const positionMs = item.startFromBeginning ? 0 :
      (durationMs > 0 ? Math.min(normalizedPositionMs, durationMs) : normalizedPositionMs)
    session.media.durationMs = durationMs
    session.stream.url = record.fileUri
    session.stream.isLocalFile = true
    session.stream.localFileSize = record.fileSize
    session.startPositionMs = positionMs
    session.durationMs = durationMs
    return session
  }

  async refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]> {
    const records = await UserDownloadFolder.listSiblingVideoRecords(this.context, session.stream.url)
    const sessionQueue: PlaybackQueueItem[] = Array.isArray(session.queue) ? session.queue : []
    if (records === null || records.length <= 1) return sessionQueue
    const rebuilt: PlaybackQueueItem[] = []
    for (let i = 0; i < records.length; i++) {
      const item = this.remember(records[i])
      for (let j = 0; j < sessionQueue.length; j++) {
        const previous = sessionQueue[j]
        if (previous === null || typeof previous !== 'object' || Array.isArray(previous)) continue
        if (LocalPlaybackResolver.normalizeText(previous.sourceId) === item.sourceId &&
          LocalPlaybackResolver.normalizeText(previous.mediaId) === item.mediaId) {
          item.positionMs = PlaybackQueueItem.normalizePositionMs(previous.positionMs)
          const previousDurationMs = PlaybackQueueItem.normalizeDurationMs(previous.durationMs)
          if (previousDurationMs > 0) item.durationMs = previousDurationMs
          if (item.durationMs > 0) {
            item.positionMs = Math.min(item.positionMs, item.durationMs)
          }
          item.startFromBeginning = previous.startFromBeginning
          item.variantId = previous.variantId
          break
        }
      }
      rebuilt.push(item)
    }
    return rebuilt
  }

  createReporterForSession(_session: PlaybackSession): PlaybackReporter | null { return null }

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
