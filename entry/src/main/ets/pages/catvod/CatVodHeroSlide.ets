import { CatVodVideo } from '../../providers/catvod/CatVodModels'
import { CatVodHeroPresentation } from './CatVodHeroPresentation'

@Component
export struct CatVodHeroSlide {
  @Prop video: CatVodVideo = new CatVodVideo()
  @Prop viewportWidth: number = 360
  @Prop topInset: number = 0
  @Prop surfaceColor: ResourceColor = $r('app.color.page_background')
  @State private artworkFailed: boolean = false
  onOpen: (video: CatVodVideo) => void = () => {}
  onArtworkError: (url: string) => void = () => {}

  build() {
    Stack() {
      this.Background()
      Row() {
        Column({ space: 8 }) {
          Text(this.video.name).fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_on_primary')).lineHeight(28)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            .textShadow({ radius: 8, color: $r('app.color.cat_hero_text_shadow'), offsetY: 1 })
          if (CatVodHeroPresentation.summary(this.video).length > 0) {
            Text(CatVodHeroPresentation.summary(this.video)).fontSize(13).lineHeight(18)
              .fontColor($r('app.color.text_overlay_dim')).width('100%')
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              .textShadow({ radius: 6, color: $r('app.color.cat_hero_text_shadow'), offsetY: 1 })
          }
          if (CatVodHeroPresentation.metadata(this.video).length > 0) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(CatVodHeroPresentation.metadata(this.video), (value: string, index: number) => {
                Text(value).fontSize(11).fontColor($r('app.color.text_overlay_dim'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(10)
                  .backgroundColor($r('app.color.cat_hero_badge_background')).margin({ right: 8, bottom: 4 })
              }, (value: string, index: number) => String(index) + ':' + value)
            }.width('100%')
          }
        }.layoutWeight(1).padding({ left: 20, right: 10 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
        Column() {
          Stack() {
            SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(32).fontColor([$r('app.color.text_hint')])
            if (!this.artworkFailed) {
              Image(this.video.poster).width('100%').height('100%').objectFit(ImageFit.Cover)
                .draggable(false).borderRadius(12).onError(() => {
                  this.artworkFailed = true; this.onArtworkError(this.video.poster)
                })
            }
          }.width('100%').height('100%').backgroundColor($r('app.color.skeleton_background')).borderRadius(12)
            .shadow({ radius: 20, color: $r('app.color.cat_hero_text_shadow'), offsetY: 8 })
        }.width(CatVodHeroPresentation.posterWidth(this.viewportWidth))
          .height(Math.round(CatVodHeroPresentation.posterWidth(this.viewportWidth) * 4 / 3))
          .padding({ left: 4, right: 18 }).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').alignItems(VerticalAlign.Center)
        .padding({ top: this.topInset + (this.viewportWidth >= 600 ? 28 : 24),
          bottom: this.viewportWidth >= 600 ? 54 : 48 })
    }.width('100%').height(CatVodHeroPresentation.height(this.viewportWidth, this.topInset))
      .accessibilityText(this.video.name).accessibilityGroup(true)
      .onClick(() => this.onOpen(this.video))
  }

  @Builder
  private Background(): void {
    Stack({ alignContent: Alignment.Top }) {
      if (!this.artworkFailed) {
        if (this.viewportWidth >= 600) {
          Image(this.video.poster).width('100%').aspectRatio(16 / 9).objectFit(ImageFit.Cover)
            .blur(14).opacity(0.72).draggable(false)
        } else {
          Image(this.video.poster).width('100%').height('100%').objectFit(ImageFit.Cover)
            .blur(14).opacity(0.72).draggable(false)
        }
      }
      Column().width('100%').height('100%')
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [[$r('app.color.hero_gradient_start'), 0], [$r('app.color.hero_gradient_dark'), 0.34],
            [this.surfaceColor, 1]] })
        .animation({ duration: 500, curve: Curve.EaseInOut })
    }.width('100%').height('100%').backgroundColor(this.surfaceColor)
      .animation({ duration: 500, curve: Curve.EaseInOut })
      .clip(true).hitTestBehavior(HitTestMode.None)
  }

}
