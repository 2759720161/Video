import type { PlaybackSession } from './PlaybackSession'
import type { PlaybackQueueItem } from './PlaybackQueueItem'
import type { PlaybackReporter } from './PlaybackReporter'

/** 启动方使用的来源解析能力，由 Provider 适配器实现。 */
export interface PlaybackResolver {
  resolve(item: PlaybackQueueItem): Promise<PlaybackSession>
  refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]>
  /** 队列切换后为新媒体创建独立上报器；无上报能力的来源返回 null。 */
  createReporterForSession(session: PlaybackSession): PlaybackReporter | null
}
