import { AppMotion } from '../../ui/theme/AppMotion'
import { AppTypography } from '../../ui/theme/AppTypography'

/** HarmonyOS-style setting row with a single, full-width touch target. */
@Component
export struct SettingsRow {
  @Prop icon: Resource
  @Prop title: string = ''
  @Prop value: string = ''
  @Prop showChevron: boolean = true
  @State private isPressed: boolean = false
  onRowClick?: () => void

  build() {
    Row() {
      SymbolGlyph(this.icon).fontSize(24).fontColor([$r('app.color.accent_blue')])
        .width(34).margin({ right: 12 })
      Text(this.title).fontSize(AppTypography.BODY_LARGE).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      if (this.value.length > 0) {
        Text(this.value).fontSize(AppTypography.BODY).fontColor($r('app.color.text_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ right: 10 })
      }
      if (this.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
          .fontColor([$r('sys.color.icon_secondary')])
      }
    }
    .width('100%').height(56).padding({ left: 16, right: 16 })
    .backgroundColor(this.isPressed ? $r('app.color.category_menu_item_selected') : Color.Transparent)
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onRowClick) this.onRowClick()
    })
  }
}
