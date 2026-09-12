import { AppMotion } from '../../ui/theme/AppMotion'

/** Whole-page artwork atmosphere; detail content remains the foreground layer. */
@Component
export struct ImmersiveArtworkBackground {
  @Prop artworkUrl: string = ''
  @Prop primaryColor: string = '#202020'
  @Prop secondaryColor: string = '#101010'
  @Prop artworkMode: string = 'none'
  @Prop ambientOpacity: number = 0.30
  @Prop scrimOpacity: number = 0.50
  @Prop heightVp: number = 560
  @Prop scrollOffsetVp: number = 0

  build() {
    Stack() {
      if (this.artworkUrl.length > 0 && this.artworkMode !== 'none') {
        Image(this.artworkUrl)
          .width('100%')
          .height(this.heightVp)
          .objectFit(ImageFit.Cover)
          .blur(this.artworkMode === 'poster' ? 32 : 24)
          .scale({ x: this.ambientScale(), y: this.ambientScale() })
          .translate({ y: this.backgroundOffset() })
          .opacity(this.fadeFactor() * this.ambientOpacity)
          .draggable(false)
          .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
      }
      if (this.artworkMode !== 'none') {
        Column()
          .width('100%')
          .height(this.heightVp)
          .backgroundColor(this.primaryColor)
          .opacity(this.fadeFactor() * 0.34)
          .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
        Column()
          .width('100%')
          .height(this.heightVp)
          .linearGradient({ direction: GradientDirection.Bottom,
            colors: [[this.secondaryColor, 0], [this.secondaryColor, 0.36],
              [$r('app.color.page_background'), 0.94], [$r('app.color.page_background'), 1]] })
          .opacity(this.fadeFactor())
        Column()
          .width('100%')
          .height(this.heightVp * 0.64)
          .linearGradient({ direction: GradientDirection.Bottom,
            colors: [['#00000000', 0], ['#00000000', 0.3], [this.scrimColor(), 1]] })
          .opacity(this.fadeFactor())
      } else {
        Column()
          .width('100%')
          .height(this.heightVp)
          .backgroundColor($r('app.color.page_background'))
        Column()
          .width('100%')
          .height(this.heightVp * 0.50)
          .linearGradient({ direction: GradientDirection.Bottom,
            colors: [['#00000000', 0], ['#22000000', 1]] })
          .opacity(0.26)
      }
    }
    .width('100%')
    .height(this.heightVp)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  private fadeFactor(): number {
    const progress = Math.max(0, Math.min(1, this.scrollOffsetVp / 220))
    return Math.max(0.08, 1 - progress * 0.92)
  }

  private ambientScale(): number {
    const baseScale = this.artworkMode === 'poster' ? 1.08 : 1.02
    const progress = Math.max(0, Math.min(1, this.scrollOffsetVp / 220))
    return baseScale - Math.min(baseScale - 1, progress * 0.02)
  }

  private backgroundOffset(): number {
    return Math.min(24, Math.max(0, this.scrollOffsetVp) * 0.10)
  }

  private scrimColor(): string {
    const alpha = Math.round(Math.max(0, Math.min(1, this.scrimOpacity)) * 255)
    return '#' + alpha.toString(16).padStart(2, '0') + '000000'
  }
}
