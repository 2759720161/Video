import { AppMotion } from '../../ui/theme/AppMotion'

/** Image based player control for system supplied artwork such as PiP. */
@Component
export struct PlayerImageControlButton {
  @Prop image: Resource = $r('app.media.ic_pip')
  @Prop buttonWidth: number = 44
  @Prop buttonHeight: number = 44
  @Prop imageWidth: number = 22
  @Prop imageHeight: number = 22
  @State private isPressed: boolean = false
  onButtonClick?: () => void

  build() {
    Row() {
      Image(this.image)
        .width(this.imageWidth)
        .height(this.imageHeight)
        .draggable(false)
    }
    .width(this.buttonWidth)
    .height(this.buttonHeight)
    .borderRadius(Math.min(this.buttonWidth, this.buttonHeight) / 2)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .scale({ x: this.isPressed ? AppMotion.ICON_PRESS_SCALE : 1,
      y: this.isPressed ? AppMotion.ICON_PRESS_SCALE : 1 })
    .opacity(this.isPressed ? 0.78 : 1)
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onButtonClick) this.onButtonClick()
    })
  }
}
