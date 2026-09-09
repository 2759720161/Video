/** Provider 解析的播放流；过期直链应在播放前由 Provider 重新解析。 */
export class PlaybackStream {
  url: string = ''
  headers: Record<string, string> = {}
  referer: string = ''
  userAgent: string = ''
  proxy: string = ''
  isLocalFile: boolean = false
  localFileSize: number = 0

  /** Unix 毫秒时间戳，0 表示不会过期。 */
  expiresAt: number = 0

  isExpired(now: number = Date.now()): boolean {
    return this.expiresAt > 0 && now >= this.expiresAt
  }

  /** 临时播放地址的提前刷新窗口，默认提前 30 秒判定。 */
  isExpiringSoon(windowMs: number = 30000, now: number = Date.now()): boolean {
    if (this.expiresAt <= 0) return false
    return this.expiresAt - now <= Math.max(0, windowMs)
  }
}
