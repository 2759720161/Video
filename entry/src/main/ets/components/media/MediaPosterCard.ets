import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'

@Component
export struct MediaPosterCard {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop artworkUrl: string = ''
  @State private isPressed: boolean = false
  onCardClick?: () => void

  build() {
    Column({ space: 6 }) {
      Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
        .width(AppDimensions.POSTER_CARD_WIDTH)
        .height(AppDimensions.POSTER_CARD_HEIGHT)
        .objectFit(ImageFit.Cover)
        .borderRadius(AppRadius.CARD)
      Text(this.title)
        .fontSize(AppTypography.CARD_TITLE)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(AppDimensions.POSTER_CARD_WIDTH)
      Text(this.subtitle)
        .fontSize(AppTypography.META)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(AppDimensions.POSTER_CARD_WIDTH)
    }
    .width(AppDimensions.POSTER_CARD_WIDTH)
    .scale({ x: this.isPressed ? 0.96 : 1, y: this.isPressed ? 0.96 : 1 })
    .opacity(this.isPressed ? 0.86 : 1)
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onCardClick) this.onCardClick()
    })
  }
}
