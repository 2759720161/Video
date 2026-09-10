import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationIconOptions, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyItem, EmbyServerConfig } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { EmbySourceConfigCodec } from '../../providers/emby/EmbySourceConfig'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { PreferencesStore } from '../../store/PreferencesStore'
import { buildImmersiveTitleBarStyle, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL,
  getTopSpacerHeight, getContentMaxWidth, isTabletLayout } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { InlineLoadingState } from '../../components/common/InlineLoadingState'
import { ContinueWatchingCard } from '../../components/media/ContinueWatchingCard'
import { MediaPosterCard } from '../../components/media/MediaPosterCard'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { MediaProgressBar } from '../../components/media/MediaProgressBar'

const EMBY_HOME_CACHE_KEY_PREFIX: string = 'embyHomeCacheV1_'

class EmbyHomeSection {
  id: string = ''
  title: string = ''
  collectionType: string = ''
  items: EmbyItem[] = []
}

class EmbyHomeCachePayload {
  timestamp: number = 0
  libraries: EmbyItem[] = []
  resumeItems: EmbyItem[] = []
  latestItems: EmbyItem[] = []
  sections: EmbyHomeSection[] = []
}

@Entry
@Component
struct EmbyLibraryPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private title: string = 'Emby'
  @State private sourceId: string = ''
  @State private pendingItemId: string = ''
  @State private parentId: string = ''
  @State private latestOnly: boolean = false
  @State private libraryRoot: boolean = false
  @State private collectionType: string = ''
  @State private config: EmbyServerConfig | null = null
  @State private provider: EmbyProvider | null = null
  @State private items: EmbyItem[] = []
  @State private resumeItems: EmbyItem[] = []
  @State private latestItems: EmbyItem[] = []
  @State private homeSections: EmbyHomeSection[] = []
  @State private loading: boolean = true
  @State private errorText: string = ''
  @State private searchText: string = ''
  @State private showSearch: boolean = false
  @State private globalSearchItems: EmbyItem[] = []
  @State private searchLoading: boolean = false
  @State private selectedFilter: string = '全部'
  @State private resumeOnly: boolean = false
  @State private pageWidth: number = 360
  private scroller: Scroller = new Scroller()
  private filters: string[] = ['全部', '电影', '剧集', '文件夹']
  private loadGeneration: number = 0
  private searchGeneration: number = 0
  private searchTimer: number = -1

  aboutToAppear(): void {
    const rawParams = this.getUIContext().getRouter().getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      if (typeof params['parentId'] === 'string') this.parentId = (params['parentId'] as string).trim()
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['itemId'] === 'string') this.pendingItemId = (params['itemId'] as string).trim()
      if (typeof params['title'] === 'string' && (params['title'] as string).trim().length > 0) {
        this.title = (params['title'] as string).trim()
      }
      if (params['view'] === 'latest') this.latestOnly = true
      if (params['view'] === 'resume') this.resumeOnly = true
      if (params['libraryRoot'] === true || params['libraryRoot'] === 'true') this.libraryRoot = true
      if (typeof params['collectionType'] === 'string') {
        this.collectionType = (params['collectionType'] as string).trim()
      }
    }
    this.loadItems()
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.isHome() && this.featuredItems().length > 0 && this.heroImageUrl(this.featuredItems()[0], 1000).length > 0) {
        Image(this.heroImageUrl(this.featuredItems()[0], 1000))
          .width('100%')
          .height(560)
          .objectFit(ImageFit.Cover)
          .blur(14)
          .opacity(0.38)
          .draggable(false)
          .align(Alignment.Top)
      }

      Column()
        .width('100%')
        .height(620)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#22000000', 0], [$r('app.color.page_background_media'), 0.48],
            [$r('app.color.page_background'), 1]]
        })
        .align(Alignment.Top)

      HdsNavigation() {
        Scroll(this.scroller) {
          Column() {
            Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')

          if (this.showSearch) {
            this.SearchBar()
          }

          if (this.loading) {
            this.LoadingState()
          } else if (this.errorText.length > 0) {
            this.ErrorState()
          } else if (this.searchText.trim().length > 0) {
            this.SearchResults()
          } else if (this.isHome()) {
            this.HomeContent()
          } else if (this.resumeOnly) {
            this.ProgressContent()
          } else {
            this.LibraryContent()
          }

          Blank().height(this.bottomSafeHeight + 28).width('100%')
          }
          .width('100%')
          .constraintSize({ minHeight: '100%', maxWidth: getContentMaxWidth(this.screenWidthVp) || '100%' })
          .padding({ left: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
            right: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildEmbyTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.isHome())
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background_media'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.pageWidth = Math.max(320, newArea.width as number)
    })
  }

  private buildEmbyTitleBarOptions(): HdsNavigationTitleBarOptions {
    const mainTitle: string = this.isHome() ?
      (this.config === null || this.config!.serverName.length === 0 ? 'Emby' : this.config!.serverName) :
      this.title
    const subTitle: string = this.isHome() ?
      (this.config === null || this.config!.userName.length === 0 ? '媒体中心' : this.config!.userName) :
      this.items.length + ' 个项目'
    const base: HdsNavigationTitleBarOptions = {
      style: buildImmersiveTitleBarStyle(this.hdsMaterialLevel),
      content: {
        title: { mainTitle: mainTitle, subTitle: subTitle },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.magnifyingglass'),
                label: '搜索 Emby 内容',
                action: (): void => {
                  this.showSearch = !this.showSearch
                  if (!this.showSearch) this.clearSearch()
                }
              } as HdsNavigationIconOptions
            },
            {
              content: {
                icon: this.isHome() ? $r('sys.symbol.folder_fill') : $r('sys.symbol.arrow_clockwise'),
                label: this.isHome() ? '媒体库' : '刷新 Emby 内容',
                action: (): void => {
                  if (this.isHome()) {
                    this.openSection('libraries', '媒体库')
                  } else {
                    this.loadItems()
                  }
                }
              } as HdsNavigationIconOptions
            }
          ]
        }
      },
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
    return base
  }

  @Builder
  private SearchBar(): void {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
      TextInput({ placeholder: '搜索家庭影院', text: this.searchText })
        .layoutWeight(1)
        .height(46)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_hint'))
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string) => {
          this.searchText = value
          this.scheduleGlobalSearch(value)
        })
      if (this.searchText.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .onClick(() => this.clearSearch())
      }
    }
    .width('calc(100% - ' + this.pagePadding() * 2 + 'vp)')
    .height(48)
    .padding({ left: 14, right: 14 })
    .margin({ left: this.pagePadding(), right: this.pagePadding(), bottom: 14 })
    .borderRadius(16)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.7, color: $r('app.color.card_specular_border') })
  }

  @Builder
  private HomeContent(): void {
    Column({ space: 30 }) {
      if (this.featuredItems().length > 0) {
        this.FeaturedHero(this.featuredItems()[0])
      }

      if (this.resumeItems.length > 0) {
        this.HomeMediaSection('继续观看', this.resumeItems, 'resume')
      }

      if (this.latestItems.length > 0) {
        this.HomeMediaSection('最近添加', this.latestItems, 'latest')
      }

      ForEach(this.homeSections, (section: EmbyHomeSection) => {
        if (section.items.length > 0) {
          this.HomeMediaSection(section.title, section.items, section.id, section.collectionType)
        }
      }, (section: EmbyHomeSection) => 'section_' + section.id)

      if (this.latestItems.length === 0 && this.resumeItems.length === 0 && this.homeSections.length === 0) {
        this.InlineEmptyState('服务器没有返回可显示的媒体')
      }
    }
    .width('100%')
    .padding({ top: 6 })
  }

  @Builder
  private FeaturedHero(item: EmbyItem): void {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.heroUsesPoster(item)) {
        Image(this.heroImageUrl(item, 1000))
          .width('100%').height(280).objectFit(ImageFit.Cover)
          .blur(18).opacity(0.42).draggable(false)
        Image(this.heroImageUrl(item, 1000))
          .width('100%').height(280).objectFit(ImageFit.Contain).draggable(false)
      } else if (this.heroImageUrl(item, 1000).length > 0) {
        Image(this.heroImageUrl(item, 1000))
          .width('100%').height(280).objectFit(ImageFit.Cover).draggable(false)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(52)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%').height(280).justifyContent(FlexAlign.Center)
      }
      Column()
        .width('100%').height(280)
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [['#00000000', 0.18], [$r('app.color.page_background_media'), 1]] })
      Column({ space: 7 }) {
        Text(item.name).fontSize(25).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(item.subtitle()).fontSize(13).fontColor($r('app.color.text_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (item.resumePositionMs() > 0) {
          MediaProgressBar({ positionMs: item.resumePositionMs(), durationMs: item.durationMs() })
            .width('100%')
        }
        Button(this.featuredActionLabel(item)).height(40).fontSize(14)
          .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
          .borderRadius(20).onClick(() => { void this.openFeaturedItem(item) })
      }
      .width('100%').padding({ left: 20, right: 20, bottom: 18 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height(280).clip(true).borderRadius(18)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private HomeMediaSection(title: string, source: EmbyItem[], sectionId: string,
    collectionType: string = ''): void {
    Column({ space: 14 }) {
      MediaSectionHeader({ title: title, actionText: '全部',
        onAction: () => this.openSection(sectionId, title, collectionType) })

      Scroll() {
        Row({ space: 16 }) {
          ForEach(source, (item: EmbyItem) => {
            if (sectionId === 'resume') {
              this.ResumeMediaCard(item)
            } else {
              MediaPosterCard({ title: item.name, subtitle: item.subtitle(),
                artworkUrl: this.itemImageUrl(item, 500), onCardClick: () => this.openItem(item) })
            }
          }, (item: EmbyItem) => sectionId + '_' + item.id)
        }
        .padding({ left: this.pagePadding(), right: this.pagePadding() })
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private ResumeMediaCard(item: EmbyItem): void {
    ContinueWatchingCard({ title: item.name, subtitle: item.subtitle(),
      artworkUrl: this.itemImageUrl(item, 700), positionMs: item.resumePositionMs(),
      durationMs: item.durationMs(), onCardClick: () => { void this.openResumeItem(item) } })
  }

  @Builder
  private ProgressContent(): void {
    Column({ space: 18 }) {
      Row() {
        Text('观看进度')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.resumeItems.length + ' 项').fontSize(13).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      if (this.resumeItems.length === 0) {
        this.InlineEmptyState('还没有未看完的内容')
      } else {
        this.PosterGrid(this.resumeItems)
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 12 })
  }

  @Builder
  private LibraryContent(): void {
    Column({ space: 16 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.filters, (filter: string) => {
            Text(filter)
              .fontSize(13)
              .fontWeight(this.selectedFilter === filter ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.selectedFilter === filter ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
              .borderRadius(18)
              .backgroundColor(this.selectedFilter === filter ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
              .border({ width: 0.5, color: this.selectedFilter === filter ? $r('app.color.accent_blue') :
                $r('app.color.card_specular_border') })
              .onClick(() => this.selectedFilter = filter)
          }, (filter: string) => filter)
        }
        .padding({ right: this.pagePadding() })
      }
      .width('calc(100% + ' + this.pagePadding() + 'vp)')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      Row() {
        Text(this.filteredItems().length + ' 个项目')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text('按名称排序').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      if (this.filteredItems().length === 0) {
        this.InlineEmptyState('当前分类没有可显示的内容')
      } else {
        this.PosterGrid(this.filteredItems())
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 10 })
  }

  @Builder
  private SearchResults(): void {
    Column({ space: 16 }) {
      Row() {
        Text('搜索结果')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.searchResults().length + ' 项').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      if (this.searchLoading) {
        InlineLoadingState({ message: '正在搜索家庭影院' })
      } else if (this.searchResults().length === 0) {
        this.InlineEmptyState('没有找到“' + this.searchText.trim() + '”')
      } else {
        this.PosterGrid(this.searchResults())
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 10 })
  }

  @Builder
  private PosterGrid(source: EmbyItem[]): void {
    Grid() {
      ForEach(source, (item: EmbyItem) => {
        GridItem() {
          if (item.resumePositionMs() > 0) {
            this.ResumeMediaCard(item)
          } else {
            MediaPosterCard({ title: item.name, subtitle: item.subtitle(),
              artworkUrl: this.itemImageUrl(item, 700), onCardClick: () => this.openItem(item) })
          }
        }
      }, (item: EmbyItem) => 'poster_' + item.id)
    }
    .columnsTemplate(this.posterColumns())
    .columnsGap(12)
    .rowsGap(18)
    .width('100%')
  }

  @Builder
  private LoadingState(): void {
    PageLoadingState({ title: this.isHome() ? '正在同步媒体首页' : '正在读取“' + this.title + '”', minHeight: 420 })
  }

  @Builder
  private ErrorState(): void {
    PageErrorState({ title: '媒体库暂时不可用', message: this.errorText,
      retryText: this.config === null ? '配置服务器' : '重新加载',
      onRetry: () => this.config === null ? this.openSettings() : this.loadItems() })
  }

  @Builder
  private InlineEmptyState(message: string): void {
    PageEmptyState({ icon: $r('sys.symbol.folder'), title: message, minHeight: 220 })
  }

  private async loadItems(): Promise<void> {
    const generation = ++this.loadGeneration
    this.loading = true
    this.errorText = ''
    let hasCachedHome = false
    try {
      if (this.sourceId.length === 0) {
        this.errorText = '媒体源参数无效，请从媒体来源列表进入'
        return
      }
      const source = await MediaSourceStore.getById(this.sourceId)
      if (generation !== this.loadGeneration) return
      if (source === null || !source.enabled || source.providerType !== 'emby') {
        this.errorText = 'Emby 媒体源不可用或已停用'
        return
      }
      this.config = EmbySourceConfigCodec.decode(source.configJson)
      if (generation !== this.loadGeneration) return
      if (this.config === null) {
        this.errorText = 'Emby 媒体源配置无效'
        return
      }
      const registeredProvider = await ProviderRegistry.get(this.sourceId,
        this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!(registeredProvider instanceof EmbyProvider)) {
        this.errorText = 'Emby 媒体源不可用或已停用'
        return
      }
      this.provider = registeredProvider
      if (this.isHome()) {
        hasCachedHome = await this.restoreHomeCache(this.config!)
        if (generation !== this.loadGeneration) return
        if (hasCachedHome) {
          this.loading = false
        }
        this.items = await this.provider.getLibrariesRaw()
        if (generation !== this.loadGeneration) return
        const tasks: Array<Promise<EmbyItem[]>> = [
          this.loadResumeItems(this.provider),
          this.loadLatestItems(this.provider)
        ]
        const results: EmbyItem[][] = await Promise.all(tasks)
        if (generation !== this.loadGeneration) return
        this.resumeItems = results[0]
        this.latestItems = results[1]
        this.homeSections = await this.loadHomeSections(this.provider, this.items)
        if (generation !== this.loadGeneration) return
        await this.saveHomeCache()
      } else {
        if (this.latestOnly) {
          this.items = await this.provider.getLatestItemsRaw(0)
        } else if (this.resumeOnly) {
          this.items = []
          this.resumeItems = await this.provider.getResumeItemsRaw()
        } else if (this.libraryRoot) {
          // Library entry pages should show media posters, not the server's
          // physical folder tree. Nested item pages keep the old behavior.
          this.items = await this.provider.getLibraryItemsRaw(this.parentId, 0, this.collectionType)
        } else {
          this.items = await this.provider.getItemsRaw(this.parentId)
        }
        if (generation !== this.loadGeneration) return
        if (!this.resumeOnly) this.resumeItems = []
        this.latestItems = []
        this.homeSections = []
      }
    } catch (err) {
      if (generation === this.loadGeneration && !hasCachedHome) {
        this.items = []
        this.resumeItems = []
        this.latestItems = []
        this.homeSections = []
        this.errorText = err instanceof Error ? err.message : 'Emby 媒体库读取失败'
      }
    } finally {
      if (generation !== this.loadGeneration) return
      this.loading = false
      if (this.pendingItemId.length > 0 && this.config !== null && this.provider !== null) {
        void this.openPendingItem()
      }
    }
  }

  private async openPendingItem(): Promise<void> {
    const itemId = this.pendingItemId
    this.pendingItemId = ''
    if (itemId.length === 0 || this.config === null || this.provider === null || this.sourceId.length === 0) return
    try {
      const item = await this.provider.getItemRaw(itemId)
      if (item !== null && !item.isFolder) await this.openItem(item)
    } catch (_) {
      promptAction.showToast({ message: '无法播放该媒体' })
    }
  }

  private homeCacheKey(config: EmbyServerConfig): string {
    return EMBY_HOME_CACHE_KEY_PREFIX + encodeURIComponent(
      this.sourceId + '|' + config.serverId + '|' + config.userId + '|' + config.baseUrl)
  }

  private async restoreHomeCache(config: EmbyServerConfig): Promise<boolean> {
    try {
      const raw = await PreferencesStore.getInstance().getString(this.homeCacheKey(config), '')
      if (raw.length === 0) return false
      const parsed = JSON.parse(raw) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return false
      const payload = parsed as Record<string, Object>
      const timestamp = typeof payload['timestamp'] === 'number' ? payload['timestamp'] as number : 0
      if (timestamp <= 0) return false
      this.items = this.decodeCachedItems(payload['libraries'])
      this.resumeItems = this.decodeCachedItems(payload['resumeItems'])
      this.latestItems = this.decodeCachedItems(payload['latestItems'])
      this.homeSections = this.decodeCachedSections(payload['sections'])
      return true
    } catch (_err) {
      return false
    }
  }

  private async saveHomeCache(): Promise<void> {
    if (this.config === null) return
    try {
      const payload = new EmbyHomeCachePayload()
      payload.timestamp = Date.now()
      payload.libraries = this.items
      payload.resumeItems = this.resumeItems
      payload.latestItems = this.latestItems
      payload.sections = this.homeSections
      await PreferencesStore.getInstance().setString(this.homeCacheKey(this.config!), JSON.stringify(payload))
    } catch (_err) {
      // Cache failures must never affect the Emby page.
    }
  }

  private decodeCachedItems(raw: Object): EmbyItem[] {
    if (!Array.isArray(raw)) return []
    const result: EmbyItem[] = []
    const values = raw as Array<Record<string, Object>>
    for (let i = 0; i < values.length; i++) {
      const candidate = values[i] as Object
      if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) continue
      const value = candidate as Record<string, Object>
      const item = new EmbyItem()
      item.id = this.cachedString(value, 'id')
      item.name = this.cachedString(value, 'name')
      item.type = this.cachedString(value, 'type')
      item.parentId = this.cachedString(value, 'parentId')
      item.collectionType = this.cachedString(value, 'collectionType')
      item.isFolder = this.cachedBoolean(value, 'isFolder')
      item.runTimeTicks = this.cachedNumber(value, 'runTimeTicks')
      item.productionYear = this.cachedNumber(value, 'productionYear')
      item.indexNumber = this.cachedNumber(value, 'indexNumber')
      item.parentIndexNumber = this.cachedNumber(value, 'parentIndexNumber')
      item.seriesName = this.cachedString(value, 'seriesName')
      item.overview = this.cachedString(value, 'overview')
      item.imageItemId = this.cachedString(value, 'imageItemId')
      item.primaryImageTag = this.cachedString(value, 'primaryImageTag')
      item.backdropImageTag = this.cachedString(value, 'backdropImageTag')
      item.backdropItemId = this.cachedString(value, 'backdropItemId')
      item.thumbnailImageTag = this.cachedString(value, 'thumbnailImageTag')
      item.thumbnailItemId = this.cachedString(value, 'thumbnailItemId')
      item.container = this.cachedString(value, 'container')
      const userData = value['userData']
      if (userData !== null && typeof userData === 'object') {
        const data = userData as Record<string, Object>
        item.userData.playbackPositionTicks = this.cachedNumber(data, 'playbackPositionTicks')
        item.userData.playedPercentage = this.cachedNumber(data, 'playedPercentage')
        item.userData.played = this.cachedBoolean(data, 'played')
      }
      if (item.id.length > 0 && item.name.length > 0) result.push(item)
    }
    return result
  }

  private decodeCachedSections(raw: Object): EmbyHomeSection[] {
    if (!Array.isArray(raw)) return []
    const result: EmbyHomeSection[] = []
    const values = raw as Array<Record<string, Object>>
    for (let i = 0; i < values.length; i++) {
      const candidate = values[i] as Object
      if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) continue
      const value = candidate as Record<string, Object>
      const section = new EmbyHomeSection()
      section.id = this.cachedString(value, 'id')
      section.title = this.cachedString(value, 'title')
      section.collectionType = this.cachedString(value, 'collectionType')
      section.items = this.decodeCachedItems(value['items'])
      if (section.id.length > 0 && section.items.length > 0) result.push(section)
    }
    return result
  }

  private cachedString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }

  private cachedNumber(value: Record<string, Object>, key: string): number {
    return typeof value[key] === 'number' && Number.isFinite(value[key] as number) ? value[key] as number : 0
  }

  private cachedBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }

  private async loadResumeItems(provider: EmbyProvider): Promise<EmbyItem[]> {
    try {
      return await provider.getResumeItemsRaw()
    } catch {
      return []
    }
  }

  private async loadLatestItems(provider: EmbyProvider): Promise<EmbyItem[]> {
    try {
      return await provider.getLatestItemsRaw()
    } catch {
      return []
    }
  }

  private async loadHomeSections(provider: EmbyProvider, libraries: EmbyItem[]): Promise<EmbyHomeSection[]> {
    const tasks: Array<Promise<EmbyItem[]>> = []
    for (let i = 0; i < libraries.length; i++) {
      tasks.push(this.loadLibraryPreview(provider, libraries[i]))
    }
    const previews: EmbyItem[][] = await Promise.all(tasks)
    const sections: EmbyHomeSection[] = []
    for (let i = 0; i < libraries.length; i++) {
      if (previews[i].length > 0) {
        const section = new EmbyHomeSection()
        section.id = libraries[i].id
        section.title = libraries[i].name
        section.collectionType = libraries[i].collectionType
        section.items = previews[i]
        sections.push(section)
      }
    }
    return sections
  }

  private async loadLibraryPreview(provider: EmbyProvider, library: EmbyItem): Promise<EmbyItem[]> {
    try {
      return await provider.getLibraryItemsRaw(library.id, 12, library.collectionType)
    } catch {
      return []
    }
  }

  private filteredItems(): EmbyItem[] {
    const result: EmbyItem[] = []
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i]
      if (this.matchesFilter(item, this.selectedFilter)) result.push(item)
    }
    return result
  }

  private searchResults(): EmbyItem[] {
    return this.globalSearchItems
  }

  private localSearchResults(keyword: string): EmbyItem[] {
    const normalizedKeyword = keyword.trim().toLowerCase()
    if (normalizedKeyword.length === 0) return []
    const source: EmbyItem[] = []
    this.appendUnique(source, this.items)
    this.appendUnique(source, this.resumeItems)
    this.appendUnique(source, this.latestItems)
    for (let i = 0; i < this.homeSections.length; i++) {
      this.appendUnique(source, this.homeSections[i].items)
    }
    const result: EmbyItem[] = []
    for (let i = 0; i < source.length; i++) {
      const item = source[i]
      if (item.name.toLowerCase().indexOf(normalizedKeyword) >= 0 ||
        item.seriesName.toLowerCase().indexOf(normalizedKeyword) >= 0) {
        result.push(item)
      }
    }
    return result
  }

  private scheduleGlobalSearch(value: string): void {
    if (this.searchTimer >= 0) clearTimeout(this.searchTimer)
    // 输入变化立即使正在进行的旧请求失效，避免新关键词短暂显示旧结果。
    this.searchGeneration++
    const keyword = value.trim()
    if (keyword.length === 0) {
      this.clearSearch()
      return
    }
    this.searchLoading = true
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1
      void this.performGlobalSearch(keyword)
    }, 260)
  }

  private async performGlobalSearch(keyword: string): Promise<void> {
    const generation = ++this.searchGeneration
    if (this.provider === null) {
      this.globalSearchItems = this.localSearchResults(keyword)
      this.searchLoading = false
      return
    }
    try {
      const results = await this.provider.searchRaw(keyword)
      if (generation !== this.searchGeneration) return
      this.globalSearchItems = results
    } catch (_) {
      // 网络搜索失败时保留已加载内容的本地结果，页面仍可继续使用。
      if (generation !== this.searchGeneration) return
      this.globalSearchItems = this.localSearchResults(keyword)
    } finally {
      if (generation === this.searchGeneration) this.searchLoading = false
    }
  }

  private clearSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    this.searchGeneration++
    this.searchText = ''
    this.globalSearchItems = []
    this.searchLoading = false
  }

  private appendUnique(target: EmbyItem[], source: EmbyItem[]): void {
    for (let i = 0; i < source.length; i++) {
      let exists = false
      for (let j = 0; j < target.length; j++) {
        if (target[j].id === source[i].id) {
          exists = true
          break
        }
      }
      if (!exists) target.push(source[i])
    }
  }

  private matchesFilter(item: EmbyItem, filter: string): boolean {
    if (filter === '全部') return true
    if (filter === '文件夹') return item.isFolder
    if (filter === '电影') return item.type === 'Movie' || item.type === 'Video'
    if (filter === '剧集') {
      return item.type === 'Series' || item.type === 'Season' || item.type === 'Episode'
    }
    return true
  }

  private itemImageUrl(item: EmbyItem, maxWidth: number = 500): string {
    return this.provider === null ? '' : this.provider.imageUrlFor(item, maxWidth)
  }

  private heroImageUrl(item: EmbyItem, maxWidth: number = 1000): string {
    if (this.provider === null) return ''
    const backdrop = this.provider.backdropUrlFor(item, maxWidth)
    if (backdrop.length > 0) return backdrop
    const thumbnail = this.provider.thumbnailUrlFor(item, maxWidth)
    if (thumbnail.length > 0) return thumbnail
    return this.itemImageUrl(item, maxWidth)
  }

  private heroUsesPoster(item: EmbyItem): boolean {
    if (this.provider === null) return false
    if (this.provider.backdropUrlFor(item, 1000).length > 0) return false
    if (this.provider.thumbnailUrlFor(item, 900).length > 0) return false
    return this.itemImageUrl(item, 1000).length > 0
  }

  private async openItem(item: EmbyItem, libraryRoot: boolean = false): Promise<void> {
    if (item.isFolder) {
      const params: Record<string, Object> = {
        'sourceId': this.sourceId,
        'parentId': item.id,
        'title': item.name
      }
      if (libraryRoot) {
        params['libraryRoot'] = true
        params['collectionType'] = item.collectionType
      }
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/emby/EmbyLibraryPage',
        params: params
      })
      return
    }
    if (this.config === null) return
    if (this.sourceId.length === 0) throw new Error('Emby 媒体源未配置')
    await this.getUIContext().getRouter().pushUrl({
      url: 'pages/emby/EmbyDetailPage',
      params: { sourceId: this.sourceId, itemId: item.id }
    })
  }

  /** 续播入口直接交给统一播放器；没有进度的精选内容仍进入详情页。 */
  private async openFeaturedItem(item: EmbyItem): Promise<void> {
    if (item.resumePositionMs() > 0 && !item.isFolder) {
      await this.openResumeItem(item)
      return
    }
    await this.openItem(item)
  }

  private async openResumeItem(item: EmbyItem): Promise<void> {
    if (item.isFolder || this.sourceId.length === 0) {
      await this.openItem(item)
      return
    }
    try {
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, item, [item])
    } catch (_) {
      promptAction.showToast({ message: '无法播放该媒体' })
    }
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/sources/SourceManagerPage' })
  }

  /** 保持连续播放在当前浏览或首页分区内，避免跨库、跨分区自动跳转。 */
  private getPlaybackQueue(item: EmbyItem): EmbyItem[] {
    const sources: EmbyItem[][] = [this.items, this.resumeItems, this.latestItems]
    for (let i = 0; i < this.homeSections.length; i++) sources.push(this.homeSections[i].items)
    for (let i = 0; i < sources.length; i++) {
      for (let j = 0; j < sources[i].length; j++) {
        if (sources[i][j].id === item.id) return sources[i]
      }
    }
    return [item]
  }

  private openSection(sectionId: string, sectionTitle: string, collectionType: string = ''): void {
    if (sectionId === 'resume') {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/emby/EmbyLibraryPage',
        params: { 'sourceId': this.sourceId, 'view': 'resume', 'title': sectionTitle }
      })
      return
    }
    if (sectionId === 'latest') {
      // The latest-only page has no parentId and must not push itself again.
      if (this.latestOnly) return
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/emby/EmbyLibraryPage',
        params: { 'sourceId': this.sourceId, 'view': 'latest', 'title': sectionTitle }
      })
      return
    }
    const params: Record<string, Object> = {
      'sourceId': this.sourceId,
      'parentId': sectionId,
      'title': sectionTitle,
      'libraryRoot': true,
      'collectionType': collectionType
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/emby/EmbyLibraryPage',
      params: params
    })
  }

  private isHome(): boolean {
    // A latest-only route also has no parentId, but it is a list page rather
    // than the home page. Keeping it out of the home branch prevents the
    // "全部" entry from rendering again and recursively navigating.
    return this.parentId.length === 0 && !this.latestOnly && !this.resumeOnly
  }

  private featuredItems(): EmbyItem[] {
    const result: EmbyItem[] = []
    this.appendUnique(result, this.resumeItems)
    this.appendUnique(result, this.latestItems)
    if (result.length > 6) return result.slice(0, 6)
    return result
  }

  private featuredActionLabel(item: EmbyItem): string {
    return item.resumePositionMs() > 0 ? '继续播放' : '查看详情'
  }

  private pagePadding(): number {
    return this.pageWidth >= 840 ? 32 : 18
  }

  private posterColumns(): string {
    if (this.pageWidth >= 1100) return '1fr 1fr 1fr 1fr 1fr 1fr'
    if (this.pageWidth >= 840) return '1fr 1fr 1fr 1fr 1fr'
    if (this.pageWidth >= 600) return '1fr 1fr 1fr 1fr'
    if (this.pageWidth >= 410) return '1fr 1fr 1fr'
    return '1fr 1fr'
  }

}
