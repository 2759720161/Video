import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'

/** 来源很多时，允许搜索并清楚标识当前选择。 */
@Component
export struct CatNodeSiteSheet {
  @Prop sites: CatNodeSite[] = []
  @Prop selectedKey: string = ''
  @State private query: string = ''
  onSelect: (key: string) => void = () => {}

  private filteredSites(): CatNodeSite[] {
    const keyword = this.query.trim().toLocaleLowerCase()
    return keyword.length === 0 ? this.sites : this.sites.filter((site: CatNodeSite) =>
      site.name.toLocaleLowerCase().includes(keyword) || site.key.toLocaleLowerCase().includes(keyword))
  }

  build() {
    Column({ space: 16 }) {
      Search({ value: this.query, placeholder: $r('app.string.cat_home_find_source') })
        .height(46).width('100%').backgroundColor($r('app.color.cat_subscription_field'))
        .onChange((value: string) => { this.query = value })
      if (this.filteredSites().length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(30)
            .fontColor([$r('app.color.text_hint')])
          Text($r('app.string.cat_home_no_source')).fontSize(15).fontColor($r('app.color.text_muted'))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.filteredSites(), (site: CatNodeSite) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Text(site.name).fontSize(16)
                    .fontWeight(site.key === this.selectedKey ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(site.key === this.selectedKey ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.Start)
                  if (site.key === this.selectedKey) {
                    SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('app.color.accent_blue')])
                  }
                }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              }.width('100%').borderRadius(16)
                .backgroundColor(site.key === this.selectedKey ? $r('app.color.cat_home_selected_surface') : Color.Transparent)
                .accessibilityText(site.name + (site.key === this.selectedKey ?
                  this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.cat_home_current').id) : ''))
                .onClick(() => this.onSelect(site.key))
            }
          }, (site: CatNodeSite) => site.key)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }
}
