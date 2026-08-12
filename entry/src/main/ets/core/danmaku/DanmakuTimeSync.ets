import { PlayerState } from '../player/IPlayerEngine'
import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { DanmakuRenderer } from './DanmakuRenderer'
import { DanmakuStyleSettings } from './DanmakuStyleSettings'
import { DanmakuRuntimeStats } from './DanmakuRuntimeStats'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuTimeSync')

const SEEK_THRESHOLD_MS = 5000
const DISPATCH_POLL_INTERVAL_MS = 100
const DISPATCH_LOG_INTERVAL = 100
const BASE_MAX_LATE_DISPATCH_MS = 4500
const MAX_PENDING_DISPATCHES = 500

class PendingDanmakuDispatch {
  item: DanmakuItem
  emitAtMs: number
  generation: number

  constructor(item: DanmakuItem, emitAtMs: number, generation: number) {
    this.item = item
    this.emitAtMs = emitAtMs
    this.generation = generation
  }
}

export class DanmakuTimeSync {
  private trackAllocator: DanmakuTrackAllocator
  private renderer: DanmakuRenderer
  private allDanmaku: DanmakuItem[] = []
  private lastPositionMs: number = 0
  private lastPlaying: boolean = false
  private lastSpeed: number = 1.0
  private durationMs: number = 0
  private dispatchIndex: number = 0
  private isSeeking: boolean = false
  private currentPositionMs: number = 0
  private currentPlaying: boolean = false
  private currentSpeed: number = 1.0
  private pollTimerId: number = -1
  private settings: DanmakuStyleSettings = DanmakuStyleSettings.getDefault()
  private blockedKeywords: string[] = []
  private blockedRegex: RegExp | null = null
  private stats: DanmakuRuntimeStats
  private timelineOffsetMs: number = 0
  private dispatchGeneration: number = 0
  private pendingDispatches: PendingDanmakuDispatch[] = []
  private dispatchBatch: DanmakuItem[] = []

  constructor(trackAllocator: DanmakuTrackAllocator, renderer: DanmakuRenderer, stats: DanmakuRuntimeStats) {
    this.trackAllocator = trackAllocator
    this.renderer = renderer
    this.stats = stats
  }

  setSettings(settings: DanmakuStyleSettings): void {
    const previousOffsetMs = this.timelineOffsetMs
    this.settings = settings
    this.blockedKeywords = this.parseBlockedKeywords(settings.blockKeywordsText)
    this.blockedRegex = this.compileBlockedRegex(settings.blockRegexText)
    const newOffsetMs = Math.round(settings.danmakuTimeOffset * 1000)
    if (newOffsetMs !== previousOffsetMs) {
      this.setTimelineOffset(settings.danmakuTimeOffset)
    }
  }

  setDanmakuData(items: DanmakuItem[]): void {
    this.allDanmaku = items
    this.stats.resetForEpisode(items.length)
    this.dispatchIndex = this.findDispatchIndex(this.resolveSourcePosition(this.currentPositionMs))
    if (items.length > 0) {
      const first = items[0]
      const last = items[items.length - 1]
      logger.info('弹幕数据注入: count=%{public}d, first=%{public}dms, last=%{public}dms, startIndex=%{public}d',
        items.length, first.timeMs, last.timeMs, this.dispatchIndex)
    } else {
      logger.warn('弹幕数据注入为空')
    }
  }

  onPlayerStateUpdate(state: PlayerState): void {
    const positionMs = this.clampPosition(state.positionMs, state.durationMs)
    this.durationMs = state.durationMs
    this.currentPositionMs = positionMs
    this.currentSpeed = state.speed > 0 ? state.speed : 1.0

    if (this.lastPlaying && Math.abs(positionMs - this.lastPositionMs) > SEEK_THRESHOLD_MS) {
      this.handleSeek(positionMs)
    }

    if (state.playing !== this.lastPlaying) {
      this.currentPlaying = state.playing
      if (state.playing) {
        this.renderer.resumeRendering()
        this.startDispatchPoll()
      } else {
        this.renderer.pauseRendering()
        this.stopDispatchPoll()
        this.clearPendingDispatches()
      }
    }

    if (state.speed !== this.lastSpeed && state.speed > 0) {
      this.renderer.setPlaybackSpeed(state.speed)
    }

    if (state.stateName === 'completed' || state.stateName === 'error' || state.stateName === 'stopped') {
      this.currentPlaying = false
      this.stopDispatchPoll()
      this.invalidatePendingTimers()
      this.renderer.stopRendering()
      this.renderer.clearAll()
    }

    if (state.playing) {
      this.renderer.resumeRendering()
      this.dispatchDanmaku(positionMs)
    }

    this.lastPositionMs = positionMs
    this.lastPlaying = state.playing
    this.lastSpeed = state.speed
  }

  syncPlayerSnapshot(state: PlayerState): void {
    const positionMs = this.clampPosition(state.positionMs, state.durationMs)
    this.durationMs = state.durationMs
    this.currentPositionMs = positionMs
    this.currentSpeed = state.speed > 0 ? state.speed : 1.0
    this.lastPositionMs = positionMs
    this.lastSpeed = state.speed
    this.lastPlaying = false
    this.currentPlaying = false
    this.dispatchIndex = this.findDispatchIndex(this.resolveSourcePosition(positionMs))
  }

  suspendDisplay(): void {
    this.stopDispatchPoll()
    this.invalidatePendingTimers()
    this.lastPlaying = false
    this.currentPlaying = false
    this.renderer.stopRendering()
    this.renderer.clearAll()
    this.trackAllocator.reset()
  }

  reset(): void {
    this.stopDispatchPoll()
    this.invalidatePendingTimers()
    this.allDanmaku = []
    this.dispatchIndex = 0
    this.lastPositionMs = 0
    this.lastPlaying = false
    this.lastSpeed = 1.0
    this.isSeeking = false
    this.currentPositionMs = 0
    this.currentPlaying = false
    this.currentSpeed = 1.0
    this.timelineOffsetMs = 0
    this.dispatchGeneration = 0
    this.pendingDispatches = []
    this.dispatchBatch = []
  }

  resyncAfterResize(): void {
    this.refreshDispatchState()
  }

  refreshAfterSettingsChanged(): void {
    this.refreshDispatchState()
  }

  applySettingsToActiveDanmaku(): void {
    const removed = this.renderer.removeActiveDanmaku((item: DanmakuItem): boolean => {
      return this.getFilterReason(item).length > 0
    })
    if (removed > 0) {
      logger.info('弹幕设置热更新移除活跃弹幕: count=%{public}d', removed)
    }
  }

  addLocalDanmaku(item: DanmakuItem): boolean {
    const insertIndex = this.findInsertIndex(item.timeMs)
    this.allDanmaku.splice(insertIndex, 0, item)
    if (insertIndex <= this.dispatchIndex) {
      this.dispatchIndex++
    }
    if (!this.currentPlaying) {
      return false
    }
    return this.dispatchImmediateDanmaku(item)
  }

  private resolveSourcePosition(positionMs: number): number {
    return positionMs - this.timelineOffsetMs
  }

  private setTimelineOffset(offsetSec: number): void {
    this.timelineOffsetMs = Math.round(offsetSec * 1000)
    this.invalidatePendingTimers()
    logger.info('时间轴偏移已更新: offsetSec=%{public}s, offsetMs=%{public}d',
      offsetSec.toFixed(2), this.timelineOffsetMs)
  }

  private invalidatePendingTimers(): void {
    this.dispatchGeneration++
    this.clearPendingDispatches()
    if (this.renderer !== null) {
      this.renderer.clearAll()
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.reset()
    }
    this.dispatchIndex = this.findDispatchIndex(this.resolveSourcePosition(this.currentPositionMs))
  }

  private clearPendingDispatches(): void {
    this.pendingDispatches = []
  }

  private refreshDispatchState(): void {
    this.invalidatePendingTimers()
    if (this.currentPlaying) {
      this.renderer.resumeRendering()
      this.startDispatchPoll()
    }
  }

  recoverAfterCanvasReady(): void {
    if (!this.renderer.isReady()) {
      return
    }
    if (this.currentPlaying) {
      this.renderer.resumeRendering()
      this.startDispatchPoll()
      this.dispatchDanmaku(this.currentPositionMs)
    }
  }

  private startDispatchPoll(): void {
    if (this.pollTimerId >= 0) {
      return
    }
    this.pollTimerId = setInterval(() => {
      this.onDispatchPollTick()
    }, DISPATCH_POLL_INTERVAL_MS)
  }

  private stopDispatchPoll(): void {
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId)
      this.pollTimerId = -1
    }
  }

  private onDispatchPollTick(): void {
    if (!this.currentPlaying) {
      return
    }
    const elapsed = DISPATCH_POLL_INTERVAL_MS * this.currentSpeed
    this.currentPositionMs += elapsed
    if (this.durationMs > 0 && this.currentPositionMs > this.durationMs) {
      this.currentPositionMs = this.durationMs
    }
    this.flushPendingDispatches(Date.now())
    this.dispatchDanmaku(this.currentPositionMs)
  }

  private handleSeek(newPositionMs: number): void {
    logger.info('检测到seek, newPositionMs=%{public}d', newPositionMs)
    this.invalidatePendingTimers()
    this.isSeeking = true
  }

  private dispatchDanmaku(positionMs: number): void {
    if (this.allDanmaku.length === 0) {
      return
    }
    if (!this.renderer.isReady()) {
      return
    }

    const sourcePositionMs = this.resolveSourcePosition(positionMs)

    const batch = this.dispatchBatch
    batch.length = 0
    while (this.dispatchIndex < this.allDanmaku.length) {
      const item = this.allDanmaku[this.dispatchIndex]
      if (item.timeMs > sourcePositionMs) {
        break
      }

      const filterReason = this.getFilterReason(item)
      if (filterReason.length > 0) {
        this.stats.filteredCount++
        this.stats.lastFilterReason = filterReason
        this.dispatchIndex++
        continue
      }

      batch.push(item)
      this.dispatchIndex++
    }

    if (batch.length === 0) {
      return
    }

    let currentSecond = -1
    let groupStart = 0
    for (let i = 0; i <= batch.length; i++) {
      let itemSecond = -1
      if (i < batch.length) {
        itemSecond = Math.floor(batch[i].timeMs / 1000)
      }
      if (itemSecond !== currentSecond || i === batch.length) {
        if (i > groupStart) {
          this.dispatchGroupWithStagger(batch, groupStart, i, positionMs)
        }
        groupStart = i
        currentSecond = itemSecond
      }
    }
    batch.length = 0
  }

  private dispatchGroupWithStagger(group: DanmakuItem[], startIndex: number, endIndex: number, positionMs: number): void {
    const total = endIndex - startIndex
    const now = Date.now()
    for (let i = 0; i < total; i++) {
      const item = group[startIndex + i]
      const staggerDelay = Math.floor(i * 1000 / total)
      if (staggerDelay === 0) {
        this.emitDanmaku(item, positionMs)
      } else {
        if (this.pendingDispatches.length >= MAX_PENDING_DISPATCHES) {
          this.emitDanmaku(item, positionMs)
          continue
        }
        this.pendingDispatches.push(new PendingDanmakuDispatch(
          item, now + staggerDelay, this.dispatchGeneration))
      }
    }
  }

  private flushPendingDispatches(now: number): void {
    if (this.pendingDispatches.length === 0) {
      return
    }

    let writeIndex = 0
    for (let i = 0; i < this.pendingDispatches.length; i++) {
      const pending = this.pendingDispatches[i]
      if (pending.generation !== this.dispatchGeneration) {
        continue
      }
      if (pending.emitAtMs <= now && this.currentPlaying) {
        this.emitDanmaku(pending.item, this.currentPositionMs)
        continue
      }
      if (writeIndex !== i) {
        this.pendingDispatches[writeIndex] = pending
      }
      writeIndex++
    }
    if (writeIndex < this.pendingDispatches.length) {
      this.pendingDispatches.length = writeIndex
    }
  }

  private emitDanmaku(item: DanmakuItem, positionMs: number): void {
    this.renderer.prepareDanmakuItem(item)
    if (!this.renderer.canAcceptDanmaku()) {
      if (positionMs - item.timeMs <= this.getMaxLateDispatchMs()) {
        return
      }
      this.stats.droppedCount++
      this.stats.lastDropReason = 'active_limit_timeout'
      return
    }

    if (item.type === 4 || item.type === 5) {
      if (!this.renderer.addActiveDanmaku(item)) {
        if (positionMs - item.timeMs <= this.getMaxLateDispatchMs()) {
          return
        }
        this.stats.droppedCount++
        this.stats.lastDropReason = 'fixed_track_timeout'
      }
      return
    }

    const trackIndex = this.trackAllocator.allocateTrack(item)
    if (trackIndex >= 0) {
      item.trackIndex = trackIndex
      item.x = this.renderer.getSpawnX()
      item.isAlive = true
      if (!this.renderer.addActiveDanmaku(item)) {
        return
      }
    } else {
      if (positionMs - item.timeMs <= this.getMaxLateDispatchMs()) {
        return
      }
      this.stats.droppedCount++
      this.stats.lastDropReason = 'track_full_timeout'
      this.trackAllocator.recordDiscard()
    }
  }

  private dispatchImmediateDanmaku(item: DanmakuItem): boolean {
    if (!this.renderer.isReady()) {
      this.stats.droppedCount++
      this.stats.lastDropReason = 'renderer_not_ready'
      return false
    }

    const filterReason = this.getFilterReason(item)
    if (filterReason.length > 0) {
      this.stats.filteredCount++
      this.stats.lastFilterReason = filterReason
      return false
    }

    this.renderer.prepareDanmakuItem(item)
    if (!this.renderer.canAcceptDanmaku()) {
      this.stats.droppedCount++
      this.stats.lastDropReason = 'active_limit'
      return false
    }

    if (item.type === 4 || item.type === 5) {
      return this.renderer.addActiveDanmaku(item)
    }

    const trackIndex = this.trackAllocator.allocateTrack(item)
    if (trackIndex < 0) {
      this.stats.droppedCount++
      this.stats.lastDropReason = 'track_full'
      this.trackAllocator.recordDiscard()
      return false
    }

    item.trackIndex = trackIndex
    item.x = this.renderer.getSpawnX()
    item.isAlive = true
    return this.renderer.addActiveDanmaku(item)
  }

  private getMaxLateDispatchMs(): number {
    return Math.max(BASE_MAX_LATE_DISPATCH_MS, Math.floor(this.settings.scrollDurationSec * 900))
  }

  private getFilterReason(item: DanmakuItem): string {
    if (this.settings.hideScroll && item.type !== 4 && item.type !== 5) {
      return 'hide_scroll'
    }
    if (this.settings.hideBottom && item.type === 4) {
      return 'hide_bottom'
    }
    if (this.settings.hideTop && item.type === 5) {
      return 'hide_top'
    }
    if (this.settings.hideColor && item.color !== '#FFFFFF') {
      return 'hide_color'
    }
    if (!this.isSourceEnabled(item.source)) {
      return 'source_disabled'
    }
    if (item.content.length > this.settings.maxLength) {
      return 'max_length'
    }
    if (this.settings.blockKeywordsEnabled && this.isKeywordBlocked(item.content)) {
      return 'block_keyword'
    }
    if (this.settings.blockRegexEnabled && this.isRegexBlocked(item.content)) {
      return 'block_regex'
    }
    return ''
  }

  private isSourceEnabled(source: string): boolean {
    const normalized = source.toLowerCase()
    if (normalized.length === 0 || normalized === 'local') {
      return true
    }
    if (normalized.indexOf('bilibili') >= 0 || normalized.indexOf('bili') >= 0) {
      return this.settings.biliBiliSource
    }
    if (normalized.indexOf('gamer') >= 0) {
      return this.settings.gamerSource
    }
    return this.settings.danDanSource
  }

  private parseBlockedKeywords(text: string): string[] {
    const keywords: string[] = []
    const parts = text.split(/[\s,，;；、]+/)
    for (let i = 0; i < parts.length; i++) {
      const keyword = parts[i].trim().toLowerCase()
      if (keyword.length > 0) {
        keywords.push(keyword)
      }
    }
    return keywords
  }

  private compileBlockedRegex(text: string): RegExp | null {
    const pattern = text.trim()
    if (pattern.length === 0) {
      return null
    }
    try {
      return new RegExp(pattern, 'i')
    } catch (_err) {
      logger.warn('弹幕正则屏蔽表达式无效，已忽略')
      return null
    }
  }

  private isKeywordBlocked(content: string): boolean {
    if (this.blockedKeywords.length === 0) {
      return false
    }
    const normalized = content.toLowerCase()
    for (let i = 0; i < this.blockedKeywords.length; i++) {
      if (normalized.includes(this.blockedKeywords[i])) {
        return true
      }
    }
    return false
  }

  private isRegexBlocked(content: string): boolean {
    if (this.blockedRegex === null) {
      return false
    }
    return this.blockedRegex.test(content)
  }

  private findDispatchIndex(targetMs: number): number {
    let left = 0
    let right = this.allDanmaku.length
    while (left < right) {
      const mid = Math.floor((left + right) / 2)
      if (this.allDanmaku[mid].timeMs <= targetMs) {
        left = mid + 1
      } else {
        right = mid
      }
    }
    return left
  }

  private findInsertIndex(targetMs: number): number {
    let left = 0
    let right = this.allDanmaku.length
    while (left < right) {
      const mid = Math.floor((left + right) / 2)
      if (this.allDanmaku[mid].timeMs <= targetMs) {
        left = mid + 1
      } else {
        right = mid
      }
    }
    return left
  }

  private clampPosition(positionMs: number, durationMs: number): number {
    if (positionMs < 0) {
      logger.warn('播放进度异常：positionMs=%{public}d', positionMs)
      return 0
    }
    if (durationMs > 0 && positionMs > durationMs) {
      logger.warn('播放进度异常：positionMs=%{public}d > durationMs=%{public}d',
        positionMs, durationMs)
      return durationMs
    }
    return positionMs
  }
}
