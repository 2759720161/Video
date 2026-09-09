/** 播放器统一控制按钮，保持最小 44vp 触控区域。 */
@Component
export struct PlayerControlButton {
  @Prop symbol: Resource = $r('sys.symbol.play_fill')
  @Prop buttonWidth: number = 44
  @Prop buttonHeight: number = 44
  @Prop iconSize: number = 22
  @State private isPressed: boolean = false
  onButtonClick?: () => void

  build() {
    Row() {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(this.buttonWidth)
    .height(this.buttonHeight)
    .borderRadius(Math.min(this.buttonWidth, this.buttonHeight) / 2)
    .backgroundColor('#00000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .scale({ x: this.isPressed ? 0.92 : 1, y: this.isPressed ? 0.92 : 1 })
    .opacity(this.isPressed ? 0.78 : 1)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
    .onClick(() => {
      if (this.onButtonClick) this.onButtonClick()
    })
  }
}
