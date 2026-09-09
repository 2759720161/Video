import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaItem } from '../../core/media/MediaItem'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct SourceBrowserPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private sourceId: string = ''
  @State private parentId: string = ''
  @State private title: string = '媒体源'
  @State private items: MediaItem[] = []
  @State private loading: boolean = true
  @State private errorText: string = ''
  @State private searchText: string = ''
  @State private searchSupported: boolean = false
  @State private gridMode: boolean = false
  @State private sortDescending: boolean = false
  @State private breadcrumb: string = ''
  private loadGeneration: number = 0

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['parentId'] === 'string') this.parentId = (params['parentId'] as string).trim()
      if (typeof params['title'] === 'string' && (params['title'] as string).trim().length > 0) {
        this.title = (params['title'] as string).trim()
      }
      if (typeof params['breadcrumb'] === 'string') this.breadcrumb = (params['breadcrumb'] as string).trim()
    }
    void this.loadItems()
  }

  build() {
    HdsNavigation() {
      Column() {
        this.BrowserToolbar()
        if (this.breadcrumb.length > 0) {
          Text(this.breadcrumb).fontSize(12).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').padding({ left: 16, right: 16, bottom: 8 })
        }
        if (this.loading) {
          LoadingProgress().width(36).height(36).margin({ top: 60 })
        } else if (this.errorText.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorText).fontSize(15).fontColor($r('app.color.text_secondary'))
            Button('重试').onClick(() => this.loadItems())
          }.width('100%').padding(32).alignItems(HorizontalAlign.Center)
        } else if (this.visibleItems().length === 0) {
          Text(this.searchText.length > 0 ? '没有匹配的媒体' : '此目录暂无媒体')
            .fontSize(15).fontColor($r('app.color.text_secondary')).margin({ top: 60 })
        } else {
          Scroll() {
            if (this.gridMode) {
              Grid() {
                ForEach(this.visibleItems(), (item: MediaItem) => {
                  GridItem() { this.GridItemCard(item) }
                }, (item: MediaItem) => 'grid_' + item.sourceId + '_' + item.id)
              }.columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10).width('100%')
            } else {
              Column({ space: 10 }) {
                ForEach(this.visibleItems(), (item: MediaItem) => { this.ItemCard(item) },
                  (item: MediaItem) => 'list_' + item.sourceId + '_' + item.id)
              }.width('100%')
            }
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).padding(16)
        }
      }.width('100%').height('100%')
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.title, this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private BrowserToolbar(): void {
    Column({ space: 8 }) {
      if (this.searchSupported) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索当前来源', text: this.searchText })
            .layoutWeight(1).height(42).fontSize(14).backgroundColor($r('app.color.button_ghost_bg'))
            .borderRadius(12).onChange((value: string) => this.searchText = value)
          Button('搜索').height(42).fontSize(13).onClick(() => this.searchItems())
        }.width('100%')
      }
      Row({ space: 8 }) {
        Button(this.sortDescending ? '名称 ↓' : '名称 ↑').height(34).fontSize(12)
          .backgroundColor(Color.Transparent).onClick(() => this.sortDescending = !this.sortDescending)
        Button(this.gridMode ? '列表' : '网格').height(34).fontSize(12)
          .backgroundColor(Color.Transparent).onClick(() => this.gridMode = !this.gridMode)
        Button('刷新').height(34).fontSize(12).backgroundColor(Color.Transparent)
          .onClick(() => this.loadItems())
      }.width('100%')
    }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 4 })
  }

  @Builder
  private ItemCard(item: MediaItem): void {
    Row({ space: 12 }) {
      SymbolGlyph(item.browsable ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle'))
        .fontSize(26).fontColor([$r('app.color.accent_blue')])
      Column({ space: 4 }) {
        Text(item.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        if (item.subtitle.length > 0) Text(item.subtitle).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.text_secondary')])
    }.width('100%').padding(14).borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .onClick(() => this.openItem(item))
  }

  @Builder
  private GridItemCard(item: MediaItem): void {
    Column({ space: 6 }) {
      SymbolGlyph(item.browsable ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle'))
        .fontSize(28).fontColor([$r('app.color.accent_blue')])
      Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (item.subtitle.length > 0) Text(item.subtitle).fontSize(11).fontColor($r('app.color.text_secondary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }.width('100%').height(104).padding(12).alignItems(HorizontalAlign.Start)
      .borderRadius(12).backgroundColor($r('app.color.card_background'))
      .onClick(() => this.openItem(item))
  }

  private async loadItems(): Promise<void> {
    const generation = ++this.loadGeneration
    this.loading = true
    this.errorText = ''
    try {
      if (this.sourceId.length === 0) throw new Error('媒体源参数无效')
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (generation !== this.loadGeneration) return
      if (provider === null) throw new Error('媒体源不可用或已停用')
      const source = await MediaSourceStore.getById(this.sourceId)
      if (source === null) throw new Error('媒体源不可用或已删除')
      const descriptor = ProviderCatalog.get(source.providerType)
      if (descriptor === null || !descriptor.hasCapability(ProviderCapability.BROWSE)) {
        throw new Error('该媒体源不支持目录浏览')
      }
      this.searchSupported = descriptor.hasCapability(ProviderCapability.SEARCH)
      const items = await provider.getChildren(this.parentId)
      if (generation !== this.loadGeneration) return
      this.items = items
    } catch (err) {
      if (generation !== this.loadGeneration) return
      this.items = []
      this.errorText = err instanceof Error ? err.message : '媒体目录读取失败'
    } finally {
      if (generation === this.loadGeneration) this.loading = false
    }
  }

  private async searchItems(): Promise<void> {
    const keyword = this.searchText.trim()
    if (keyword.length === 0) {
      await this.loadItems()
      return
    }
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      const descriptor = source === null ? null : ProviderCatalog.get(source.providerType)
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (provider !== null && descriptor !== null && descriptor.hasCapability(ProviderCapability.SEARCH)) {
        this.items = await provider.search(keyword)
      }
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '搜索失败'
    }
  }

  private visibleItems(): MediaItem[] {
    const keyword = this.searchText.trim().toLowerCase()
    const filtered: MediaItem[] = []
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i]
      if (keyword.length > 0 && item.title.toLowerCase().indexOf(keyword) < 0 &&
        item.subtitle.toLowerCase().indexOf(keyword) < 0) continue
      filtered.push(item)
    }
    filtered.sort((left: MediaItem, right: MediaItem) => {
      const compare = left.title.localeCompare(right.title)
      return this.sortDescending ? -compare : compare
    })
    return filtered
  }

  private async openItem(item: MediaItem): Promise<void> {
    try {
      if (this.sourceId.length === 0) throw new Error('媒体源参数无效')
      if (item.browsable) {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/sources/SourceBrowserPage', params: {
            sourceId: this.sourceId, parentId: item.id, title: item.title,
            breadcrumb: this.breadcrumb.length > 0 ? this.breadcrumb + ' / ' + item.title : item.title
          }
        })
        return
      }
      if (!item.playable) {
        promptAction.showToast({ message: '该文件类型暂不支持播放' })
        return
      }
      const playable = this.items.filter((value: MediaItem) => value.playable)
      await ProviderPlaybackLauncher.open(this.getUIContext(), item, playable)
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法打开媒体' })
    }
  }
}
