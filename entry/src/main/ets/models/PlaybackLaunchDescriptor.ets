/** 可在进程重建后重新解析播放会话的稳定启动描述。 */
export class PlaybackLaunchDescriptor {
  sourceId: string = ''
  mediaId: string = ''
  variantId: string = ''
  positionMs: number = 0
}
