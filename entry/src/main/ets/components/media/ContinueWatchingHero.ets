import { MediaProgressBar } from './MediaProgressBar'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'

@Component
export struct ContinueWatchingHero {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop artworkUrl: string = ''
  @Prop positionMs: number = 0
  @Prop durationMs: number = 0
  @Prop heightVp: number = AppDimensions.HERO_PHONE_HEIGHT
  onHeroPlay?: () => void

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
        .width('100%')
        .height(this.heightVp)
        .objectFit(ImageFit.Cover)
        .borderRadius(AppRadius.HERO)
        .opacity(this.artworkUrl.length > 0 ? 1 : 0.78)
      Column({ space: 8 }) {
        Text(this.title)
          .fontSize(AppTypography.HERO_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subtitle)
          .fontSize(AppTypography.BODY)
          .fontColor('#E6FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        MediaProgressBar({ positionMs: this.positionMs, durationMs: this.durationMs })
        Button('继续播放')
          .height(44)
          .fontSize(AppTypography.BODY)
          .fontColor($r('app.color.text_on_primary'))
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(AppRadius.BUTTON)
          .onClick(() => {
            if (this.onHeroPlay) this.onHeroPlay()
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 16 })
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [[Color.Transparent, 0], ['#CC000000', 1]]
      })
    }
    .width('100%')
    .height(this.heightVp)
    .borderRadius(AppRadius.HERO)
    .clip(true)
  }
}
