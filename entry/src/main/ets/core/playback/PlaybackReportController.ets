import type { PlaybackReporter } from './PlaybackReporter'

const PLAYBACK_REPORT_INTERVAL_MS: number = 10000

/** 页面与 PiP 共享上报生命周期，并按调用顺序发送。 */
export class PlaybackReportController {
  private started: boolean = false
  private stopping: boolean = false
  private lastProgressMs: number = 0
  private lastPlaying: boolean = false
  private pending: Promise<void> = Promise.resolve()

  private reporter: PlaybackReporter

  constructor(reporter: PlaybackReporter) {
    this.reporter = reporter
  }

  update(positionMs: number, durationMs: number, playing: boolean, speed: number,
    ready: boolean, now: number = Date.now()): void {
    // Queue switches can emit one last engine state while the previous
    // reporter's stopped event is still being delivered. Do not reopen the
    // old reporting cycle from that late callback.
    if (this.stopping) return
    if (!this.started) {
      if (!ready) return
      this.started = true
      const normalizedNow = this.normalizeTimestamp(now)
      const normalizedDurationMs = this.normalizeDuration(durationMs)
      const normalizedPositionMs = this.normalizePosition(positionMs, normalizedDurationMs)
      const normalizedSpeed = this.normalizeSpeed(speed)
      this.lastProgressMs = normalizedNow
      this.lastPlaying = playing
      this.pending = this.pending.then(() => this.reporter.started(
        normalizedPositionMs, normalizedDurationMs, playing, normalizedSpeed))
        .catch(() => {})
      return
    }
    const normalizedNow = this.normalizeTimestamp(now)
    const normalizedDurationMs = this.normalizeDuration(durationMs)
    const normalizedPositionMs = this.normalizePosition(positionMs, normalizedDurationMs)
    const normalizedSpeed = this.normalizeSpeed(speed)
    const changed = playing !== this.lastPlaying
    if (changed || normalizedNow - this.lastProgressMs >= PLAYBACK_REPORT_INTERVAL_MS) {
      this.lastProgressMs = normalizedNow
      this.lastPlaying = playing
      const eventName = changed ? (playing ? 'Unpause' : 'Pause') : 'TimeUpdate'
      this.pending = this.pending.then(() => this.reporter.progress(
        normalizedPositionMs, normalizedDurationMs, playing, normalizedSpeed, eventName))
        .catch(() => {})
    }
  }

  stop(positionMs: number, durationMs: number, speed: number): Promise<void> {
    if (this.started) {
      this.started = false
      this.stopping = true
      const normalizedDurationMs = this.normalizeDuration(durationMs)
      this.pending = this.pending.then(() => this.reporter.stopped(
        this.normalizePosition(positionMs, normalizedDurationMs), normalizedDurationMs, this.normalizeSpeed(speed)))
        .catch(() => {})
        .then(() => { this.stopping = false })
    }
    return this.pending
  }

  private normalizePosition(value: number, durationMs: number = 0): number {
    const positionMs = Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0
    return durationMs > 0 ? Math.min(positionMs, durationMs) : positionMs
  }

  private normalizeDuration(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0
  }

  private normalizeSpeed(value: number): number {
    return Number.isFinite(value) && value > 0 ? value : 1
  }

  private normalizeTimestamp(value: number): number {
    if (!Number.isFinite(value) || value < 0) return Date.now()
    // Date.now() can move backwards after a wall-clock correction. Keep the
    // throttle clock monotonic so a correction cannot create a burst of reports.
    return Math.max(this.lastProgressMs, Math.floor(value))
  }
}
