import { AppMotion } from '../../ui/theme/AppMotion'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'

/** Compact episode row used by series and season detail pages. */
@Component
export struct EpisodeRow {
  @Prop indexLabel: string = ''
  @Prop title: string = ''
  @Prop meta: string = ''
  @Prop artworkUrl: string = ''
  @Prop progress: number = 0
  @State private isPressed: boolean = false
  @State private artworkLoaded: boolean = false
  onRowClick?: () => void

  build() {
    Row({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(this.artworkUrl.length > 0 ? this.artworkUrl : $r('app.media.ic_placeholder'))
          .width(104).height(58).objectFit(ImageFit.Cover)
          .borderRadius(AppRadius.SMALL_BUTTON)
          .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.68)
          .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
          .onComplete(() => this.artworkLoaded = true)
          .onError(() => this.artworkLoaded = true)
        if (this.progress > 0) {
          Progress({ value: Math.min(100, Math.max(0, this.progress)), total: 100, type: ProgressType.Linear })
            .width(88).height(3).color($r('app.color.accent_blue'))
            .backgroundColor('#88000000').align(Alignment.Bottom)
            .margin({ bottom: 5 })
        }
      }.width(104).height(58)
      Text(this.indexLabel)
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_secondary'))
        .width(28)
        .textAlign(TextAlign.Center)
      Column({ space: AppSpacing.XS }) {
        Text(this.title)
          .fontSize(AppTypography.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.meta)
          .fontSize(AppTypography.META)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18)
        .fontColor([$r('app.color.accent_blue')])
    }
    .width('100%').height(80)
    .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider_color') })
    .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
    .opacity(this.isPressed ? 0.84 : 1)
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onRowClick) this.onRowClick()
    })
  }
}
