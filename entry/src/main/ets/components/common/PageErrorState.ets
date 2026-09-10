import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'

/** 页面级错误状态，统一重试入口和错误详情展示。 */
@Component
export struct PageErrorState {
  @Prop title: string = '加载失败'
  @Prop message: string = ''
  @Prop retryText: string = '重试'
  onRetry?: () => void

  build() {
    Column({ space: AppSpacing.SMALL }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(34).fontColor([$r('app.color.status_error')])
      Text(this.title).fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.message.length > 0) {
        Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary'))
          .maxLines(3).textAlign(TextAlign.Center)
      }
      Button(this.retryText).height(44).fontSize(13)
        .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
        .borderRadius(AppRadius.BUTTON)
        .onClick(() => { if (this.onRetry) this.onRetry() })
    }
    .width('100%').padding({ top: AppSpacing.SECTION, bottom: AppSpacing.SECTION,
      left: AppSpacing.CARD_CONTENT, right: AppSpacing.CARD_CONTENT })
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
