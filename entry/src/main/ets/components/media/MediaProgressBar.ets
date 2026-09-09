@Component
export struct MediaProgressBar {
  @Prop positionMs: number = 0
  @Prop durationMs: number = 0

  build() {
    if (this.durationMs > 0 && this.positionMs > 0) {
      Progress({
        value: Math.min(this.positionMs, this.durationMs),
        total: this.durationMs,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(3)
        .color($r('app.color.accent_blue'))
        .backgroundColor('#55000000')
    }
  }
}
