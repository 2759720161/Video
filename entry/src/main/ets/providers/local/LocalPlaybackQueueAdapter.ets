import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalPlaybackIdentity } from './LocalPlaybackIdentity'

/** 本地记录转换留在来源层，公共队列不依赖本地模型。 */
export class LocalPlaybackQueueAdapter {
  static fromRecord(record: LocalVideoRecord): PlaybackQueueItem {
    const item = new PlaybackQueueItem()
    item.sourceId = 'local'
    // URI 只留在 LocalPlaybackResolver 的内存映射中，公共队列只保存不可读的稳定身份。
    item.mediaId = LocalPlaybackIdentity.fromRecord(record)
    item.title = LocalPlaybackQueueAdapter.safeText(record.fileName)
    item.subtitle = LocalPlaybackQueueAdapter.describeVideo(record.fileSize)
    item.artwork = LocalPlaybackQueueAdapter.safeText(record.coverUri)
    item.durationMs = PlaybackQueueItem.normalizeDurationMs(record.durationMs)
    const normalizedPositionMs = PlaybackQueueItem.normalizePositionMs(record.positionMs)
    item.positionMs = item.durationMs > 0
      ? Math.min(normalizedPositionMs, item.durationMs) : normalizedPositionMs
    return item
  }

  private static describeVideo(fileSize: number): string {
    if (!Number.isFinite(fileSize) || fileSize <= 0) return '本地视频'
    const units = ['B', 'KB', 'MB', 'GB']
    let value = fileSize
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
    return value.toFixed(unit === 0 ? 0 : 1) + ' ' + units[unit]
  }

  private static safeText(value: string): string {
    return typeof value === 'string' ? value : ''
  }
}
