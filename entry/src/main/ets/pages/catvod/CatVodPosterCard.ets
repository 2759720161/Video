import { AppMotion } from '../../ui/theme/AppMotion'

@Component
export struct CatVodPosterCard {
  @Prop title: string = ''
  @Prop remarks: string = ''
  @Prop @Watch('resetArtwork') poster: string = ''
  @Prop cardWidth: number = 100
  @Prop scaleOnlyPress: boolean = false
  @State private failed: boolean = false
  @State private isPressed: boolean = false
  onOpen: () => void = () => {}

  private resetArtwork(): void { this.failed = false }
  aboutToDisappear(): void { this.isPressed = false }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(28)
              .fontColor([$r('app.color.text_hint')])
            if (this.poster.length > 0 && !this.failed) {
              Image(this.poster).width('100%').height('100%').objectFit(ImageFit.Cover)
                .draggable(false).onError(() => { this.failed = true })
            }
          }.width(this.cardWidth).height(this.cardWidth * 1.45).backgroundColor($r('app.color.skeleton_background'))
          if (this.remarks.length > 0) {
            Column() {
              Text(this.remarks).fontSize(11).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_on_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.End)
            }.width('100%').padding({ left: 8, right: 8, top: 24, bottom: 8 })
              .linearGradient({ direction: GradientDirection.Bottom,
                colors: [[Color.Transparent, 0], [$r('app.color.overlay_control_bg'), 1]] })
          }
        }.width(this.cardWidth).height(this.cardWidth * 1.45).borderRadius(12).clip(true)
        Text(this.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').height(38)
          .textAlign(TextAlign.Start)
      }.width(this.cardWidth).alignItems(HorizontalAlign.Start)
    }.width(this.cardWidth).padding(0).borderRadius(12).backgroundColor(Color.Transparent)
      .stateEffect(!this.scaleOnlyPress).shadow({ radius: 0 })
      .scale({ x: this.scaleOnlyPress && this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1,
        y: this.scaleOnlyPress && this.isPressed ? AppMotion.POSTER_PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.HOME_PRESS_MS, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) this.isPressed = true
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
      })
      .accessibilityText(this.title + (this.remarks.length > 0 ? '，' + this.remarks : ''))
      .onClick(() => this.onOpen())
  }
}
