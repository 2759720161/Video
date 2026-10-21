import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { buildDetailSheetMaterial } from '../../utils/DetailMaterial'
import { IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

@Component
export struct CatVodHomeTitle {
  @Prop title: string = ''
  @Prop sites: CatNodeSite[] = []
  @Prop selectedKey: string = ''
  @Prop busy: boolean = true
  @Prop maxWidth: number = 200
  @Prop @Watch('onActiveChanged') isActive: boolean = true
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @State private showMenu: boolean = false
  onSelect: (key: string) => void = () => {}

  aboutToDisappear(): void { this.showMenu = false }
  private onActiveChanged(): void { if (!this.isActive) this.showMenu = false }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 9 }) {
        Text(this.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: Math.max(40, this.maxWidth - 52) })
        if (this.busy) {
          LoadingProgress().width(15).height(15).color($r('app.color.text_muted'))
        } else {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([$r('app.color.text_primary')])
        }
      }.padding({ left: 12, right: 12 })
    }.id('cat-home-title-menu').height(44).padding(0).borderRadius(22)
      .backgroundColor($r('app.color.titlebar_button_surface'))
      .enabled(this.isActive && !this.busy && this.sites.length > 0)
      .accessibilityText(this.title + '，' + this.getUIContext().getHostContext()!.resourceManager
        .getStringSync($r('app.string.cat_home_choose_source').id))
      .onClick(() => { this.showMenu = !this.showMenu })
      .bindMenu(this.showMenu, this.SourceMenu(), this.menuOptions())
  }

  @Builder
  private SourceMenu(): void {
    Menu() {
      ForEach(this.sites, (site: CatNodeSite) => {
        MenuItem(this.SourceRow(site))
          .selected(site.key === this.selectedKey)
          .selectIcon(false)
          .enabled(!this.busy)
          .onClick(() => { this.showMenu = false; this.onSelect(site.key) })
      }, (site: CatNodeSite) => site.key)
    }.width(260).borderRadius(28)
  }

  @Builder
  private SourceRow(site: CatNodeSite): void {
    Row({ space: 14 }) {
      Text(site.name).fontSize(17)
        .fontWeight(site.key === this.selectedKey ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(site.key === this.selectedKey ? $r('app.color.accent_blue') : $r('app.color.text_primary')).layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').constraintSize({ minHeight: 54 })
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }

  private menuOptions(): MenuOptions {
    const material = buildDetailSheetMaterial(this.materialThickness)
    const options: MenuOptions = {
      placement: Placement.BottomLeft, borderRadius: 28,
      backgroundColor: material === undefined ? $r('app.color.card_background') : Color.Transparent,
      onDisappear: () => { this.showMenu = false }
    }
    if (material !== undefined) options.systemMaterial = material
    return options
  }
}
