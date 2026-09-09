import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'

@Component
export struct QuickAccessCard {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop iconKind: string = 'play'
  @State private isPressed: boolean = false
  onCardClick?: () => void

  build() {
    Column({ space: 7 }) {
      SymbolGlyph(this.iconKind === 'folder' ? $r('sys.symbol.folder') :
        this.iconKind === 'plus' ? $r('sys.symbol.plus') : $r('sys.symbol.play_round_rectangle'))
        .fontSize(25)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.title)
        .fontSize(AppTypography.CARD_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.subtitle)
        .fontSize(AppTypography.CAPTION)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(AppDimensions.SOURCE_CARD_WIDTH)
    .height(AppDimensions.SOURCE_CARD_HEIGHT)
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(AppRadius.CARD)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .scale({ x: this.isPressed ? 0.96 : 1, y: this.isPressed ? 0.96 : 1 })
    .opacity(this.isPressed ? 0.86 : 1)
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onCardClick) this.onCardClick()
    })
  }
}
