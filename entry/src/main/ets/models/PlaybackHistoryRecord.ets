/** 所有媒体来源共享的继续观看记录。来源专属信息仍由各 Provider 保存。 */
export class PlaybackHistoryRecord {
  id: number = -1
  sourceId: string = ''
  mediaId: string = ''
  title: string = ''
  subtitle: string = ''
  artwork: string = ''
  positionMs: number = 0
  durationMs: number = 0
  lastPlayedAt: number = 0
  contextJson: string = ''
  createdAt: number = 0
  updatedAt: number = 0
}
