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
  @Prop @Watch('resetArtworkState') artworkUrl: string = ''
  @Prop progress: number = 0
  @Prop played: boolean = false
  @Prop isResumeTarget: boolean = false
  @Prop showDivider: boolean = true
  @Prop hideSpoiler: boolean = false
  @Prop playbackEnabled: boolean = true
  @State private isPressed: boolean = false
  @State private artworkLoaded: boolean = false
  @State private artworkFailed: boolean = false
  onRowClick?: () => void

  build() {
    Row({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(this.artworkUrl.length > 0 && !this.artworkFailed ? this.artworkUrl : $r('app.media.ic_placeholder'))
          .width(88).height(50).objectFit(ImageFit.Cover)
          .blur(this.hideSpoiler ? 18 : 0)
          .accessibilityLevel('no')
          .borderRadius(AppRadius.SMALL_BUTTON)
          .opacity(this.artworkUrl.length > 0 ? (this.artworkLoaded ? 1 : 0) : 0.68)
          .animation({ duration: AppMotion.SMALL_TRANSITION_MS, curve: Curve.EaseOut })
          .onComplete(() => this.artworkLoaded = true)
          .onError(() => { this.artworkFailed = true; this.artworkLoaded = true })
        if (this.progress > 0) {
          Progress({ value: Math.min(100, Math.max(0, this.progress)), total: 100, type: ProgressType.Linear })
            .width(76).height(3).color($r('app.color.accent_blue'))
            .backgroundColor('#88000000').align(Alignment.Bottom)
            .margin({ bottom: 5 })
        }
      }.width(88).height(50)
      Column({ space: AppSpacing.XS }) {
        Text(this.hideSpoiler ? '第 ' + this.indexLabel + ' 集' : this.indexLabel + ' · ' + this.title)
          .fontSize(AppTypography.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isResumeTarget ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.meta)
          .fontSize(AppTypography.META)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.played) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18)
          .fontColor([$r('app.color.accent_blue')])
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%').constraintSize({ minHeight: 84 })
    .padding({ top: 12, bottom: 12 }).backgroundColor(Color.Transparent)
    .border({ width: { bottom: this.showDivider ? 0.5 : 0 }, color: $r('app.color.divider_color') })
    .enabled(this.playbackEnabled).accessibilityGroup(true)
    .accessibilityText('第 ' + this.indexLabel + ' 集，' + (this.hideSpoiler ? '' : this.title + '，') + this.meta)
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

  private resetArtworkState(): void {
    this.artworkLoaded = false
    this.artworkFailed = false
  }
}
