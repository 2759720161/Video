import { ProviderIcon } from './ProviderIcon'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'

@Component
export struct MediaSourceShortcutCard {
  @Prop title: string = ''
  @Prop providerType: string = ''
  @Prop statusText: string = ''
  @Prop isEnabled: boolean = true
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
        .width(120)
      Text(this.providerLabel())
        .fontSize(AppTypography.CAPTION)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(120)
      if (this.statusText.length > 0) {
        Text(this.statusText)
        .fontSize(AppTypography.CAPTION)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(120)
      }
    }
    .width(AppDimensions.SOURCE_CARD_WIDTH)
    .height(AppDimensions.SOURCE_CARD_HEIGHT)
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(AppRadius.CARD)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? (this.isPressed ? 0.86 : 1) : 0.55)
    .scale({ x: this.isPressed ? 0.96 : 1, y: this.isPressed ? 0.96 : 1 })
    .animation({ duration: 140, curve: Curve.EaseOut })
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
