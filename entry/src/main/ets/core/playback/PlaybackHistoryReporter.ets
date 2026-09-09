import type { PlaybackReporter } from './PlaybackReporter'
import { PlaybackMedia } from './PlaybackMedia'
import { PlaybackHistoryRecord } from '../../models/PlaybackHistoryRecord'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import { Logger } from '../../utils/Logger'
import { ArtworkResolver } from '../../services/ArtworkResolver'

const logger = new Logger('PlaybackHistoryReporter')

/** 不需要服务端进度同步的远程来源统一写入继续观看历史。 */
export class PlaybackHistoryReporter implements PlaybackReporter {
  private readonly media: PlaybackMedia
  private readonly historyStore: PlaybackHistoryStore = new PlaybackHistoryStore()

  constructor(media: PlaybackMedia) {
    this.media = new PlaybackMedia()
    this.media.sourceId = PlaybackHistoryReporter.normalizeText(media.sourceId)
    this.media.mediaId = PlaybackHistoryReporter.normalizeText(media.mediaId)
    this.media.title = PlaybackHistoryReporter.normalizeText(media.title)
    this.media.subtitle = PlaybackHistoryReporter.normalizeText(media.subtitle)
    this.media.artwork = PlaybackHistoryReporter.normalizeText(media.artwork)
    this.media.artworkRef = ArtworkResolver.persistedValue('', media.artworkRef)
    this.media.durationMs = Number.isFinite(media.durationMs) && media.durationMs > 0 ? Math.floor(media.durationMs) : 0
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
    if (this.media.sourceId.length === 0 || this.media.mediaId.length === 0) return
    try {
      const record = new PlaybackHistoryRecord()
      record.sourceId = this.media.sourceId
      record.mediaId = this.media.mediaId
      record.title = this.media.title
      record.subtitle = this.media.subtitle
      record.artworkRef = this.media.artworkRef
      record.artwork = ArtworkResolver.persistedValue(this.media.artwork, this.media.artworkRef)
      record.durationMs = Number.isFinite(durationMs) && durationMs > 0 ? Math.floor(durationMs) :
        (Number.isFinite(this.media.durationMs) && this.media.durationMs > 0 ? Math.floor(this.media.durationMs) : 0)
      const normalizedPositionMs = Number.isFinite(positionMs) ? Math.max(0, Math.floor(positionMs)) : 0
      record.positionMs = record.durationMs > 0
        ? Math.min(normalizedPositionMs, record.durationMs) : normalizedPositionMs
      await this.historyStore.upsert(record)
    } catch (err) {
      logger.warn('播放历史写入失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
