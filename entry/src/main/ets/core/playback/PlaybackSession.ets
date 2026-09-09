import { PlaybackMedia } from './PlaybackMedia'
import { PlaybackStream } from './PlaybackStream'
import { PlaybackQueueItem } from './PlaybackQueueItem'
import { PlaybackSubtitle } from './PlaybackSubtitle'

/** 进程内的播放启动会话，与系统媒体控制使用的状态快照分离。 */
export class PlaybackSession {
  id: string = ''
  media: PlaybackMedia = new PlaybackMedia()
  stream: PlaybackStream = new PlaybackStream()
  queue: PlaybackQueueItem[] = []
  queueIndex: number = -1
  subtitles: PlaybackSubtitle[] = []
  startPositionMs: number = 0
  durationMs: number = 0
  /** Provider 私有上下文；播放器不解析，也不作为路由参数传递。 */
  contextJson: string = ''
}
