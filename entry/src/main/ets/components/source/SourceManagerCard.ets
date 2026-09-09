import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { ProviderIcon } from './ProviderIcon'
import { SourceActionKind, SourceActionSheet } from './SourceActionSheet'
import { SourceStatusBadge } from './SourceStatusBadge'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'

/** 来源管理页单张来源卡，只保留浏览主入口和低频操作菜单。 */
@Component
export struct SourceManagerCard {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop providerLabel: string = ''
  @Prop statusText: string = ''
  @Prop isBuiltIn: boolean = false
  @Prop canBrowse: boolean = false
  @Prop isEnabled: boolean = true
  @State private isPressed: boolean = false
  onBrowse?: () => void
  onAction?: (action: SourceActionKind) => void

  build() {
    Row({ space: AppSpacing.CARD_CONTENT }) {
      ProviderIcon({ providerType: this.source.providerType })
      Column({ space: AppSpacing.TINY }) {
        Text(this.source.name)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: AppSpacing.SMALL }) {
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
        SourceActionSheet({ title: this.source.name, isEnabled: this.isEnabled,
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
    .padding({ left: AppSpacing.CARD_CONTENT, right: AppSpacing.SMALL,
      top: AppSpacing.SMALL, bottom: AppSpacing.SMALL })
    .borderRadius(AppRadius.CARD)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .opacity(this.isEnabled || this.isBuiltIn ? (this.isPressed ? 0.86 : 1) : 0.58)
    .scale({ x: this.isPressed ? 0.96 : 1, y: this.isPressed ? 0.96 : 1 })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.canBrowse && (this.isEnabled || this.isBuiltIn) && this.onBrowse) this.onBrowse()
    })
  }
}
