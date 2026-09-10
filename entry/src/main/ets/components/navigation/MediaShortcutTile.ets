import { AppMotion } from '../../ui/theme/AppMotion'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppSurface } from '../../ui/theme/AppSurface'

/** Lightweight home shortcut; media artwork retains the stronger visual weight. */
@Component
export struct MediaShortcutTile {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop iconKind: string = 'play'
  @Prop tileWidth: number = 128
  @Prop tileHeight: number = 80
  @State private isPressed: boolean = false
  onClickAction?: () => void

  build() {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(this.iconKind === 'folder' ? $r('sys.symbol.folder') :
        this.iconKind === 'plus' ? $r('sys.symbol.plus') : $r('sys.symbol.play_round_rectangle'))
        .fontSize(22)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.title)
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(AppTypography.CAPTION)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width(this.tileWidth)
    .height(this.tileHeight)
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .alignItems(HorizontalAlign.Start)
    .borderRadius(AppRadius.SMALL_BUTTON)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE_INTERACTIVE))
    .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
    .opacity(this.isPressed ? 0.86 : 1)
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.onClickAction) this.onClickAction()
    })
  }
}
