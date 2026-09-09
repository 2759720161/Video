/** 来源内的稳定媒体身份与展示信息，不包含认证或播放地址。 */
export class PlaybackMedia {
  sourceId: string = ''
  mediaId: string = ''
  title: string = ''
  subtitle: string = ''
  artwork: string = ''
  durationMs: number = 0
}
