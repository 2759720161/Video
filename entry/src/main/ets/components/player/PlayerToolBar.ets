import { PlayerControlButton } from './PlayerControlButton'

/** 播放器底部低频工具入口。 */
@Component
export struct PlayerToolBar {
  @Prop isDanmakuEnabled: boolean = false
  onDanmaku?: () => void
  onSubtitle?: () => void
  onSpeed?: () => void
  onMore?: () => void
  onFullscreen?: () => void

  build() {
    Row({ space: 8 }) {
      this.ToolItem('弹幕', this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off'),
        () => { if (this.onDanmaku) this.onDanmaku() })
      this.ToolItem('字幕', $r('sys.symbol.AI_word_suggest'),
        () => { if (this.onSubtitle) this.onSubtitle() })
      this.ToolItem('倍速', $r('sys.symbol.speed_100percent'),
        () => { if (this.onSpeed) this.onSpeed() })
      this.ToolItem('更多', $r('sys.symbol.more'),
        () => { if (this.onMore) this.onMore() })
      this.ToolItem('全屏', $r('sys.symbol.rectangle_rotate'),
        () => { if (this.onFullscreen) this.onFullscreen() })
    }
    .height(64).justifyContent(FlexAlign.End)
  }

  @Builder
  private ToolItem(label: string, symbol: Resource, action: () => void): void {
    Column({ space: 1 }) {
      PlayerControlButton({ symbol: symbol, buttonWidth: 40, buttonHeight: 40,
        iconSize: 22, onButtonClick: action })
      Text(label)
        .fontSize(10)
        .fontColor($r('app.color.text_on_primary'))
        .maxLines(1)
    }
    .width(48)
    .height(62)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }
}
