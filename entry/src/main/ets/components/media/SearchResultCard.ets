import { MediaSearchItem } from '../../services/media/MediaSearchPresentation'
import { createArtworkTransitionId } from '../../utils/ArtworkTransition'

@Component
export struct SearchResultCard {
  @Prop item: MediaSearchItem = new MediaSearchItem()
  @Prop @Watch('resetArtwork') artworkUrl: string = ''
  @Prop cardWidth: number = 100
  @Prop listMode: boolean = false
  @Prop showSource: boolean = false
  @State private failed: boolean = false
  private readonly transitionId: string = createArtworkTransitionId()
  onOpen: (transitionId: string) => void = () => {}

  private resetArtwork(): void { this.failed = false }
  private artworkFailed(url: string): void { if (url === this.artworkUrl) this.failed = true }

  @Builder
  private Artwork(url: string, width: number, height: number): void {
    if (this.item.embyItem !== null) {
      Image(url.length > 0 && !this.failed ? url : $r('app.media.ic_placeholder'))
        .width(width).height(height).objectFit(ImageFit.Cover).draggable(false).borderRadius(12).clip(true)
        .sharedTransition(this.transitionId, { duration: 360, curve: Curve.FastOutSlowIn })
        .onError(() => this.artworkFailed(url))
    } else {
      Image(url.length > 0 && !this.failed ? url : $r('app.media.ic_placeholder'))
        .width(width).height(height).objectFit(ImageFit.Cover).draggable(false).borderRadius(12).clip(true)
        .onError(() => this.artworkFailed(url))
    }
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      if (this.listMode) {
        Row({ space: 14 }) {
          this.Artwork(this.artworkUrl, 80, 120)
          Column({ space: 7 }) {
            Text(this.item.title).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (this.item.subtitle.length > 0) {
              Text(this.item.subtitle).fontSize(12).fontColor($r('app.color.text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
            if (this.item.overview.length > 0) {
              Text(this.item.overview).fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted'))
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
            Text(this.item.sourceName).fontSize(11).fontColor($r('app.color.text_hint'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding(12).alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 7 }) {
          this.Artwork(this.artworkUrl, this.cardWidth, this.cardWidth * 1.5)
          Text(this.item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').height(40).textAlign(TextAlign.Start)
          Text(this.item.subtitle).fontSize(11).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').height(16).textAlign(TextAlign.Start)
          if (this.showSource) {
            Text(this.item.sourceName).fontSize(11).fontColor($r('app.color.accent_blue'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').height(16).textAlign(TextAlign.Start)
          }
        }.width(this.cardWidth).alignItems(HorizontalAlign.Start)
      }
    }.width(this.listMode ? '100%' : this.cardWidth).padding(0).borderRadius(16)
      .backgroundColor(this.listMode ? $r('app.color.card_background') : Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
      .accessibilityText(this.item.title + '，' + this.item.subtitle + '，' + this.item.sourceName)
      .onClick(() => this.onOpen(this.item.embyItem !== null ? this.transitionId : ''))
  }
}
