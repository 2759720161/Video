import { ProviderIcon } from './ProviderIcon'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'
import { AppMotion } from '../../ui/theme/AppMotion'
import { AppSurface } from '../../ui/theme/AppSurface'

@Component
export struct MediaSourceShortcutCard {
  @Prop title: string = ''
  @Prop providerType: string = ''
  @Prop statusText: string = ''
  @Prop isEnabled: boolean = true
  @Prop tileWidth: number = 128
  @Prop tileHeight: number = 80
  @State private isPressed: boolean = false
  onCardClick?: () => void

  build() {
    Column({ space: 7 }) {
      ProviderIcon({ providerType: this.providerType })
      Text(this.title)
        .fontSize(AppTypography.CARD_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.tileWidth - 16)
      Text(this.providerLabel())
        .fontSize(AppTypography.CAPTION)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.tileWidth - 16)
      if (this.statusText.length > 0) {
        Text(this.statusText)
        .fontSize(AppTypography.CAPTION)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(this.tileWidth - 16)
      }
    }
    .width(this.tileWidth)
    .height(this.tileHeight)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
    .borderRadius(AppRadius.SMALL_BUTTON)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE_INTERACTIVE))
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? (this.isPressed ? 0.86 : 1) : 0.55)
    .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onCardClick) this.onCardClick()
    })
  }

  private providerLabel(): string {
    const descriptor = ProviderCatalog.get(this.providerType)
    return descriptor === null || descriptor.displayName.length === 0 ? this.providerType : descriptor.displayName
  }
}
