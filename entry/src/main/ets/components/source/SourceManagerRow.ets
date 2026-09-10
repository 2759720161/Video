import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { ProviderIcon } from './ProviderIcon'
import { SourceActionKind, SourceActionSheet } from './SourceActionSheet'
import { SourceStatusBadge } from './SourceStatusBadge'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppMotion } from '../../ui/theme/AppMotion'

/** Source management row shared by normal and grouped management views. */
@Component
export struct SourceManagerRow {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop providerLabel: string = ''
  @Prop statusText: string = ''
  @Prop isBuiltIn: boolean = false
  @Prop canBrowse: boolean = false
  @Prop isEnabled: boolean = true
  @Prop canEdit: boolean = true
  @Prop userToggleable: boolean = true
  @Prop userReorderable: boolean = true
  @Prop userRemovable: boolean = true
  @Prop showDivider: boolean = true
  @State private isPressed: boolean = false
  onBrowse?: () => void
  onAction?: (action: SourceActionKind) => void

  build() {
    Row({ space: AppSpacing.MD }) {
      ProviderIcon({ providerType: this.source.providerType })
      Column({ space: AppSpacing.XS }) {
        Text(this.source.name)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: AppSpacing.SM }) {
          Text(this.providerLabel)
            .fontSize(AppTypography.CAPTION)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SourceStatusBadge({ text: this.statusText })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (!this.isBuiltIn) {
        SourceActionSheet({ title: this.source.name, isEnabled: this.isEnabled, showEdit: this.canEdit,
          userToggleable: this.userToggleable, userReorderable: this.userReorderable,
          userRemovable: this.userRemovable,
          onAction: (action: SourceActionKind) => {
            if (this.onAction) this.onAction(action)
          } })
      } else {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height(72)
    .padding({ left: AppSpacing.MD, right: AppSpacing.SM,
      top: AppSpacing.SM, bottom: AppSpacing.SM })
    .border({ width: { bottom: this.showDivider ? 0.5 : 0 }, color: $r('app.color.divider_color') })
    .opacity(this.isEnabled || this.isBuiltIn ? (this.isPressed ? 0.86 : 1) : 0.58)
    .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.canBrowse && (this.isEnabled || this.isBuiltIn) && this.onBrowse) this.onBrowse()
    })
  }
}
