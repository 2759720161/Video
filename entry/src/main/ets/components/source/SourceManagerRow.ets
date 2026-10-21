import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { ProviderIcon } from './ProviderIcon'
import { SourceActionKind, SourceActionSheet } from './SourceActionSheet'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppMotion } from '../../ui/theme/AppMotion'

/** Source management row shared by normal and grouped management views. */
@Component
export struct SourceManagerRow {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop providerLabel: string = ''
  @Prop summaryText: string = ''
  @Prop isBuiltIn: boolean = false
  @Prop isSelected: boolean = false
  @Prop canSelect: boolean = false
  @Prop isEnabled: boolean = true
  @Prop canEdit: boolean = true
  @Prop userToggleable: boolean = true
  @Prop userReorderable: boolean = true
  @Prop userRemovable: boolean = true
  @State private isPressed: boolean = false
  onSelect?: () => void
  onAction?: (action: SourceActionKind) => void

  private customIcon(): string {
    if (this.source.providerType !== 'catnode') return ''
    try {
      const value = JSON.parse(this.source.configJson) as Record<string, Object>
      const icon = value['iconUri']
      return typeof icon === 'string' && icon.startsWith('file://') ? icon : ''
    } catch (_) { return '' }
  }

  build() {
    // 所有信息参与线性布局，不能用叠层定位状态或操作入口。
    Row({ space: 12 }) {
      Row() {
        ProviderIcon({ providerType: this.source.providerType, iconSize: 25, imageUri: this.customIcon() })
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .borderRadius(24)
      .backgroundColor(this.isSelected ? $r('app.color.accent_blue_light') : $r('app.color.button_ghost_bg'))
      .flexShrink(0)

      Column({ space: 6 }) {
          Text(this.source.name)
            .fontSize(AppTypography.FEATURE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.summaryText.length > 0 ? this.summaryText : this.providerLabel)
            .fontSize(AppTypography.BODY)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        if (!this.isBuiltIn) {
          SourceActionSheet({ title: this.source.name, isEnabled: this.isEnabled, showEdit: this.canEdit,
            userToggleable: this.userToggleable, userReorderable: this.userReorderable,
            userRemovable: this.userRemovable,
            onAction: (action: SourceActionKind) => {
              if (this.onAction) this.onAction(action)
            } })
        } else {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
            .width(44)
            .height(44)
        }
      }.width(44).height(44).flexShrink(0)
    }
    .width('100%')
    .constraintSize({ minHeight: 92 })
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(22)
    .border({ width: this.isSelected ? 2 : 0.5,
      color: this.isSelected ? $r('app.color.accent_blue') : $r('app.color.card_specular_border') })
    .shadow({ radius: this.isSelected ? 16 : 10,
      color: this.isSelected ? $r('app.color.shadow_button_info') : $r('app.color.shadow_surface'), offsetY: 5 })
    .opacity(this.isEnabled || this.isBuiltIn ? (this.isPressed ? 0.86 : 1) : 0.58)
    .scale({ x: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1, y: this.isPressed ? AppMotion.NAVIGATION_PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.TOUCH_FEEDBACK_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.isPressed = true
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isPressed = false
    })
    .onClick(() => {
      if (this.canSelect && this.onSelect) this.onSelect()
    })
  }
}
