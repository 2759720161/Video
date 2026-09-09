import { promptAction } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaItem } from '../../core/media/MediaItem'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { PreferencesStore } from '../../store/PreferencesStore'
import { BrowserBreadcrumbItem } from '../../models/BrowserBreadcrumbItem'
import { buildTitleBarOptions, getContentMaxWidth, isTabletLayout,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { PageErrorState } from '../../components/common/PageErrorState'

@Entry
@Component
struct SourceBrowserPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
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
  @State private breadcrumbs: BrowserBreadcrumbItem[] = []
  @State private pressedItemKey: string = ''
  private loadGeneration: number = 0
  private searchGeneration: number = 0

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['parentId'] === 'string') this.parentId = (params['parentId'] as string).trim()
      if (typeof params['title'] === 'string' && (params['title'] as string).trim().length > 0) {
        this.title = (params['title'] as string).trim()
      }
      if (typeof params['breadcrumb'] === 'string') this.breadcrumb = (params['breadcrumb'] as string).trim()
      if (typeof params['breadcrumbJson'] === 'string') {
        this.breadcrumbs = this.decodeBreadcrumbs(params['breadcrumbJson'] as string)
      }
    }
    if (this.breadcrumbs.length === 0) this.breadcrumbs = this.legacyBreadcrumbs()
    void this.restoreViewMode()
    void this.loadItems()
  }

  build() {
    HdsNavigation() {
      Column() {
        this.BrowserToolbar()
        this.BreadcrumbBar()
        if (this.loading) {
          PageLoadingState({ title: '正在读取“' + this.title + '”', minHeight: 240 })
        } else if (this.errorText.length > 0) {
          PageErrorState({ title: '目录读取失败', message: this.errorText, onRetry: () => this.loadItems() })
        } else if (this.visibleItems().length === 0) {
          this.EmptyBrowserState()
        } else {
          Scroll() {
            if (this.gridMode) {
              Grid() {
                ForEach(this.visibleItems(), (item: MediaItem) => {
                  GridItem() { this.GridItemCard(item) }
                }, (item: MediaItem) => 'grid_' + item.sourceId + '_' + item.id)
              }.columnsTemplate(this.gridColumns()).columnsGap(10).rowsGap(10).width('100%')
            } else {
              Column({ space: 10 }) {
                ForEach(this.visibleItems(), (item: MediaItem) => { this.ItemCard(item) },
                  (item: MediaItem) => 'list_' + item.sourceId + '_' + item.id)
              }.width('100%')
            }
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
            .padding({ left: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
              right: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
              bottom: AppSpacing.SECTION })
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
        Blank().layoutWeight(1)
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(22).fontColor([$r('app.color.text_secondary')])
          .width(44).height(34)
          .onClick(() => this.openToolbarMenu())
      }.width('100%')
    }.width('100%').constraintSize({ maxWidth: getContentMaxWidth(this.screenWidthVp) || '100%' })
      .padding({ left: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
        right: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
        top: AppSpacing.SMALL, bottom: 4 })
      .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private BreadcrumbBar(): void {
    if (this.breadcrumbs.length > 0) {
      Scroll() {
        Row({ space: 5 }) {
          ForEach(this.breadcrumbs, (item: BrowserBreadcrumbItem, index: number) => {
            if (index > 0) {
              Text('›').fontSize(14).fontColor($r('app.color.text_hint'))
            }
            Text(item.title)
              .fontSize(index === this.breadcrumbs.length - 1 ? 13 : 12)
              .fontWeight(index === this.breadcrumbs.length - 1 ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(index === this.breadcrumbs.length - 1 ? $r('app.color.text_primary') : $r('app.color.accent_blue'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                if (index < this.breadcrumbs.length - 1) this.openBreadcrumb(item)
              })
          }, (item: BrowserBreadcrumbItem) => 'breadcrumb_' + item.id + '_' + item.title)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').padding({ left: AppSpacing.PAGE, right: AppSpacing.PAGE, bottom: AppSpacing.SMALL })
    }
  }

  @Builder
  private EmptyBrowserState(): void {
    PageEmptyState({
      icon: this.searchText.length > 0 ? $r('sys.symbol.magnifyingglass') : $r('sys.symbol.folder'),
      title: this.searchText.length > 0 ? '没有匹配的媒体' : '此目录暂无媒体',
      message: this.searchText.length > 0 ? '尝试更换关键词或清空搜索条件' : '当前来源还没有可显示的内容'
    })
  }

  @Builder
  private ItemCard(item: MediaItem): void {
    Row({ space: 12 }) {
      this.ItemThumbnail(item, 64, 48)
      Column({ space: 4 }) {
        Text(item.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        if (item.subtitle.length > 0) Text(item.subtitle).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.text_secondary')])
    }.width('100%').padding(14).borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .scale({ x: this.itemCardScale('list_' + item.id), y: this.itemCardScale('list_' + item.id) })
      .opacity(this.itemCardOpacity('list_' + item.id))
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => this.handleItemTouch('list_' + item.id, event))
      .onClick(() => this.openItem(item))
  }

  @Builder
  private GridItemCard(item: MediaItem): void {
    Column({ space: 6 }) {
      this.ItemThumbnail(item, '100%', item.browsable ? 72 : this.gridVideoThumbnailHeight())
      Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (item.subtitle.length > 0) Text(item.subtitle).fontSize(11).fontColor($r('app.color.text_secondary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }.width('100%').height(item.browsable ? 150 : this.gridVideoThumbnailHeight() + 92)
      .padding(12).alignItems(HorizontalAlign.Start)
      .borderRadius(12).backgroundColor($r('app.color.card_background'))
      .scale({ x: this.itemCardScale('grid_' + item.id), y: this.itemCardScale('grid_' + item.id) })
      .opacity(this.itemCardOpacity('grid_' + item.id))
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => this.handleItemTouch('grid_' + item.id, event))
      .onClick(() => this.openItem(item))
  }

  @Builder
  private ItemThumbnail(item: MediaItem, width: Length, height: Length): void {
    if (!item.browsable && item.poster.length > 0) {
      Image(item.poster).width(width).height(height).objectFit(ImageFit.Cover)
        .borderRadius(9).draggable(false)
    } else {
      Column() {
        SymbolGlyph(item.browsable ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle'))
          .fontSize(26).fontColor([$r('app.color.accent_blue')])
      }.width(width).height(height).justifyContent(FlexAlign.Center)
        .borderRadius(9).backgroundColor($r('app.color.button_ghost_bg'))
    }
  }

  private async loadItems(): Promise<void> {
    const generation = ++this.loadGeneration
    // 目录刷新开始后，任何尚未完成的搜索都不能再覆盖刷新结果。
    this.searchGeneration++
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
      // 浏览型来源至少支持当前目录本地过滤；具备 SEARCH 能力时，searchItems
      // 会改用 Provider 的全局搜索结果。
      this.searchSupported = descriptor.hasCapability(ProviderCapability.BROWSE)
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
    const generation = ++this.searchGeneration
    this.errorText = ''
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      const descriptor = source === null ? null : ProviderCatalog.get(source.providerType)
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (generation !== this.searchGeneration) return
      if (provider !== null && descriptor !== null && descriptor.hasCapability(ProviderCapability.SEARCH)) {
        const results = await provider.search(keyword)
        if (generation !== this.searchGeneration) return
        this.items = results
      } else if (provider === null || descriptor === null) {
        throw new Error('媒体源不可用')
      }
      // 不具备全局 SEARCH 的 Provider 保留当前目录数据，visibleItems 会按
      // searchText 做本地标题/副标题过滤，避免伪造远端搜索能力。
    } catch (err) {
      if (generation !== this.searchGeneration) return
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
      if (left.browsable !== right.browsable) return left.browsable ? -1 : 1
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
            breadcrumb: this.breadcrumbTextForChild(item.title),
            breadcrumbJson: this.encodeBreadcrumbs(this.breadcrumbsForChild(item))
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

  private async restoreViewMode(): Promise<void> {
    if (this.sourceId.length === 0) return
    const value = await PreferencesStore.getInstance().getString('sourceBrowserViewMode_' + this.sourceId, 'list')
    this.gridMode = value === 'grid'
  }

  private persistViewMode(): void {
    if (this.sourceId.length === 0) return
    void PreferencesStore.getInstance().setString('sourceBrowserViewMode_' + this.sourceId,
      this.gridMode ? 'grid' : 'list')
  }

  private itemCardScale(itemKey: string): number {
    return this.pressedItemKey === itemKey ? 0.96 : 1
  }

  private itemCardOpacity(itemKey: string): number {
    return this.pressedItemKey === itemKey ? 0.86 : 1
  }

  private handleItemTouch(itemKey: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedItemKey = itemKey
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.pressedItemKey === itemKey) this.pressedItemKey = ''
    }
  }

  private openToolbarMenu(): void {
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: '浏览选项',
        buttons: [
          { text: this.gridMode ? '切换列表视图' : '切换网格视图', color: $r('app.color.text_primary') },
          { text: '刷新当前目录', color: $r('app.color.text_primary') }
        ]
      }, (err: BusinessError, result: promptAction.ActionMenuSuccessResponse) => {
        if (err !== undefined) return
        if (result.index === 0) {
          this.gridMode = !this.gridMode
          this.persistViewMode()
        } else if (result.index === 1) {
          void this.loadItems()
        }
      })
    } catch (_) {
      // 工具菜单失败不影响列表浏览。
    }
  }

  private gridColumns(): string {
    if (this.screenWidthVp >= 1000) return '1fr 1fr 1fr 1fr'
    if (isTabletLayout(this.screenWidthVp)) return '1fr 1fr 1fr'
    return '1fr 1fr'
  }

  /** 让视频缩略图在不同列数下保持接近 16:9，文件夹仍使用紧凑卡片。 */
  private gridVideoThumbnailHeight(): number {
    if (this.screenWidthVp >= 1000) return 120
    if (isTabletLayout(this.screenWidthVp)) return 108
    if (this.screenWidthVp >= 410) return 92
    return 84
  }

  private legacyBreadcrumbs(): BrowserBreadcrumbItem[] {
    const result: BrowserBreadcrumbItem[] = []
    if (this.breadcrumb.length === 0) {
      if (this.title.length > 0) result.push(new BrowserBreadcrumbItem(this.parentId, this.title))
      return result
    }
    const parts = this.breadcrumb.split('/')
    for (let i = 0; i < parts.length; i++) {
      const value = parts[i].trim()
      if (value.length > 0) result.push(new BrowserBreadcrumbItem(i === parts.length - 1 ? this.parentId : '', value))
    }
    return result
  }

  private decodeBreadcrumbs(raw: string): BrowserBreadcrumbItem[] {
    try {
      const parsed = JSON.parse(raw) as Object
      if (!Array.isArray(parsed)) return []
      const result: BrowserBreadcrumbItem[] = []
      const values = parsed as Object[]
      for (let i = 0; i < values.length; i++) {
        const value = values[i]
        if (value === null || typeof value !== 'object' || Array.isArray(value)) continue
        const entry = value as Record<string, Object>
        const id = typeof entry['id'] === 'string' ? entry['id'] as string : ''
        const title = typeof entry['title'] === 'string' ? entry['title'] as string : ''
        if (title.trim().length > 0) result.push(new BrowserBreadcrumbItem(id, title))
      }
      return result
    } catch (_) {
      return []
    }
  }

  private breadcrumbsForChild(item: MediaItem): BrowserBreadcrumbItem[] {
    const result: BrowserBreadcrumbItem[] = []
    for (let i = 0; i < this.breadcrumbs.length; i++) {
      result.push(new BrowserBreadcrumbItem(this.breadcrumbs[i].id, this.breadcrumbs[i].title))
    }
    result.push(new BrowserBreadcrumbItem(item.id, item.title))
    return result
  }

  private encodeBreadcrumbs(items: BrowserBreadcrumbItem[]): string {
    const result: BrowserBreadcrumbItem[] = []
    for (let i = 0; i < items.length; i++) {
      result.push(new BrowserBreadcrumbItem(items[i].id, items[i].title))
    }
    return JSON.stringify(result)
  }

  private breadcrumbTextForChild(title: string): string {
    const base = this.breadcrumbs.map((item: BrowserBreadcrumbItem) => item.title).join(' / ')
    return base.length > 0 ? base + ' / ' + title : title
  }

  private openBreadcrumb(item: BrowserBreadcrumbItem): void {
    const index = this.breadcrumbs.indexOf(item)
    const path = index >= 0 ? this.breadcrumbs.slice(0, index + 1) : [item]
    void this.getUIContext().getRouter().pushUrl({
      url: 'pages/sources/SourceBrowserPage',
      params: {
        sourceId: this.sourceId,
        parentId: item.id,
        title: item.title,
        breadcrumbJson: this.encodeBreadcrumbs(path)
      }
    })
  }
}
