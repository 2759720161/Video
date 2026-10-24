import { AppTypography } from '../../ui/theme/AppTypography'

@Component
export struct MediaSectionHeader {
  @Prop title: string = ''
  @Prop actionText: string = ''
  @Prop chevronAction: boolean = false
  onAction?: () => void

  build() {
    Row() {
      Text(this.title)
        .fontSize(AppTypography.SECTION_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.chevronAction) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20)
            .fontColor([$r('app.color.text_secondary')]).accessibilityLevel('no')
        }.width(44).height(44).backgroundColor(Color.Transparent).margin({ right: -12 })
          .accessibilityText(this.actionText)
          .onClick(() => { if (this.onAction) this.onAction() })
      } else if (this.actionText.length > 0) {
        Row() {
          Text(this.actionText)
            .fontSize(AppTypography.BODY)
            .fontColor($r('app.color.accent_blue'))
        }
        .height(44)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.onAction) this.onAction()
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
