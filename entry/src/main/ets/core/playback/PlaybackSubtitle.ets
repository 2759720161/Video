/** Provider 提供的外挂字幕资源；播放器只消费通用 URL 与请求头。 */
export class PlaybackSubtitle {
  id: string = ''
  displayName: string = ''
  url: string = ''
  headers: Record<string, string> = {}
}
