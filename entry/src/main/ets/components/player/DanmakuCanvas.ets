import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuCanvas')

@Component
export struct DanmakuCanvas {
  @Prop isDanmakuEnabled: boolean = true
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  onCanvasReady?: (context: CanvasRenderingContext2D, width: number, height: number) => void
  onCanvasSizeChanged?: (width: number, height: number) => void

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        const width = this.normalizeSize(this.context.width)
        const height = this.normalizeSize(this.context.height)
        logger.info('Canvas ready: contextWidth=%{public}s, contextHeight=%{public}s, width=%{public}d, height=%{public}d',
          String(this.context.width), String(this.context.height), width, height)
        if (this.onCanvasReady) {
          this.onCanvasReady(this.context, width, height)
        }
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = this.normalizeSize(newArea.width)
        const height = this.normalizeSize(newArea.height)
        logger.info('Canvas area changed: rawWidth=%{public}s, rawHeight=%{public}s, width=%{public}d, height=%{public}d',
          String(newArea.width), String(newArea.height), width, height)
        if (width > 0 && height > 0 && this.onCanvasSizeChanged) {
          this.onCanvasSizeChanged(width, height)
        } else {
          logger.warn('Canvas area invalid: width=%{public}d, height=%{public}d', width, height)
        }
      })
  }

  private normalizeSize(value: Length): number {
    if (typeof value === 'number') {
      return Math.ceil(value)
    }
    const text = String(value)
    const parsed = parseFloat(text)
    if (isNaN(parsed)) {
      return 0
    }
    return Math.ceil(parsed)
  }
}
