import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'
import { AppMotion } from '../../ui/theme/AppMotion'
import { AppMediaStyle } from '../../ui/theme/AppMediaStyle'
import { createArtworkTransitionId } from '../../utils/ArtworkTransition'

@Component
export struct MediaPosterCard {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop subtitleColor: ResourceColor = $r('app.color.text_secondary')
  @Prop artworkUrl: string = ''
  @Prop enableSharedTransition: boolean = false
  @Prop scaleOnlyPress: boolean = false
  @Prop cardWidth: number = AppDimensions.POSTER_CARD_WIDTH
  @State private isPressed: boolean = false
  @State private artworkLoaded: boolean = false
  private readonly artworkTransitionId: string = createArtworkTransitionId()
  onCardClick?: (artworkTransitionId: string) => void

  build() {
    Column({ space: 6 }) {
      this.Artwork()
      Text(this.title)
        .fontSize(AppTypography.CARD_TITLE)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.cardWidth)
      Text(this.subtitle)
        .fontSize(AppTypography.META)
        .fontColor(this.subtitleColor)
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
      if (this.onCardClick) this.onCardClick(this.enableSharedTransition ? this.artworkTransitionId : '')
    })
  }

  @Builder
  private Artwork(): void {
    if (this.enableSharedTransition) {
      Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
        .width(this.cardWidth)
        .height(this.cardHeight())
        .objectFit(ImageFit.Cover)
        .borderRadius(AppRadius.MEDIA_POSTER)
        .clip(true)
        .sharedTransition(this.artworkTransitionId, { duration: 360, curve: Curve.FastOutSlowIn })
        .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.82)
        .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
        .onComplete(() => this.artworkLoaded = true)
        .onError(() => this.artworkLoaded = true)
    } else {
      Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
        .width(this.cardWidth)
        .height(this.cardHeight())
        .objectFit(ImageFit.Cover)
        .borderRadius(AppRadius.MEDIA_POSTER)
        .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.82)
        .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
        .onComplete(() => this.artworkLoaded = true)
        .onError(() => this.artworkLoaded = true)
    }
  }

  private cardHeight(): number {
    return AppMediaStyle.posterHeight(this.cardWidth)
  }
}
