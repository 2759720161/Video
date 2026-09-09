import { PlayerControlButton } from './PlayerControlButton'

/** 播放器高频主控组，上一项/下一项由队列存在性决定。 */
@Component
export struct PlayerPrimaryControls {
  @Prop isPlaying: boolean = false
  @Prop showQueue: boolean = false
  @Prop seekBackSymbol: Resource = $r('sys.symbol.gobackward_10')
  @Prop seekForwardSymbol: Resource = $r('sys.symbol.goforward_10')
  onSeekBack?: () => void
  onPrevious?: () => void
  onPlayPause?: () => void
  onNext?: () => void
  onSeekForward?: () => void

  build() {
    Row({ space: 6 }) {
      PlayerControlButton({ symbol: this.seekBackSymbol, onButtonClick: () => { if (this.onSeekBack) this.onSeekBack() } })
      if (this.showQueue) {
        PlayerControlButton({ symbol: $r('sys.symbol.backward_end_fill'), onButtonClick: () => { if (this.onPrevious) this.onPrevious() } })
      }
      PlayerControlButton({ symbol: this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
        buttonWidth: 52, buttonHeight: 52, iconSize: 26,
        onButtonClick: () => { if (this.onPlayPause) this.onPlayPause() } })
        .backgroundColor($r('app.color.accent_blue')).borderRadius(26)
      if (this.showQueue) {
        PlayerControlButton({ symbol: $r('sys.symbol.forward_end_fill'), onButtonClick: () => { if (this.onNext) this.onNext() } })
      }
      PlayerControlButton({ symbol: this.seekForwardSymbol, onButtonClick: () => { if (this.onSeekForward) this.onSeekForward() } })
    }
    .height(54).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
  }
}
