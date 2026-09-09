import { AppSpacing } from '../../ui/theme/AppSpacing'

/** 页面级加载状态，统一图标、文案和垂直留白。 */
@Component
export struct PageLoadingState {
  @Prop title: string = '正在加载'
  @Prop message: string = ''
  @Prop minHeight: number = 240

  build() {
    Column({ space: AppSpacing.CARD_CONTENT }) {
      LoadingProgress().width(38).height(38)
      Text(this.title).fontSize(15).fontColor($r('app.color.text_secondary'))
      if (this.message.length > 0) {
        Text(this.message).fontSize(12).fontColor($r('app.color.text_hint'))
          .maxLines(2).textAlign(TextAlign.Center)
      }
    }
    .width('100%').height(this.minHeight)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
