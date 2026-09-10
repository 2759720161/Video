import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppRadius } from '../../ui/theme/AppRadius'

/** 页面级空状态，允许页面只提供业务文案和可选主操作。 */
@Component
export struct PageEmptyState {
  @Prop icon: Resource = $r('sys.symbol.folder')
  @Prop title: string = '暂无内容'
  @Prop message: string = ''
  @Prop primaryActionText: string = ''
  @Prop minHeight: number = 0
  onPrimaryAction?: () => void

  build() {
    Column({ space: AppSpacing.SMALL }) {
      SymbolGlyph(this.icon).fontSize(34).fontColor([$r('app.color.accent_blue')])
      Text(this.title).fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.message.length > 0) {
        Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary'))
          .maxLines(2).textAlign(TextAlign.Center)
      }
      if (this.primaryActionText.length > 0) {
        Button(this.primaryActionText).height(44).fontSize(13)
          .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
          .borderRadius(AppRadius.BUTTON)
          .onClick(() => { if (this.onPrimaryAction) this.onPrimaryAction() })
      }
    }
    .width('100%').height(this.minHeight > 0 ? this.minHeight : 'auto').padding({ top: AppSpacing.SECTION, bottom: AppSpacing.SECTION,
      left: AppSpacing.CARD_CONTENT, right: AppSpacing.CARD_CONTENT })
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
