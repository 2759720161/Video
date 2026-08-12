import { DanmakuItem } from '../../models/DanmakuItem'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuTrackAllocator')

const TRACK_GAP = 4
const DEFAULT_FONT_SIZE = 25
const LINE_HEIGHT_RATIO = 1.08
const MIN_LINE_HEIGHT = 14
const MIN_LINE_HEIGHT_RATIO = 1.0
const MAX_LINE_HEIGHT_RATIO = 2.5
const TRACK_REUSE_LEEWAY = 8
const COMPACT_HEIGHT_THRESHOLD = 260
const MIN_COMPACT_TRACKS = 5
const MIN_NORMAL_TRACKS = 8
const MIN_TRACK_FILL_RATIO = 0.75

export class DanmakuTrackAllocator {
  private trackCount: number = 0
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private trackRightBounds: number[] = []
  private discardCount: number = 0
  private fontSize: number = DEFAULT_FONT_SIZE
  private displayAreaRatio: number = 1.0
  private lineHeightRatio: number = LINE_HEIGHT_RATIO
  private lineHeight: number = Math.round(DEFAULT_FONT_SIZE * LINE_HEIGHT_RATIO)

  updateCanvasSize(width: number, height: number): void {
    this.canvasWidth = width
    this.canvasHeight = height
    this.recalculateTracks()
  }

  updateStyle(fontSize: number, displayAreaRatio: number = 1.0, lineHeightRatio: number = LINE_HEIGHT_RATIO): void {
    this.fontSize = Math.max(10, Math.min(48, fontSize))
    this.displayAreaRatio = Math.max(0.25, Math.min(1.0, displayAreaRatio))
    this.lineHeightRatio = Math.max(MIN_LINE_HEIGHT_RATIO, Math.min(MAX_LINE_HEIGHT_RATIO, lineHeightRatio))
    this.recalculateTracks()
  }

  allocateTrack(item: DanmakuItem): number {
    if (this.trackCount === 0) {
      return -1
    }

    const textWidth = item.textWidth > 0 ? item.textWidth : 200
    const itemRightEdge = this.canvasWidth + textWidth + TRACK_GAP

    for (let i = 0; i < this.trackCount; i++) {
      const bound = this.trackRightBounds[i]
      if (bound < 0 || bound <= this.canvasWidth + TRACK_REUSE_LEEWAY) {
        this.trackRightBounds[i] = itemRightEdge
        return i
      }
    }

    return -1
  }

  recordDiscard(): void {
    this.discardCount++
    if (this.discardCount % 50 === 1) {
      logger.info('弹幕轨道溢出：已丢弃%{public}d条弹幕', this.discardCount)
    }
  }

  releaseTrack(trackIndex: number): void {
    if (trackIndex >= 0 && trackIndex < this.trackCount) {
      this.trackRightBounds[trackIndex] = -1
    }
  }

  updateTrackBound(trackIndex: number, rightBound: number): void {
    if (trackIndex >= 0 && trackIndex < this.trackCount) {
      this.trackRightBounds[trackIndex] = rightBound
    }
  }

  getTrackY(trackIndex: number): number {
    if (trackIndex < 0 || trackIndex >= this.trackCount) {
      return 0
    }
    const lineHeight = this.getLineHeight()
    return trackIndex * lineHeight + Math.round(lineHeight / 2)
  }

  getTrackCount(): number {
    return this.trackCount
  }

  getLineHeight(): number {
    return this.lineHeight
  }

  getDisplayHeight(): number {
    return Math.floor(this.canvasHeight * this.displayAreaRatio)
  }

  getDiscardCount(): number {
    return this.discardCount
  }

  reset(): void {
    for (let i = 0; i < this.trackCount; i++) {
      this.trackRightBounds[i] = -1
    }
    this.discardCount = 0
  }

  private recalculateTracks(): void {
    if (this.canvasHeight <= 0) {
      this.trackCount = 0
      this.trackRightBounds = []
      return
    }

    const displayHeight = this.getDisplayHeight()
    const baseLineHeight = this.getBaseLineHeight()
    const naturalTrackCount = Math.floor(displayHeight / baseLineHeight)
    const minTargetTracks = displayHeight < COMPACT_HEIGHT_THRESHOLD ? MIN_COMPACT_TRACKS : MIN_NORMAL_TRACKS
    const minTrackCount = displayHeight >= this.fontSize * minTargetTracks * MIN_TRACK_FILL_RATIO
      ? minTargetTracks
      : 0
    const newTrackCount = Math.max(1, Math.max(naturalTrackCount, minTrackCount))
    const newLineHeight = Math.max(MIN_LINE_HEIGHT, Math.floor(displayHeight / newTrackCount))

    if (newTrackCount === this.trackCount && newLineHeight === this.lineHeight) {
      return
    }

    logger.info('轨道数量变更: %{public}d -> %{public}d, lineHeight=%{public}d',
      this.trackCount, newTrackCount, newLineHeight)
    this.trackCount = newTrackCount
    this.lineHeight = newLineHeight
    this.trackRightBounds = []
    for (let i = 0; i < this.trackCount; i++) {
      this.trackRightBounds.push(-1)
    }
  }

  private getBaseLineHeight(): number {
    return Math.max(MIN_LINE_HEIGHT, Math.round(this.fontSize * this.lineHeightRatio))
  }
}
