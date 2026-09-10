import { PlayerControlButton } from './PlayerControlButton'
import { PlayerImageControlButton } from './PlayerImageControlButton'

/** 播放器顶栏纯 UI 组件；播放器生命周期和动作仍由页面注入。 */
@Component
export struct PlayerTopBar {
  @Prop title: string = ''
  @Prop topInset: number = 0
  @Prop showPiP: boolean = false
  onBack?: () => void
  onPiP?: () => void
  onMore?: () => void

  build() {
    Row() {
      PlayerControlButton({ symbol: $r('sys.symbol.chevron_left'), buttonWidth: 48, buttonHeight: 48,
        iconSize: 28, onButtonClick: () => { if (this.onBack) this.onBack() } })
      Text(this.title.length > 0 ? this.title : '本地播放')
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_on_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1).margin({ left: 10, right: 10 })
      if (this.showPiP) {
        PlayerImageControlButton({ image: $r('app.media.ic_pip'), onButtonClick: () => {
          if (this.onPiP) this.onPiP()
        } })
      }
      PlayerControlButton({ symbol: $r('sys.symbol.more'), buttonWidth: 44, buttonHeight: 44,
        iconSize: 23, onButtonClick: () => { if (this.onMore) this.onMore() } })
    }
    .width('100%').height(this.topInset + 68)
    .padding({ left: 10, right: 14, top: this.topInset + 8, bottom: 8 })
    .linearGradient({ direction: GradientDirection.Bottom,
      colors: [['#AA000000', 0.0], ['#5C000000', 0.55], ['#00000000', 1.0]] })
  }
}
