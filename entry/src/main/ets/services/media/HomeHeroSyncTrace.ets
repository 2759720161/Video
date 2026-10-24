import { FrameCallback, UIContext } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

class HeroFrameProbe extends FrameCallback {
  private trace: HomeHeroSyncTrace
  private ticket: number
  private startedAt: number

  constructor(trace: HomeHeroSyncTrace, ticket: number, startedAt: number) {
    super()
    this.trace = trace; this.ticket = ticket; this.startedAt = startedAt
  }

  onFrame(_frameTimeInNano: number): void { this.trace.frame(this.ticket, this.startedAt) }
}

/** One summary per second/end; frame probes measure scheduling, not screen presentation. */
export class HomeHeroSyncTrace {
  private static active: HomeHeroSyncTrace | null = null
  private kind: string = ''
  private ticket: number = 0
  private startedAt: number = 0
  private lastSampleAt: number = 0
  private lastProbeAt: number = 0
  private samples: number = 0
  private known: number = 0
  private content: number = 0
  private home: number = 0
  private callbackMaxMs: number = 0
  private gapMaxMs: number = 0
  private frameWaitMaxMs: number = 0
  private position: number = 0
  private tone: string = ''
  private contentColor: string = ''
  private homeColor: string = ''

  static palette(kind: string, available: boolean, tone: string = ''): void {
    const trace = HomeHeroSyncTrace.active
    if (trace === null || trace.kind !== kind) return
    if (available) trace.known++
    trace.tone = /^#[0-9a-f]{6}$/i.test(tone) ? tone : ''
  }

  static applied(kind: string, layer: string, color: string = ''): void {
    const trace = HomeHeroSyncTrace.active
    if (trace === null || trace.kind !== kind) return
    const validColor = /^#[0-9a-f]{6}$/i.test(color) ? color : ''
    if (layer === 'home') { trace.home++; trace.homeColor = validColor }
    else if (layer === 'content') { trace.content++; trace.contentColor = validColor }
  }

  sample(context: UIContext, kind: string, position: number, apply: () => void): void {
    const now = Date.now()
    this.kind = kind === 'cat' ? 'cat' : 'emby'
    if (this.samples === 0) this.startedAt = now
    if (this.lastSampleAt > 0) this.gapMaxMs = Math.max(this.gapMaxMs, now - this.lastSampleAt)
    this.lastSampleAt = now; this.position = position; this.samples++
    HomeHeroSyncTrace.active = this
    try { apply() } finally {
      HomeHeroSyncTrace.active = null
      this.callbackMaxMs = Math.max(this.callbackMaxMs, Date.now() - now)
    }
    if (now - this.lastProbeAt < 500) return
    this.lastProbeAt = now
    try { context.postFrameCallback(new HeroFrameProbe(this, this.ticket, now)) } catch (_) {}
    if (now - this.startedAt >= 1000) this.flush()
  }

  frame(ticket: number, startedAt: number): void {
    if (ticket === this.ticket) this.frameWaitMaxMs = Math.max(this.frameWaitMaxMs, Date.now() - startedAt)
  }

  flush(): void {
    if (this.samples > 0) {
      hilog.info(0, 'HomeHeroSync',
        '%{public}s samples=%{public}d known=%{public}d content=%{public}d home=%{public}d callbackMaxMs=%{public}d gapMaxMs=%{public}d frameWaitMaxMs=%{public}d position=%{public}s tone=%{public}s contentColor=%{public}s homeColor=%{public}s',
        this.kind, this.samples, this.known, this.content, this.home, this.callbackMaxMs,
        this.gapMaxMs, this.frameWaitMaxMs, this.position.toFixed(3), this.tone, this.contentColor, this.homeColor)
    }
    this.ticket++; this.samples = 0; this.known = 0; this.content = 0; this.home = 0
    this.lastSampleAt = 0; this.lastProbeAt = 0; this.callbackMaxMs = 0; this.gapMaxMs = 0; this.frameWaitMaxMs = 0
    this.tone = ''; this.contentColor = ''; this.homeColor = ''
  }
}
