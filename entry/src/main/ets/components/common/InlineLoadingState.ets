/** 行内加载状态，用于列表刷新或局部内容同步。 */
@Component
export struct InlineLoadingState {
  @Prop message: string = '正在加载'

  build() {
    Row({ space: 8 }) {
      LoadingProgress().width(20).height(20)
      Text(this.message).fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').height(40).justifyContent(FlexAlign.Center)
  }
}
