import type { PlaybackVariant } from './PlaybackVariant'

/** 队列保存稳定媒体身份；切换项目时重新解析 PlaybackStream。 */
export class PlaybackQueueItem {
  sourceId: string = ''
  mediaId: string = ''
  title: string = ''
  subtitle: string = ''
  artwork: string = ''
  artworkRef: string = ''
  positionMs: number = 0
  durationMs: number = 0
  /** 会话内的显式播放意图；避免 positionMs = 0 被远程 Provider 解释为“使用服务端续播点”。 */
  startFromBeginning: boolean = false
  /** 线路、清晰度或媒体版本的可选标识。 */
  variantId: string = ''
  /** Provider 暴露的可选线路/版本，页面只消费通用模型。 */
  variants: PlaybackVariant[] = []

  /** 队列元数据可能来自服务端或历史缓存，统一过滤异常数值。 */
  static normalizePositionMs(value: number): number {
    return Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0
  }

  static normalizeDurationMs(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0
  }
}
