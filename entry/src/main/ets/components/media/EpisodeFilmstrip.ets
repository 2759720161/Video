import { AppMotion } from '../../ui/theme/AppMotion'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'

/** Horizontal episode card for the compact phone layout. */
@Component
export struct EpisodeFilmstrip {
  @Prop title: string = ''
  @Prop episodeLabel: string = ''
  @Prop artworkUrl: string = ''
  @Prop progress: number = 0
  @Prop played: boolean = false
  @Prop resume: boolean = false
  @Prop resumeColor: string = '#2B5BBD'
  @State private isPressed: boolean = false
  @State private artworkLoaded: boolean = false
  onEpisodeClick?: () => void

  build() {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
          .width(160).height(90).objectFit(ImageFit.Cover)
          .borderRadius(AppRadius.SMALL_BUTTON)
          .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.68)
          .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
          .onComplete(() => this.artworkLoaded = true)
          .onError(() => this.artworkLoaded = true)
        if (this.progress > 0) {
          Progress({ value: Math.min(100, Math.max(0, this.progress)), total: 100, type: ProgressType.Linear })
            .width(144).height(3).color(this.resumeColor)
            .backgroundColor('#88000000').margin({ bottom: 5 })
        }
        if (this.resume) {
          Text('继续观看')
            .fontSize(10).fontColor(Color.White)
            .backgroundColor(this.resumeColor)
            .borderRadius(5)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .margin({ left: 6, bottom: 8 })
            .align(Alignment.BottomStart)
        }
      }
      .width(160).height(90)
      Text(this.episodeLabel + (this.title.length > 0 ? '  ' + this.title : ''))
        .fontSize(AppTypography.CARD_TITLE)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(160)
      Text(this.played ? '已看完' : (this.progress > 0 ? '已观看 ' + String(Math.round(this.progress)) + '%' : '点击播放'))
        .fontSize(AppTypography.META)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(160)
    }
    .width(160)
    .padding({ left: 6, right: 6, top: 6, bottom: 8 })
    .borderRadius(AppRadius.SURFACE)
    .backgroundColor(this.resume ? this.resumeSurfaceColor() : Color.Transparent)
    .scale({ x: this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1 })
    .opacity(this.isPressed ? 0.86 : 1)
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => { if (this.onEpisodeClick) this.onEpisodeClick() })
  }

  private resumeSurfaceColor(): string {
    if (this.resumeColor.length === 7 && this.resumeColor.charAt(0) === '#') {
      return '#14' + this.resumeColor.substring(1)
    }
    return '#142B5C'
  }
}
