/** 播放器进度区纯 UI 组件；拖动策略由页面回调处理。 */
@Component
export struct PlayerProgressBar {
  @Prop positionMs: number = 0
  @Prop durationMs: number = 0
  @Prop isInteractive: boolean = true
  onChange?: (value: number, mode: SliderChangeMode) => void

  build() {
    Row({ space: 8 }) {
      Text(this.formatTime(this.positionMs)).fontSize(12).fontColor($r('app.color.text_on_primary'))
      Slider({ value: this.durationMs > 0 ? this.positionMs : 0, min: 0,
        max: this.durationMs > 0 ? this.durationMs : 1, step: 1000 })
        .layoutWeight(1).trackColor('#55FFFFFF').selectedColor($r('app.color.accent_blue'))
        .blockColor($r('app.color.text_on_primary')).enabled(this.isInteractive)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (this.onChange) this.onChange(value, mode)
        })
      Text(this.formatTime(this.durationMs)).fontSize(12).fontColor($r('app.color.text_on_primary'))
    }
    .width('100%').height(28)
  }

  private formatTime(value: number): string {
    const total = Math.max(0, Math.floor(value / 1000))
    const hours = Math.floor(total / 3600)
    const minutes = Math.floor((total % 3600) / 60)
    const seconds = total % 60
    const mm = minutes < 10 ? '0' + minutes : String(minutes)
    const ss = seconds < 10 ? '0' + seconds : String(seconds)
    return hours > 0 ? hours + ':' + mm + ':' + ss : mm + ':' + ss
  }
}
