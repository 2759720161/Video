/** 实现应固定绑定来源实例，并在内部处理上报失败。 */
export interface PlaybackReporter {
  started(positionMs: number, durationMs: number,
    playing: boolean, speed: number): Promise<void>

  progress(positionMs: number, durationMs: number,
    playing: boolean, speed: number, eventName?: string): Promise<void>

  stopped(positionMs: number, durationMs: number, speed: number): Promise<void>
}
