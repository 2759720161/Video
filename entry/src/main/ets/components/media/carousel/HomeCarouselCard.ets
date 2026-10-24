import { matrix4 } from '@kit.ArkUI'
import { HomeCarouselLayout } from './HomeCarouselLayout'
import { HomeCarouselProjection } from './HomeCarouselProjection'
import { AppMotion } from '../../../ui/theme/AppMotion'

@Component
export struct HomeCarouselCard {
  @Prop @Watch('resetArtwork') artworkUrl: string = ''
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop viewportWidth: number = 360
  @Prop posePosition: number = 0
  @Prop shadeOpacity: number = 0
  @Prop faceOpacity: number = 1
  @State private failed: boolean = false
  @State private sourceRatio: number = 2 / 3
  @State private decoded: boolean = false
  @State private isPressed: boolean = false
  onOpen: () => void = () => {}
  onArtworkError: (url: string) => void = () => {}

  private resetArtwork(): void { this.failed = false; this.sourceRatio = 2 / 3; this.decoded = false }
  aboutToDisappear(): void { this.isPressed = false }

  private artworkLoaded(url: string, width: number, height: number, status: number): void {
    if (url !== this.artworkUrl || this.failed || !Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) return
    this.sourceRatio = HomeCarouselLayout.artworkRatio(width, height)
    if (status === 1) this.decoded = true
  }

  private artworkFailed(url: string): void {
    if (url !== this.artworkUrl) return
    this.failed = true; this.decoded = false; this.onArtworkError(url)
  }

  private faceTransform(): matrix4.Matrix4Transit {
    const values = HomeCarouselProjection.matrixValues(this.posePosition, this.viewportWidth, this.getUIContext().vp2px(1))
    return matrix4.init([values[0], values[1], values[2], values[3],
      values[4], values[5], values[6], values[7], values[8], values[9], values[10], values[11],
      values[12], values[13], values[14], values[15]])
  }

  @Builder
  private Poster(url: string): void {
    // Only the fitted image and its clipped shade enter the offscreen group, never the empty slot.
    Stack() {
      Stack() {
        Image(url).width('100%').height('100%').objectFit(ImageFit.Contain).draggable(false)
          .onComplete((event) => {
            if (event !== undefined) this.artworkLoaded(url, event.width, event.height, event.loadingStatus)
          })
          .onError(() => this.artworkFailed(url))
        Row().width('100%').height('100%').backgroundColor(Color.Black)
          .opacity(Math.max(0, Math.min(0.4, this.shadeOpacity))).hitTestBehavior(HitTestMode.None)
      }.width('100%').height('100%').opacity(this.decoded ? 1 : 0)
        .animation({ duration: 180, curve: Curve.EaseOut })
        .scale({ x: this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1 })
        .animation({ duration: AppMotion.HOME_PRESS_MS, curve: Curve.EaseOut })
        .borderRadius(HomeCarouselLayout.artworkRadius(this.viewportWidth, this.sourceRatio)).clip(true)
        .renderGroup(true)
    }.width(HomeCarouselLayout.artworkWidth(this.viewportWidth, this.sourceRatio))
      .height(HomeCarouselLayout.artworkHeight(this.viewportWidth, this.sourceRatio))
      .transform3D(this.faceTransform()).opacity(this.faceOpacity)
  }

  build() {
    Stack() {
      if (this.artworkUrl.length > 0 && !this.failed) {
        this.Poster(this.artworkUrl)
      } else {
        SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(36)
          .fontColor([$r('app.color.text_hint')]).transform3D(this.faceTransform()).opacity(this.faceOpacity)
      }
    }.width('100%').height(HomeCarouselLayout.cardHeight(this.viewportWidth))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) this.isPressed = true
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
      })
      .accessibilityText(this.title + (this.subtitle.length > 0 ? '，' + this.subtitle : ''))
      .accessibilityGroup(true).onClick(() => this.onOpen())
  }
}
