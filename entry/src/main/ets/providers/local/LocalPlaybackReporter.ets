import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { PlaybackHistoryRecord } from '../../models/PlaybackHistoryRecord'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import { Logger } from '../../utils/Logger'
import { LocalPlaybackIdentity } from './LocalPlaybackIdentity'

const logger = new Logger('LocalPlaybackReporter')

/** 本地播放生命周期上报：保留旧本地扩展数据，同时写入统一历史缓存。 */
export class LocalPlaybackReporter implements PlaybackReporter {
  private record: LocalVideoRecord
  private localStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private historyStore: PlaybackHistoryStore = new PlaybackHistoryStore()

  constructor(record: LocalVideoRecord) {
    this.record = LocalPlaybackReporter.copyRecord(record)
  }

  async started(positionMs: number, durationMs: number, _playing: boolean, _speed: number): Promise<void> {
    await this.persist(positionMs, durationMs)
  }

  async progress(positionMs: number, durationMs: number, _playing: boolean, _speed: number,
    _eventName: string = ''): Promise<void> {
    await this.persist(positionMs, durationMs)
  }

  async stopped(positionMs: number, durationMs: number, _speed: number): Promise<void> {
    await this.persist(positionMs, durationMs)
  }

  private async persist(positionMs: number, durationMs: number): Promise<void> {
    try {
      if (Number.isFinite(durationMs) && durationMs > 0) {
        this.record.durationMs = Math.floor(durationMs)
      } else if (Number.isFinite(this.record.durationMs) && this.record.durationMs > 0) {
        this.record.durationMs = Math.floor(this.record.durationMs)
      } else {
        this.record.durationMs = 0
      }
      const normalizedPositionMs = Number.isFinite(positionMs) ? Math.max(0, Math.floor(positionMs)) : 0
      this.record.positionMs = this.record.durationMs > 0
        ? Math.min(normalizedPositionMs, this.record.durationMs) : normalizedPositionMs
      await this.localStore.upsert(this.record)
      const history = new PlaybackHistoryRecord()
      history.sourceId = 'local'
      history.mediaId = LocalPlaybackIdentity.fromRecord(this.record)
      history.title = this.record.fileName
      history.artwork = this.record.coverUri
      history.artworkRef = ''
      history.positionMs = this.record.positionMs
      history.durationMs = this.record.durationMs
      await this.historyStore.upsert(history)
    } catch (err) {
      logger.warn('local playback history report failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private static copyRecord(record: LocalVideoRecord): LocalVideoRecord {
    const copy = new LocalVideoRecord()
    const storedKey = LocalPlaybackReporter.normalizeText(record.fileKey)
    const fileUri = LocalPlaybackReporter.safeText(record.fileUri)
    const fileName = LocalPlaybackReporter.safeText(record.fileName)
    copy.fileKey = storedKey.length > 0 ? storedKey :
      `${fileUri}|${record.fileSize}|${fileName}`
    copy.fileUri = fileUri
    copy.fileName = fileName
    copy.fileSize = LocalPlaybackReporter.safeNumber(record.fileSize)
    copy.coverUri = LocalPlaybackReporter.safeText(record.coverUri)
    copy.durationMs = record.durationMs
    copy.positionMs = record.positionMs
    copy.externalSubtitleFileName = LocalPlaybackReporter.safeText(record.externalSubtitleFileName)
    copy.externalSubtitleUri = LocalPlaybackReporter.safeText(record.externalSubtitleUri)
    return copy
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
