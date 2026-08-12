import { PlayerState } from '../player/IPlayerEngine'
import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuTimeSync } from './DanmakuTimeSync'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { DanmakuRenderer } from './DanmakuRenderer'
import { DanmakuStyleSettings } from './DanmakuStyleSettings'
import { DanmakuRuntimeStats } from './DanmakuRuntimeStats'
import { PreferencesStore } from '../../store/PreferencesStore'

const DANMAKU_PREFS_KEY_ENABLED: string = 'danmaku_enabled'

export class DanmakuStats {
  count: number = 0
  format: string = ''
  offsetMs: number = 0
  source: string = ''
}

/**
 * Local-file danmaku coordinator. It deliberately has no online matching,
 * account, proxy, or remote-cache dependency.
 */
export class DanmakuManager {
  private trackAllocator: DanmakuTrackAllocator | null = null
  private renderer: DanmakuRenderer | null = null
  private timeSync: DanmakuTimeSync | null = null
  private stats: DanmakuRuntimeStats = new DanmakuRuntimeStats()
  private style: DanmakuStyleSettings = DanmakuStyleSettings.getDefault()
  private items: DanmakuItem[] = []
  private isEnabled: boolean = true
  private currentOffsetMs: number = 0
  private lastState: PlayerState | null = null
  private canvasContext: CanvasRenderingContext2D | null = null
  private canvasWidth: number = 0
  private canvasHeight: number = 0

  async init(): Promise<void> {
    if (this.trackAllocator === null || this.renderer === null || this.timeSync === null) {
      this.trackAllocator = new DanmakuTrackAllocator()
      this.renderer = new DanmakuRenderer(this.trackAllocator, this.stats)
      this.timeSync = new DanmakuTimeSync(this.trackAllocator, this.renderer, this.stats)
    }
    this.style = await DanmakuStyleSettings.load()
    this.renderer.setStyle(this.style)
    this.timeSync.setSettings(this.style)
    this.isEnabled = await PreferencesStore.getInstance().getBoolean(DANMAKU_PREFS_KEY_ENABLED, true)
    this.bindCanvasIfReady()
    this.applyItems()
  }

  onPlayerStateUpdate(state: PlayerState): void {
    this.lastState = state
    if (this.timeSync === null) return
    if (this.isEnabled) this.timeSync.onPlayerStateUpdate(state)
    else this.timeSync.syncPlayerSnapshot(state)
  }

  loadLocalDanmaku(items: DanmakuItem[]): void {
    this.currentOffsetMs = 0
    this.items = this.cloneAndSort(items)
    this.applyItems()
  }

  appendLocalDanmaku(items: DanmakuItem[]): void {
    const keys: Set<string> = new Set()
    for (let i = 0; i < this.items.length; i++) keys.add(this.itemKey(this.items[i]))
    for (let i = 0; i < items.length; i++) {
      if (!keys.has(this.itemKey(items[i]))) {
        this.items.push(items[i])
        keys.add(this.itemKey(items[i]))
      }
    }
    this.items = this.cloneAndSort(this.items)
    this.applyItems()
  }

  clearLocalDanmaku(): void {
    this.items = []
    this.currentOffsetMs = 0
    this.applyItems()
  }

  applyDanmakuOffset(deltaMs: number): void {
    if (deltaMs === 0 || this.items.length === 0) return
    for (let i = 0; i < this.items.length; i++) this.items[i].timeMs = Math.max(0, this.items[i].timeMs + deltaMs)
    this.currentOffsetMs += deltaMs
    this.items = this.cloneAndSort(this.items)
    this.applyItems()
  }

  resetDanmakuOffset(): void {
    if (this.currentOffsetMs === 0) return
    this.applyDanmakuOffset(-this.currentOffsetMs)
  }

  getCurrentOffsetMs(): number { return this.currentOffsetMs }
  getIsDanmakuEnabled(): boolean { return this.isEnabled }
  hasDanmakuData(): boolean { return this.items.length > 0 }
  getRenderer(): DanmakuRenderer | null { return this.renderer }

  getLocalDanmakuStats(): DanmakuStats {
    const value = new DanmakuStats()
    value.count = this.items.length
    value.format = this.items.length > 0 ? 'local-file' : ''
    value.offsetMs = this.currentOffsetMs
    value.source = this.items.length > 0 ? 'local-file' : 'none'
    return value
  }

  toggleDanmaku(): boolean {
    this.isEnabled = !this.isEnabled
    PreferencesStore.getInstance().setBoolean(DANMAKU_PREFS_KEY_ENABLED, this.isEnabled)
    if (!this.isEnabled) {
      this.renderer?.clearAll()
      this.timeSync?.suspendDisplay()
    } else {
      this.applyItems()
      if (this.lastState !== null) this.timeSync?.onPlayerStateUpdate(this.lastState)
    }
    return this.isEnabled
  }

  async reloadSettings(): Promise<void> {
    this.style = await DanmakuStyleSettings.load()
    this.renderer?.setStyle(this.style)
    this.timeSync?.setSettings(this.style)
    this.applyItems()
  }

  onCanvasReady(context: CanvasRenderingContext2D, width: number, height: number): void {
    this.canvasContext = context
    this.canvasWidth = width
    this.canvasHeight = height
    this.bindCanvasIfReady()
  }

  onCanvasSizeChanged(width: number, height: number): void {
    this.canvasWidth = width
    this.canvasHeight = height
    this.trackAllocator?.updateCanvasSize(width, height)
    this.renderer?.updateCanvasSize(width, height)
    this.timeSync?.resyncAfterResize()
  }

  release(): void {
    this.timeSync?.reset()
    this.renderer?.release()
    this.trackAllocator?.reset()
    this.trackAllocator = null
    this.renderer = null
    this.timeSync = null
    this.items = []
    this.lastState = null
  }

  private applyItems(): void {
    if (this.timeSync === null || !this.isEnabled) return
    this.timeSync.setDanmakuData(this.items)
    if (this.lastState !== null) this.timeSync.syncPlayerSnapshot(this.lastState)
  }

  private bindCanvasIfReady(): void {
    if (this.canvasContext === null || this.trackAllocator === null || this.renderer === null) return
    this.trackAllocator.updateCanvasSize(this.canvasWidth, this.canvasHeight)
    this.renderer.setCanvasContext(this.canvasContext, this.canvasWidth, this.canvasHeight)
    this.timeSync?.recoverAfterCanvasReady()
  }

  private cloneAndSort(items: DanmakuItem[]): DanmakuItem[] {
    const copy: DanmakuItem[] = []
    for (let i = 0; i < items.length; i++) copy.push(items[i])
    copy.sort((first: DanmakuItem, second: DanmakuItem) => first.timeMs - second.timeMs)
    return copy
  }

  private itemKey(item: DanmakuItem): string {
    return `${item.timeMs}|${item.type}|${item.content}`
  }
}
