import { AppMotion } from '../../ui/theme/AppMotion'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppSurface } from '../../ui/theme/AppSurface'
import { AppTypography } from '../../ui/theme/AppTypography'

/** Detail hero shared by phone and wide layouts. */
@Component
export struct MediaDetailHero {
  @Prop title: string = ''
  @Prop meta: string = ''
  @Prop overview: string = ''
  @Prop artworkUrl: string = ''
  @Prop usePosterFallback: boolean = false
  @Prop wide: boolean = false
  @Prop artworkWidth: number = 280
  @Prop artworkHeight: number = 420
  @Prop showIdentity: boolean = true
  @Prop showAction: boolean = true
  @Prop showOverview: boolean = true
  @Prop actionText: string = '播放'
  @State private artworkLoaded: boolean = false
  @State private isPressed: boolean = false
  onPrimaryAction?: () => void

  build() {
    if (this.wide) {
      this.WideHero()
    } else {
      this.PhoneHero()
    }
  }

  @Builder
  private PhoneHero(): void {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.Artwork(240, ImageFit.Cover)
      if (this.showIdentity || this.showAction || this.showOverview) {
        Column({ space: AppSpacing.SM }) {
          if (this.showIdentity) {
            Text(this.title)
              .fontSize(AppTypography.HERO_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.meta)
              .fontSize(AppTypography.META)
              .fontColor('#E6FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.showAction && this.onPrimaryAction) {
            this.PrimaryButton()
          }
          if (this.showOverview && this.overview.length > 0) {
            Text(this.overview)
              .fontSize(AppTypography.BODY)
              .fontColor('#F0FFFFFF')
              .lineHeight(22)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XL, bottom: AppSpacing.MD })
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [[Color.Transparent, 0], ['#E6000000', 0.7], ['#F0000000', 1]] })
      }
    }
    .width('100%')
    .height(240)
    .borderRadius(AppRadius.HERO)
    .clip(true)
  }

  @Builder
  private WideHero(): void {
    Row({ space: AppSpacing.XL }) {
      this.WideArtwork()
      if (this.showIdentity || this.showAction || this.showOverview) {
        Column({ space: AppSpacing.MD }) {
          if (this.showIdentity) {
            Text(this.title)
              .fontSize(AppTypography.PAGE_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.meta)
              .fontSize(AppTypography.META)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          if (this.showAction && this.onPrimaryAction) {
            this.PrimaryButton()
          }
          if (this.showOverview && this.overview.length > 0) {
            Text(this.overview)
              .fontSize(AppTypography.BODY)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(22)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width(this.showIdentity || this.showAction || this.showOverview ? '100%' : this.artworkWidth)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private WideArtwork(): void {
    if (this.artworkUrl.length > 0) {
      Image(this.artworkUrl)
        .width(this.artworkWidth)
        .height(this.artworkHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(AppRadius.MEDIA_POSTER)
        .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
        .opacity(this.artworkLoaded ? 1 : 0)
        .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
        .onComplete(() => this.artworkLoaded = true)
        .onError(() => this.artworkLoaded = true)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.play_round_rectangle'))
          .fontSize(48)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(this.artworkWidth)
      .height(this.artworkHeight)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(AppRadius.MEDIA_POSTER)
      .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
    }
  }

  @Builder
  private Artwork(heightVp: number, fit: ImageFit): void {
    if (this.artworkUrl.length > 0) {
      Image(this.artworkUrl)
        .width('100%')
        .height(heightVp)
        .objectFit(this.usePosterFallback ? ImageFit.Contain : fit)
        .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
        .opacity(this.artworkLoaded ? 1 : 0)
        .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
        .onComplete(() => this.artworkLoaded = true)
        .onError(() => this.artworkLoaded = true)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.play_round_rectangle'))
          .fontSize(48)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .height(heightVp)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
    }
  }

  @Builder
  private PrimaryButton(): void {
    Button(this.actionText)
      .height(48)
      .constraintSize({ minWidth: 144 })
      .fontSize(AppTypography.BODY_LARGE)
      .fontColor($r('app.color.text_on_primary'))
      .backgroundColor($r('app.color.accent_blue'))
      .borderRadius(AppRadius.BUTTON)
      .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1,
        y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) this.isPressed = true
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
      })
      .onClick(() => {
        if (this.onPrimaryAction) this.onPrimaryAction()
      })
  }
}
