import type { MediaItem } from '../../core/media/MediaItem'
import type { MediaSection } from '../../core/media/MediaSection'
import type { PlaybackSession } from '../../core/playback/PlaybackSession'
import type { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'

/** 来源层的最小能力边界；Provider 负责数据和播放解析，页面只消费公共模型。 */
export interface MediaProvider {
  getSourceId(): string
  hasCapability(capability: ProviderCapability): boolean
  getHome(): Promise<MediaSection[]>
  getChildren(parentId: string): Promise<MediaItem[]>
  search(keyword: string): Promise<MediaItem[]>
  getItem(itemId: string): Promise<MediaItem | null>
  resolvePlayback(item: PlaybackQueueItem): Promise<PlaybackSession>
  resolve(item: PlaybackQueueItem): Promise<PlaybackSession>
  refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]>
  createReporterForSession(session: PlaybackSession): PlaybackReporter | null
}
