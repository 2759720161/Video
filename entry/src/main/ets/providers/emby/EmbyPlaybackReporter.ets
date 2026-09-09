import { EmbyPlaybackContext, EmbyServerConfig } from './EmbyModels'
import { EmbyClient } from './EmbyClient'
import { Logger } from '../../utils/Logger'
import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { PlaybackMedia } from '../../core/playback/PlaybackMedia'
import { PlaybackHistoryRecord } from '../../models/PlaybackHistoryRecord'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import { ArtworkResolver } from '../../services/ArtworkResolver'

const logger = new Logger('EmbyPlaybackReporter')

export class EmbyPlaybackReporter implements PlaybackReporter {
  private context: EmbyPlaybackContext
  private config: EmbyServerConfig
  private media: PlaybackMedia
  private historyStore: PlaybackHistoryStore = new PlaybackHistoryStore()

  constructor(config: EmbyServerConfig, media: PlaybackMedia, context: EmbyPlaybackContext) {
    this.config = config.copy()
    this.media = new PlaybackMedia()
    this.media.sourceId = EmbyPlaybackReporter.normalizeText(media.sourceId)
    this.media.mediaId = EmbyPlaybackReporter.normalizeText(media.mediaId)
    this.media.title = EmbyPlaybackReporter.normalizeText(media.title)
    this.media.subtitle = EmbyPlaybackReporter.normalizeText(media.subtitle)
    this.media.artwork = EmbyPlaybackReporter.normalizeText(media.artwork)
    this.media.artworkRef = ArtworkResolver.persistedValue('', media.artworkRef)
    this.media.durationMs = Number.isFinite(media.durationMs) && media.durationMs > 0 ? Math.floor(media.durationMs) : 0
    this.context = new EmbyPlaybackContext()
    this.context.itemId = EmbyPlaybackReporter.normalizeText(context.itemId)
    this.context.mediaSourceId = EmbyPlaybackReporter.normalizeText(context.mediaSourceId)
    this.context.playSessionId = EmbyPlaybackReporter.normalizeText(context.playSessionId)
    this.context.playMethod = EmbyPlaybackReporter.normalizeText(context.playMethod)
    if (this.context.playMethod.length === 0) this.context.playMethod = 'DirectStream'
  }

  async started(positionMs: number, durationMs: number, playing: boolean, speed: number): Promise<void> {
    await this.report('/Sessions/Playing', positionMs, durationMs, playing, speed)
    await this.persistHistory(positionMs, durationMs)
  }

  async progress(positionMs: number, durationMs: number, playing: boolean, speed: number,
    eventName: string = 'TimeUpdate'): Promise<void> {
    await this.report('/Sessions/Playing/Progress', positionMs, durationMs, playing, speed, eventName)
    await this.persistHistory(positionMs, durationMs)
  }

  async stopped(positionMs: number, durationMs: number, speed: number): Promise<void> {
    await this.report('/Sessions/Playing/Stopped', positionMs, durationMs, false, speed)
    await this.persistHistory(positionMs, durationMs)
  }

  private async report(endpoint: string, positionMs: number, durationMs: number, playing: boolean,
    speed: number, eventName: string = ''): Promise<void> {
    try {
      await new EmbyClient(this.config).reportPlayback(endpoint, this.context, positionMs, durationMs,
        playing, speed, eventName)
    } catch (err) {
      logger.warn('Emby playback report failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async persistHistory(positionMs: number, durationMs: number): Promise<void> {
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
      // PlaybackSession 的上下文只服务于当前进程；历史记录不保存临时会话标识。
      record.contextJson = ''
      await this.historyStore.upsert(record)
    } catch (err) {
      logger.warn('local playback history cache failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
