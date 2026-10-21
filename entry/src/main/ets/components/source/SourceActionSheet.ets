import { buildDetailSheetMaterial } from '../../utils/DetailMaterial'
import { IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

export enum SourceActionKind {
  EDIT = 'edit',
  TEST = 'test',
  TOGGLE = 'toggle',
  REORDER = 'reorder',
  DELETE = 'delete'
}

/** 来源卡片的低频操作入口，避免把危险操作长期放在卡片一级。 */
@Component
export struct SourceActionSheet {
  @Prop title: string = ''
  @Prop isEnabled: boolean = true
  @Prop showEdit: boolean = true
  @Prop userToggleable: boolean = true
  @Prop userReorderable: boolean = true
  @Prop userRemovable: boolean = true
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @State private showMenu: boolean = false
  onAction?: (action: SourceActionKind) => void

  build() {
    SymbolGlyph($r('sys.symbol.more'))
      .fontSize(22)
      .fontColor([$r('app.color.text_secondary')])
      .width(44)
      .height(44)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => { this.showMenu = !this.showMenu })
      .bindMenu(this.showMenu, this.actionMenuItems(), this.actionMenuOptions())
  }

  private menuItem(value: string, action: SourceActionKind): MenuElement {
    return { value: value, action: () => {
      this.showMenu = false
      if (this.onAction) this.onAction(action)
    } }
  }

  private actionMenuItems(): MenuElement[] {
    const items: MenuElement[] = []
    if (this.showEdit) items.push(this.menuItem('编辑', SourceActionKind.EDIT))
    items.push(this.menuItem('测试连接', SourceActionKind.TEST))
    if (this.userToggleable) items.push(this.menuItem(this.isEnabled ? '停用媒体源' : '启用媒体源', SourceActionKind.TOGGLE))
    if (this.userReorderable) items.push(this.menuItem('调整顺序', SourceActionKind.REORDER))
    if (this.userRemovable) items.push(this.menuItem('删除媒体源', SourceActionKind.DELETE))
    return items
  }

  private actionMenuOptions(): MenuOptions {
    const material = buildDetailSheetMaterial(this.materialThickness)
    const options: MenuOptions = {
      placement: Placement.BottomRight,
      borderRadius: 22,
      backgroundColor: material === undefined ? $r('app.color.card_background') : Color.Transparent,
      onDisappear: () => { this.showMenu = false }
    }
    if (material !== undefined) options.systemMaterial = material
    return options
  }
}
