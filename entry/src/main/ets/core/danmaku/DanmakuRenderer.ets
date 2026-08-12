import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { DanmakuStyleSettings } from './DanmakuStyleSettings'
import { DanmakuRuntimeStats } from './DanmakuRuntimeStats'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuRenderer')

const DEFAULT_TARGET_FPS = 60
const MAX_FRAME_DELTA_MS = 80
const DEFAULT_TEXT_WIDTH = 200
const MAX_ACTIVE_PER_TRACK = 5
const MAX_ACTIVE_PER_TRACK_MASSIVE = 8
const MIN_ACTIVE_CAPACITY = 32
const MAX_ACTIVE_CAPACITY = 180
const MAX_ACTIVE_CAPACITY_MASSIVE = 300
const MIN_STROKE_WIDTH = 0.1
const MAX_STROKE_WIDTH = 3.0
const EDGE_CLEAR_PADDING = 16
const SPAWN_X_PADDING = 12
const FIXED_DANMAKU_DURATION_MS = 4000
const FPS_LOW_THRESHOLD = 20
const FPS_CRITICAL_THRESHOLD = 15
const FPS_LOW_DURATION_MS = 3000
const FPS_CRITICAL_DURATION_MS = 5000
const DENSITY_REDUCTION_RATIO = 0.7
const TEXT_WIDTH_CACHE_LIMIT = 2048

export class DanmakuRenderer {
  private trackAllocator: DanmakuTrackAllocator
  private canvasContext: CanvasRenderingContext2D | null = null
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private activeDanmaku: DanmakuItem[] = []
  private scrollSpeed: number = 0
  private maxVisibleCount: number = 0
  private isRendering: boolean = false
  private isPaused: boolean = false
  private renderTimerId: number = -1
  private targetFrameRate: number = DEFAULT_TARGET_FPS
  private renderFrameIntervalMs: number = 1000 / DEFAULT_TARGET_FPS
  private lastFrameTimeMs: number = 0
  private playbackSpeed: number = 1.0
  private frameTimestamps: number[] = []
  private frameTimestampStartIndex: number = 0
  private currentFps: number = 0
  private lowFpsStartMs: number = 0
  private criticalFpsStartMs: number = 0
  private densityReduced: boolean = false
  private criticalStopped: boolean = false
  private style: DanmakuStyleSettings = DanmakuStyleSettings.getDefault()
  private missingCanvasWarned: boolean = false
  private topTrackEndTimes: number[] = []
  private bottomTrackEndTimes: number[] = []
  private stats: DanmakuRuntimeStats
  private cachedFont: string = ''
  private cachedBorderWidth: number = 0
  private cachedStyleStateKey: string = ''
  private textWidthCache: Map<string, number> = new Map()
  private textWidthCacheFont: string = ''

  constructor(trackAllocator: DanmakuTrackAllocator, stats: DanmakuRuntimeStats) {
    this.trackAllocator = trackAllocator
    this.stats = stats
  }

  setCanvasContext(context: CanvasRenderingContext2D, width: number, height: number): void {
    this.canvasContext = context
    this.canvasWidth = width
    this.canvasHeight = height
    this.missingCanvasWarned = false
    this.recalculateParams()
    this.updateStats()
    logger.info('渲染Canvas绑定: width=%{public}d, height=%{public}d, maxVisible=%{public}d',
      width, height, this.maxVisibleCount)
  }

  updateCanvasSize(width: number, height: number): void {
    this.canvasWidth = width
    this.canvasHeight = height
    this.recalculateParams()
    this.updateStats()
    logger.info('渲染Canvas尺寸更新: width=%{public}d, height=%{public}d, maxVisible=%{public}d',
      width, height, this.maxVisibleCount)
  }

  setStyle(style: DanmakuStyleSettings): void {
    this.style = style
    this.trackAllocator.updateStyle(style.fontSize, style.displayArea, style.lineHeight)
    this.cachedFont = this.buildFont()
    this.cachedBorderWidth = Math.max(MIN_STROKE_WIDTH, Math.min(MAX_STROKE_WIDTH, style.borderSize))
    this.cachedStyleStateKey = ''
    this.clearTextWidthCache()
    this.activeDanmaku.forEach((item: DanmakuItem) => {
      item.textWidth = 0
    })
    this.rebuildActiveTrackBounds()
    this.recalculateParams()
    this.updateStats()
    logger.info('弹幕样式应用: border=%{public}s, borderSize=%{public}s, color=%{public}s, fontSize=%{public}s, fontWeight=%{public}d, opacity=%{public}s, duration=%{public}s, area=%{public}s, lineHeight=%{public}s, followSpeed=%{public}s, fps=%{public}d',
      String(style.border), style.borderSize.toFixed(1), String(style.useSourceColor), style.fontSize.toFixed(0),
      style.fontWeight, style.opacity.toFixed(2), style.scrollDurationSec.toFixed(1), style.displayArea.toFixed(2),
      style.lineHeight.toFixed(1), String(style.followSpeed), this.targetFrameRate)
  }

  getCanvasWidth(): number {
    return this.canvasWidth
  }

  getSpawnX(): number {
    return this.canvasWidth + SPAWN_X_PADDING
  }

  canAcceptDanmaku(): boolean {
    return this.activeDanmaku.length < this.maxVisibleCount
  }

  isReady(): boolean {
    return this.canvasContext !== null && this.canvasWidth > 0 && this.canvasHeight > 0 && this.maxVisibleCount > 0
  }

  addActiveDanmaku(item: DanmakuItem): boolean {
    if (this.activeDanmaku.length >= this.maxVisibleCount) {
      logger.warn('活跃弹幕达到上限: active=%{public}d, max=%{public}d',
        this.activeDanmaku.length, this.maxVisibleCount)
      this.stats.droppedCount++
      this.stats.lastDropReason = 'active_limit'
      return false
    }
    if (this.isFixedDanmaku(item)) {
      if (!this.prepareFixedDanmaku(item)) {
        this.stats.droppedCount++
        this.stats.lastDropReason = 'fixed_track_full'
        return false
      }
    }
    this.activeDanmaku.push(item)
    this.stats.shownCount++
    this.stats.activeCount = this.activeDanmaku.length
    if (this.activeDanmaku.length === 1 || this.activeDanmaku.length % 50 === 0) {
      logger.info('活跃弹幕增加: active=%{public}d, max=%{public}d',
        this.activeDanmaku.length, this.maxVisibleCount)
    }
    return true
  }

  prepareDanmakuItem(item: DanmakuItem): void {
    if (item.textWidth > 0 || this.canvasContext === null) {
      return
    }
    item.textWidth = this.measureTextWidth(item.content)
  }

  startRendering(): void {
    if (this.isRendering || !this.isReady()) {
      if (!this.isReady() && !this.missingCanvasWarned) {
        logger.warn('弹幕渲染未启动: canvasContext为空')
        this.missingCanvasWarned = true
      }
      return
    }
    this.isRendering = true
    this.isPaused = false
    this.lastFrameTimeMs = Date.now()
    logger.info('弹幕渲染启动: width=%{public}d, height=%{public}d',
      this.canvasWidth, this.canvasHeight)
    this.restartRenderTimer()
  }

  private restartRenderTimer(): void {
    if (this.renderTimerId >= 0) {
      clearInterval(this.renderTimerId)
      this.renderTimerId = -1
    }
    this.lastFrameTimeMs = Date.now()
    this.renderTimerId = setInterval(() => {
      this.renderFrame()
    }, this.renderFrameIntervalMs)
  }

  pauseRendering(): void {
    this.isPaused = true
  }

  resumeRendering(): void {
    if (!this.isRendering) {
      this.criticalStopped = false
      this.startRendering()
      return
    }
    this.isPaused = false
    this.lastFrameTimeMs = Date.now()
    if (this.criticalStopped) {
      this.criticalStopped = false
      this.densityReduced = false
      this.recalculateParams()
      logger.info('弹幕渲染从critical状态恢复')
    }
  }

  stopRendering(): void {
    this.isRendering = false
    this.isPaused = false
    if (this.renderTimerId >= 0) {
      clearInterval(this.renderTimerId)
      this.renderTimerId = -1
    }
    this.resetFpsWindow()
    logger.info('弹幕渲染停止')
  }

  setPlaybackSpeed(speed: number): void {
    this.playbackSpeed = speed
  }

  clearAll(): void {
    this.activeDanmaku = []
    this.trackAllocator.reset()
    this.topTrackEndTimes = []
    this.bottomTrackEndTimes = []
    this.stats.activeCount = 0
    this.densityReduced = false
    this.criticalStopped = false
    this.clearCanvas()
  }

  removeActiveDanmaku(predicate: (item: DanmakuItem) => boolean): number {
    let writeIndex = 0
    let removed = 0
    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      if (predicate(item)) {
        item.isAlive = false
        removed++
      } else {
        if (writeIndex !== i) {
          this.activeDanmaku[writeIndex] = item
        }
        writeIndex++
      }
    }
    if (writeIndex < this.activeDanmaku.length) {
      this.activeDanmaku.length = writeIndex
    }
    if (removed > 0) {
      this.rebuildActiveTrackBounds()
      this.drawFrame()
    }
    this.stats.activeCount = this.activeDanmaku.length
    return removed
  }

  release(): void {
    this.stopRendering()
    this.clearCanvas()
    this.canvasContext = null
    this.activeDanmaku = []
    this.stats.activeCount = 0
    this.resetFpsWindow()
    this.clearTextWidthCache()
    this.densityReduced = false
    this.criticalStopped = false
  }

  private recalculateParams(): void {
    if (this.canvasWidth <= 0) {
      return
    }
    this.scrollSpeed = this.canvasWidth / (this.style.scrollDurationSec * 1000)
    const trackCount = this.trackAllocator.getTrackCount()
    const perTrack = this.style.massiveMode ? MAX_ACTIVE_PER_TRACK_MASSIVE : MAX_ACTIVE_PER_TRACK
    const maxCap = this.style.massiveMode ? MAX_ACTIVE_CAPACITY_MASSIVE : MAX_ACTIVE_CAPACITY
    this.maxVisibleCount = Math.max(MIN_ACTIVE_CAPACITY,
      Math.min(maxCap, trackCount * perTrack))
    if (this.densityReduced) {
      this.maxVisibleCount = Math.floor(this.maxVisibleCount * DENSITY_REDUCTION_RATIO)
    }
  }

  private renderFrame(): void {
    if (!this.isRendering) {
      return
    }

    const now = Date.now()
    let elapsedMs = now - this.lastFrameTimeMs
    if (elapsedMs <= 0 || elapsedMs > MAX_FRAME_DELTA_MS) {
      elapsedMs = this.renderFrameIntervalMs
    }
    this.lastFrameTimeMs = now

    if (!this.isPaused && this.canvasContext !== null) {
      this.updatePositions(elapsedMs)
      this.drawFrame()
      this.cleanupExpiredDanmaku(now)
      this.monitorFps(now)
    }
  }

  private updatePositions(elapsedMs: number): void {
    const speed = this.scrollSpeed * (this.style.followSpeed ? this.playbackSpeed : 1.0)
    const distance = speed * elapsedMs
    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      if (this.isFixedDanmaku(item)) {
        continue
      }
      item.x -= distance

      const textWidth = item.textWidth > 0 ? item.textWidth : DEFAULT_TEXT_WIDTH
      const rightBound = item.x + textWidth
      this.trackAllocator.updateTrackBound(item.trackIndex, rightBound)
    }
  }

  private drawFrame(): void {
    if (this.canvasContext === null) {
      return
    }

    const ctx = this.canvasContext
    ctx.clearRect(0, 0, this.canvasWidth + EDGE_CLEAR_PADDING, this.canvasHeight + EDGE_CLEAR_PADDING)
    this.applySharedCanvasState(ctx)

    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      try {
        this.drawDanmakuItem(ctx, item)
      } catch (_drawErr) {
        logger.warn('弹幕绘制异常：跳过')
      }
    }
  }

  private clearCanvas(): void {
    if (this.canvasContext !== null && this.canvasWidth > 0 && this.canvasHeight > 0) {
      this.canvasContext.clearRect(0, 0, this.canvasWidth + EDGE_CLEAR_PADDING, this.canvasHeight + EDGE_CLEAR_PADDING)
    }
  }

  private rebuildActiveTrackBounds(): void {
    this.trackAllocator.reset()
    const trackCount = this.trackAllocator.getTrackCount()
    let writeIndex = 0
    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      if (item.trackIndex < 0 || item.trackIndex >= trackCount) {
        item.isAlive = false
        continue
      }
      if (writeIndex !== i) {
        this.activeDanmaku[writeIndex] = item
      }
      writeIndex++
      if (!this.isFixedDanmaku(item)) {
        const textWidth = item.textWidth > 0 ? item.textWidth : DEFAULT_TEXT_WIDTH
        this.trackAllocator.updateTrackBound(item.trackIndex, item.x + textWidth)
      }
    }
    if (writeIndex < this.activeDanmaku.length) {
      this.activeDanmaku.length = writeIndex
    }
  }

  private drawDanmakuItem(ctx: CanvasRenderingContext2D, item: DanmakuItem): void {
    if (!this.isFixedDanmaku(item) && item.x + (item.textWidth > 0 ? item.textWidth : DEFAULT_TEXT_WIDTH) < 0) {
      return
    }

    const color = this.style.useSourceColor ? item.color : '#FFFFFF'
    const y = this.getDanmakuY(item)
    const drawX = Math.round(this.isFixedDanmaku(item) ? this.getFixedDanmakuX(item) : item.x)
    const drawY = Math.round(y)

    if (this.style.border && this.style.borderSize > 0) {
      ctx.strokeText(item.content, drawX, drawY)
    }
    if (ctx.fillStyle !== color) {
      ctx.fillStyle = color
    }
    ctx.fillText(item.content, drawX, drawY)

    if (item.textWidth === 0) {
      item.textWidth = this.measureTextWidth(item.content)
    }
  }

  private cleanupExpiredDanmaku(now: number): void {
    let writeIdx = 0
    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      const textWidth = item.textWidth > 0 ? item.textWidth : DEFAULT_TEXT_WIDTH
      const expired = this.isFixedDanmaku(item)
        ? item.endRenderMs > 0 && now >= item.endRenderMs
        : item.x + textWidth < 0
      if (expired) {
        item.isAlive = false
      } else {
        if (writeIdx !== i) {
          this.activeDanmaku[writeIdx] = item
        }
        writeIdx++
      }
    }
    if (writeIdx < this.activeDanmaku.length) {
      this.activeDanmaku.length = writeIdx
    }
    this.stats.activeCount = this.activeDanmaku.length
  }

  private applySharedCanvasState(ctx: CanvasRenderingContext2D): void {
    const font = this.cachedFont.length > 0 ? this.cachedFont : this.buildFont()
    const stateKey = `${font}|${this.style.opacity.toFixed(2)}|${String(this.style.border)}|${this.cachedBorderWidth.toFixed(1)}`
    if (stateKey === this.cachedStyleStateKey) {
      return
    }
    ctx.font = font
    ctx.globalAlpha = this.style.opacity
    ctx.textBaseline = 'middle'
    if (this.style.border && this.style.borderSize > 0) {
      ctx.lineWidth = this.cachedBorderWidth
      ctx.lineJoin = 'round'
      ctx.lineCap = 'round'
      ctx.miterLimit = 2
      ctx.strokeStyle = '#000000'
    }
    this.cachedStyleStateKey = stateKey
  }

  private buildFont(): string {
    const fontSize = this.style.fontSize
    const fontWeight = Math.max(1, Math.min(9, this.style.fontWeight)) * 100
    return `${fontWeight} ${fontSize}vp sans-serif`
  }

  private measureTextWidth(content: string): number {
    if (this.canvasContext === null || content.length === 0) {
      return DEFAULT_TEXT_WIDTH
    }

    const font = this.cachedFont.length > 0 ? this.cachedFont : this.buildFont()
    if (this.textWidthCacheFont !== font) {
      this.clearTextWidthCache()
      this.textWidthCacheFont = font
    }

    const cachedWidth = this.textWidthCache.get(content)
    if (cachedWidth !== undefined) {
      return cachedWidth
    }

    const ctx = this.canvasContext
    ctx.font = font
    const measured = ctx.measureText(content)
    const width = measured.width > 0 ? measured.width : DEFAULT_TEXT_WIDTH
    this.textWidthCache.set(content, width)
    if (this.textWidthCache.size > TEXT_WIDTH_CACHE_LIMIT) {
      const firstKey = this.textWidthCache.keys().next().value as string
      if (firstKey !== undefined) {
        this.textWidthCache.delete(firstKey)
      }
    }
    return width
  }

  private clearTextWidthCache(): void {
    this.textWidthCache.clear()
    this.textWidthCacheFont = this.cachedFont.length > 0 ? this.cachedFont : this.buildFont()
  }

  private isFixedDanmaku(item: DanmakuItem): boolean {
    return item.type === 4 || item.type === 5
  }

  private prepareFixedDanmaku(item: DanmakuItem): boolean {
    const now = Date.now()
    const trackCount = Math.max(1, this.trackAllocator.getTrackCount())
    const tracks = item.type === 5 ? this.topTrackEndTimes : this.bottomTrackEndTimes
    for (let i = 0; i < trackCount; i++) {
      const endTime = i < tracks.length ? tracks[i] : 0
      if (endTime <= now) {
        item.trackIndex = i
        item.startRenderMs = now
        item.endRenderMs = now + FIXED_DANMAKU_DURATION_MS
        tracks[i] = item.endRenderMs
        return true
      }
    }
    return false
  }

  private getFixedDanmakuX(item: DanmakuItem): number {
    const textWidth = item.textWidth > 0 ? item.textWidth : DEFAULT_TEXT_WIDTH
    return Math.max(0, (this.canvasWidth - textWidth) / 2)
  }

  private getDanmakuY(item: DanmakuItem): number {
    if (item.type === 5) {
      return this.trackAllocator.getTrackY(item.trackIndex)
    }
    if (item.type === 4) {
      const lineHeight = this.trackAllocator.getLineHeight()
      const displayHeight = this.trackAllocator.getDisplayHeight()
      return displayHeight - Math.round(lineHeight / 2) - item.trackIndex * lineHeight
    }
    return this.trackAllocator.getTrackY(item.trackIndex)
  }

  private monitorFps(now: number): void {
    this.frameTimestamps.push(now)
    const oneSecAgo = now - 1000
    while (this.frameTimestampStartIndex < this.frameTimestamps.length &&
           this.frameTimestamps[this.frameTimestampStartIndex] < oneSecAgo) {
      this.frameTimestampStartIndex++
    }
    if (this.frameTimestampStartIndex > 60) {
      this.frameTimestamps = this.frameTimestamps.slice(this.frameTimestampStartIndex)
      this.frameTimestampStartIndex = 0
    }
    this.currentFps = this.frameTimestamps.length - this.frameTimestampStartIndex
    this.stats.currentFps = this.currentFps

    if (this.currentFps < FPS_LOW_THRESHOLD) {
      if (this.lowFpsStartMs === 0) {
        this.lowFpsStartMs = now
      }
      if (now - this.lowFpsStartMs >= FPS_LOW_DURATION_MS && !this.densityReduced) {
        this.densityReduced = true
        this.recalculateParams()
        logger.warn('帧率过低(%{public}dfps)，降低弹幕密度30%%', this.currentFps)
      }

      if (this.currentFps < FPS_CRITICAL_THRESHOLD) {
        if (this.criticalFpsStartMs === 0) {
          this.criticalFpsStartMs = now
        }
        if (now - this.criticalFpsStartMs >= FPS_CRITICAL_DURATION_MS) {
          this.criticalStopped = true
          this.stopRendering()
          logger.error('帧率持续过低(%{public}dfps)，暂停弹幕渲染，将在下次resume时恢复', this.currentFps)
        }
      }
    } else {
      this.lowFpsStartMs = 0
      this.criticalFpsStartMs = 0
      if (this.densityReduced && this.currentFps > 24) {
        this.densityReduced = false
        this.recalculateParams()
        logger.info('帧率恢复(%{public}dfps)，恢复弹幕密度', this.currentFps)
      }
    }
  }

  private updateStats(): void {
    this.stats.canvasWidth = this.canvasWidth
    this.stats.canvasHeight = this.canvasHeight
    this.stats.trackCount = this.trackAllocator.getTrackCount()
    this.stats.activeCount = this.activeDanmaku.length
  }

  private resetFpsWindow(): void {
    this.frameTimestamps = []
    this.frameTimestampStartIndex = 0
    this.currentFps = 0
    this.stats.currentFps = 0
  }
}
