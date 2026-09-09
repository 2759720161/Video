/** 历史页面使用的通用展示模型，不依赖 LocalVideoRecord。 */
export class PlaybackHistoryViewItem {
  key: string = ''
  sourceId: string = ''
  mediaId: string = ''
  title: string = ''
  subtitle: string = ''
  artworkRef: string = ''
  /** 运行时解析出的图片地址；永远不写入历史存储。 */
  artworkUrl: string = ''
  positionMs: number = 0
  durationMs: number = 0
  lastPlayedAt: number = 0
  localRecordId: number = -1
  remoteRecordId: number = -1
  completed: boolean = false
}
