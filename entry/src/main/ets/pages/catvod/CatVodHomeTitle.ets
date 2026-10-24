import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { SourceMenuEntry, SourceSelectionMenu } from '../../components/common/SourceSelectionMenu'
import { buildSourceSelectionMenuOptions } from '../../utils/SourceSelectionMenuStyle'
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
  onRefresh: () => void = () => {}

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
    SourceSelectionMenu({ entries: this.menuEntries(), selectedKey: this.selectedKey, disabled: this.busy })
  }

  private menuEntries(): SourceMenuEntry[] {
    const entries = this.sites.map((site: CatNodeSite): SourceMenuEntry => ({
      key: site.key, value: site.name, action: () => { this.showMenu = false; this.onSelect(site.key) }
    }))
    entries.push({ key: '/refresh-home', value: $r('app.string.cat_home_refresh'),
      action: () => { this.showMenu = false; this.onRefresh() } })
    return entries
  }

  private menuOptions(): MenuOptions {
    return buildSourceSelectionMenuOptions(this.materialThickness, Placement.BottomLeft, () => { this.showMenu = false })
  }
}
