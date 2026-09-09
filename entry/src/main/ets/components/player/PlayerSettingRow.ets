/** 播放设置面板中的统一设置行。 */
@Component
export struct PlayerSettingRow {
  @Prop title: string = ''
  @Prop value: string = ''
  onRowClick?: () => void

  build() {
    Row({ space: 10 }) {
      Text(this.title).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
      if (this.value.length > 0) {
        Text(this.value).fontSize(13).fontColor($r('app.color.text_secondary'))
      }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%').height(46).onClick(() => { if (this.onRowClick) this.onRowClick() })
  }
}
