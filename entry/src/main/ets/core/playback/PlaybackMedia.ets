/** 来源内的稳定媒体身份与展示信息，不包含认证或播放地址。 */
export class PlaybackMedia {
  sourceId: string = ''
  mediaId: string = ''
  title: string = ''
  subtitle: string = ''
  artwork: string = ''
  /** 稳定 ArtworkRef；artwork 只保留运行时展示 URL。 */
  artworkRef: string = ''
  durationMs: number = 0
}
