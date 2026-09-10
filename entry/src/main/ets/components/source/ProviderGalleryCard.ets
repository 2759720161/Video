import { ProviderIcon } from './ProviderIcon'
import { AppMotion } from '../../ui/theme/AppMotion'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppSurface } from '../../ui/theme/AppSurface'
import { AppTypography } from '../../ui/theme/AppTypography'

/** Gallery card for adding a provider; the whole card is the primary target. */
@Component
export struct ProviderGalleryCard {
  @Prop providerType: string = ''
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop summary: string = ''
  @Prop isEnabled: boolean = true
  @Prop comingSoonText: string = ''
  @State private isPressed: boolean = false
  onCardClick?: () => void

  build() {
    Column({ space: AppSpacing.MD }) {
      ProviderIcon({ providerType: this.providerType })

      Column({ space: AppSpacing.XS }) {
        Text(this.title)
          .fontSize(AppTypography.FEATURE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subtitle)
          .fontSize(AppTypography.META)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text(this.summary)
        .fontSize(AppTypography.CAPTION)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row() {
        Blank().layoutWeight(1)
        if (this.isEnabled) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([$r('app.color.accent_blue')])
        } else {
          Text(this.comingSoonText.length > 0 ? this.comingSoonText : '即将支持')
            .fontSize(AppTypography.CAPTION)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 160 })
    .padding(AppSpacing.MD)
    .borderRadius(AppRadius.SURFACE)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE_INTERACTIVE))
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? (this.isPressed ? 0.86 : 1) : 0.6)
    .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1,
      y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (!this.isEnabled) return
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.isEnabled && this.onCardClick) this.onCardClick()
    })
  }
}
