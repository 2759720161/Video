import { MediaProgressBar } from './MediaProgressBar'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'
import { AppMotion } from '../../ui/theme/AppMotion'
import { AppSpacing } from '../../ui/theme/AppSpacing'

/** V3 immersive hero: artwork first, with a restrained bottom scrim and one CTA. */
@Component
export struct MediaHero {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop artworkUrl: string = ''
  @Prop positionMs: number = 0
  @Prop durationMs: number = 0
  @Prop heightVp: number = AppDimensions.HERO_PHONE_HEIGHT
  @Prop widthVp: number = 0
  @Prop actionText: string = '继续播放'
  @Prop actionEnabled: boolean = true
  @Prop secondaryActionText: string = ''
  @State private artworkLoaded: boolean = false
  onPlay?: () => void
  onSecondaryAction?: () => void

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
        .width('100%').height(this.resolvedHeight()).objectFit(ImageFit.Cover).draggable(false)
        .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.78)
        .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
        .onComplete(() => this.artworkLoaded = true)
        .onError(() => this.artworkLoaded = true)
      Column({ space: AppSpacing.SM }) {
        Text(this.title)
          .fontSize(AppTypography.HERO_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subtitle)
          .fontSize(AppTypography.BODY)
          .fontColor('#E6FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        MediaProgressBar({ positionMs: this.positionMs, durationMs: this.durationMs })
        Row({ space: 12 }) {
          Button(this.actionText)
          .height(44)
          .fontSize(AppTypography.BODY_LARGE)
          .fontColor($r('app.color.text_on_primary'))
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(AppRadius.BUTTON)
          .enabled(this.actionEnabled)
          .onClick(() => {
            if (this.onPlay) this.onPlay()
          })
          if (this.secondaryActionText.length > 0) {
            Button(this.secondaryActionText).height(44).fontSize(AppTypography.BODY)
              .fontColor(Color.White).backgroundColor('#44000000')
              .onClick(() => { if (this.onSecondaryAction) this.onSecondaryAction() })
          }
        }
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG, bottom: AppSpacing.MD })
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [[Color.Transparent, 0], ['#E6000000', 0.72], ['#F0000000', 1]]
      })
    }
    .width('100%')
    .height(this.resolvedHeight())
    .borderRadius(AppRadius.HERO)
    .clip(true)
    .scale({ x: 1, y: 1 })
    .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
  }

  private resolvedHeight(): number {
    if (!Number.isFinite(this.widthVp) || this.widthVp <= 0) return this.heightVp
    const preferred = Math.round(this.widthVp * 0.62)
    return Math.min(AppDimensions.HERO_MAX_HEIGHT, Math.max(AppDimensions.HERO_MIN_HEIGHT, preferred))
  }
}
