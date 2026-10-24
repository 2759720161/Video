import { curves, FrameCallback } from '@kit.ArkUI'
import { CategoryTabMaterialModifier } from '../../utils/DetailMaterial'
import { IMMERSIVE_STYLE_DEFAULT } from '../../utils/HdsPageStyle'

/** A controlled single-choice tab; tapping the active item must not deselect it. */
@Component
export struct CatVodCategoryTab {
  @Prop name: string = ''
  @Prop @Watch('syncSelection') selected: boolean = false
  @Prop @Watch('syncSelection') selectionEnabled: boolean = true
  @Prop materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @State private toggled: boolean = false
  private alive: boolean = false
  private resetPending: boolean = false
  private resetTicket: number = 0
  onSelect: () => void = () => {}

  aboutToAppear(): void { this.alive = true; this.syncSelection() }
  aboutToDisappear(): void { this.alive = false; this.resetTicket++; this.resetPending = false }

  private syncSelection(): void { this.toggled = this.selected }

  private selectionChanged(value: boolean): void {
    if (!this.alive || this.resetPending) return
    this.resetPending = true
    const ticket = ++this.resetTicket
    // Let native two-way state render before restoring the parent's single-choice state.
    this.getUIContext().postFrameCallback(new CatVodCategoryTabReset(() => {
      if (!this.alive || ticket !== this.resetTicket) return
      this.resetPending = false
      this.syncSelection()
    }))
    if (this.selectionEnabled && !this.selected && value) this.onSelect()
  }

  build() {
    Column() {
      Toggle({ type: ToggleType.Button, isOn: $$this.toggled }) {
        Text(this.name).fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selected ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
          .animation({ duration: 250, curve: curves.springMotion() })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center).hitTestBehavior(HitTestMode.None)
      }.height(30).constraintSize({ minWidth: 52 }).padding({ left: 12, right: 12 }).borderRadius(15)
        .clip(false)
        .attributeModifier(new CategoryTabMaterialModifier(this.materialThickness, this.selected,
          $r('app.color.cat_category_surface'), this.selectionEnabled))
        .responseRegion({ x: 0, y: -7, width: '100%', height: 44 })
        .accessibilityText(this.name)
        .onChange((value: boolean) => this.selectionChanged(value))
    }.height(44).justifyContent(FlexAlign.Center).clip(false)
  }
}
class CatVodCategoryTabReset extends FrameCallback {
  private restore: () => void
  constructor(restore: () => void) { super(); this.restore = restore }
  onFrame(): void { this.restore() }
}
