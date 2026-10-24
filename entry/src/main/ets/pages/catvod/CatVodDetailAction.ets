import { FrameCallback } from '@kit.ArkUI'
import { DetailToggleButtonMaterialModifier } from '../../utils/DetailMaterial'
import { AppSurface } from '../../ui/theme/AppSurface'
import { IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

/** Native material carrier for both actions and selected episode capsules. */
@Component
export struct CatVodDetailAction {
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) thickness: string = IMMERSIVE_STYLE_DEFAULT
  @Prop label: string = ''
  @Prop accessibilityLabel: string = ''
  @Prop icon: Resource | undefined = undefined
  @Prop @Watch('syncSelection') selected: boolean = false
  @Prop actionEnabled: boolean = true
  @Prop busy: boolean = false
  @Prop leftAligned: boolean = false
  @Prop scrollOverflow: boolean = false
  @State private toggled: boolean = false
  @State private labelVisible: boolean = false
  private alive: boolean = false
  private pending: boolean = false
  private resetTicket: number = 0
  onAction: () => void = () => {}

  aboutToAppear(): void { this.alive = true; this.pending = false; this.resetTicket++; this.syncSelection() }
  aboutToDisappear(): void { this.alive = false; this.pending = false; this.resetTicket++ }
  private syncSelection(): void { this.toggled = this.selected }
  private changed(): void {
    if (!this.alive || this.pending || !this.actionEnabled || this.busy) return
    this.pending = true
    const ticket = ++this.resetTicket
    this.getUIContext().postFrameCallback(new CatVodDetailActionReset(() => {
      if (!this.alive || ticket !== this.resetTicket) return
      this.pending = false; this.syncSelection()
    }))
    this.onAction()
  }

  build() {
    Toggle({ type: ToggleType.Button, isOn: $$this.toggled }) {
      Row({ space: 8 }) {
        if (this.busy) {
          LoadingProgress().width(20).height(20).color($r('app.color.accent_blue'))
        } else if (this.icon !== undefined) {
          SymbolGlyph(this.icon).fontSize(21).fontColor([this.selected ?
            $r('app.color.accent_blue') : $r('app.color.text_primary')]).accessibilityLevel('no')
        }
        if (this.label.length > 0) {
          Text(this.label).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.selected ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: this.scrollOverflow ? TextOverflow.MARQUEE : TextOverflow.Ellipsis })
            .marqueeOptions({ start: this.scrollOverflow && this.labelVisible, step: 0.6, loop: -1,
              fromStart: true, delay: 1000, fadeout: true, marqueeStartPolicy: MarqueeStartPolicy.DEFAULT })
            .layoutWeight(this.leftAligned ? 1 : 0)
            .constraintSize({ maxWidth: this.icon === undefined ? '100%' : '65%' })
            .textAlign(this.leftAligned ? TextAlign.Start : TextAlign.Center)
            .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number) => {
              this.labelVisible = visible && ratio > 0
            })
        }
      }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
    }.width('100%').height(48).padding({ left: 14, right: 14 }).borderRadius(24)
      .backgroundColor($r('app.color.cat_detail_control_surface'))
      .selectedColor($r('app.color.cat_detail_control_surface'))
      .border({ width: 0.5, color: AppSurface.borderColor() })
      .attributeModifier(new DetailToggleButtonMaterialModifier(this.thickness))
      .enabled(this.actionEnabled && !this.busy)
      .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.label)
      .onChange(() => this.changed())
  }
}

class CatVodDetailActionReset extends FrameCallback {
  private reset: () => void
  constructor(reset: () => void) { super(); this.reset = reset }
  onIdle(): void { this.reset() }
}
