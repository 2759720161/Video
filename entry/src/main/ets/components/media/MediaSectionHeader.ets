import { AppTypography } from '../../ui/theme/AppTypography'

@Component
export struct MediaSectionHeader {
  @Prop title: string = ''
  @Prop actionText: string = ''
  onAction?: () => void

  build() {
    Row() {
      Text(this.title)
        .fontSize(AppTypography.SECTION_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(AppTypography.BODY)
          .fontColor($r('app.color.accent_blue'))
          .onClick(() => {
            if (this.onAction) this.onAction()
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
