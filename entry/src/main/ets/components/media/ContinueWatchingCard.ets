import { MediaProgressBar } from './MediaProgressBar'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'
import { AppMotion } from '../../ui/theme/AppMotion'
import { AppMediaStyle } from '../../ui/theme/AppMediaStyle'
import { ContinueWatchingPresentation } from './ContinueWatchingPresentation'

@Component
export struct ContinueWatchingCard {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop @Watch('resetArtwork') artworkUrl: string = ''
  @Prop positionMs: number = 0
  @Prop durationMs: number = 0
  @Prop cardWidth: number = AppDimensions.LANDSCAPE_CARD_WIDTH
  @Prop scaleOnlyPress: boolean = false
  @Prop loading: boolean = false
  @State private isPressed: boolean = false
  @State private artworkLoaded: boolean = false
  @State private artworkFailed: boolean = false
  onCardClick?: () => void

  build() {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(this.artworkUrl.length > 0 && !this.artworkFailed ? this.artworkUrl : $r('app.media.ic_placeholder'))
          .width(this.cardWidth)
          .height(this.cardHeight())
          .objectFit(ImageFit.Cover)
          .borderRadius(AppRadius.MEDIA_LANDSCAPE)
          .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.82)
          .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
          .onComplete(() => this.artworkLoaded = true)
          .onError(() => { this.artworkLoaded = true; this.artworkFailed = true })
        if (this.positionMs > 0) {
          Column() {}.width('100%').height(46)
            .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#99000000', 1]] })
          Text($r('app.string.continue_watching_position', ContinueWatchingPresentation.time(this.positionMs)))
            .fontSize(11).fontWeight(FontWeight.Medium).fontColor(Color.White)
            .maxLines(1).margin({ left: 12, bottom: 20 })
        }
        MediaProgressBar({ positionMs: this.positionMs, durationMs: this.durationMs })
          .width(this.cardWidth - 24)
          .margin({ left: 12, bottom: 8 })
        if (this.loading) {
          Column({ space: 6 }) {
            LoadingProgress().width(24).height(24).color(Color.White)
            Text($r('app.string.continue_watching_preparing')).fontSize(11).fontColor(Color.White)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#66000000')
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.cardWidth)
      .height(this.cardHeight())
      .borderRadius(AppRadius.MEDIA_LANDSCAPE).clip(true)
      Text(this.title)
        .fontSize(AppTypography.CARD_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.cardWidth)
      Text(this.subtitle)
        .fontSize(AppTypography.META)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.cardWidth)
    }
    .width(this.cardWidth)
    .scale({ x: this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1 })
    .opacity(this.scaleOnlyPress ? 1 : (this.isPressed ? 0.86 : 1))
    .animation({ duration: this.scaleOnlyPress ? AppMotion.HOME_PRESS_MS : AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onCardClick) this.onCardClick()
    })
  }

  private cardHeight(): number {
    return AppMediaStyle.landscapeHeight(this.cardWidth)
  }
  private resetArtwork(): void { this.artworkLoaded = false; this.artworkFailed = false }
}
