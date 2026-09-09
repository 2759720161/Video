/** 媒体来源异常状态徽标；正常来源不显示该组件。 */
@Component
export struct SourceStatusBadge {
  @Prop text: string = ''

  build() {
    if (this.text.length > 0) {
      Text(this.text)
        .fontSize(11)
        .fontColor($r('app.color.status_error'))
        .backgroundColor($r('app.color.source_badge_bg'))
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .borderRadius(8)
    }
  }
}
