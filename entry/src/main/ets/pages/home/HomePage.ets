import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore, MEDIA_SOURCE_VERSION_KEY } from '../../store/MediaSourceStore'
import { ActiveSourceStore, ACTIVE_HOME_SOURCE_KEY } from '../../store/ActiveSourceStore'
import { HomeSourcePolicy } from '../../services/library/HomeSourcePolicy'
import { LibraryPage } from '../library/LibraryPage'
import { EmbyHomeContent } from '../emby/EmbyHomeContent'
import { WebDavHomeContent } from './WebDavHomeContent'
import { CatVodContent } from '../catvod/CatVodContent'
import { CatVodHomeTitle } from '../catvod/CatVodHomeTitle'
import { CatVodHomeNavigation } from '../catvod/CatVodHomeNavigation'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { buildDetailSheetMaterial } from '../../utils/DetailMaterial'
import { UserDownloadFolder } from '../../services/UserDownloadFolder'
import { LOCAL_MEDIA_LIBRARY_VERSION_KEY } from '../../store/LocalMediaLibraryChangeSignal'
import {
  buildImmersiveTitleBarStyle,
  buildHeroTitleBarStyle,
  getTopSpacerHeight,
  getBottomSpacerHeight,
  HDS_MATERIAL_LEVEL_DEFAULT,
  IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

@Component
export struct HomePage {
  @Prop @Watch('onActiveChanged') isActive: boolean = true
  @StorageLink(ACTIVE_HOME_SOURCE_KEY) @Watch('onSelectionChanged') selectedId: string = 'local'
  @StorageLink(MEDIA_SOURCE_VERSION_KEY) @Watch('reloadSources') sourceVersion: number = 0
  @StorageLink(LOCAL_MEDIA_LIBRARY_VERSION_KEY) @Watch('reloadSources') localLibraryVersion: number = 0
  @StorageLink('appInForeground') @Watch('onForegroundChanged') appInForeground: boolean = true
  @StorageLink('appRdbReady') @Watch('reloadSources') ready: boolean = false
  @StorageLink('currentTab') currentTab: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidth: number = 360
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @State private sources: MediaSourceInstance[] = []
  @State private loading: boolean = true
  @State private hasServices: boolean = false
  @State private error: string = ''
  @State private showSourceMenu: boolean = false
  @State private searchToken: number = 0
  @State private refreshToken: number = 0
  @State private catNavigation: CatVodHomeNavigation = new CatVodHomeNavigation()
  @State private catSelecting: boolean = false
  @State private embyBackgroundSource: string = ''
  @State private embyBackgroundUpdatedAt: number = 0
  @State private embyBackgroundColor: string = ''
  private generation: number = 0
  private catSelectionGeneration: number = 0
  private scrollers: Map<string, Scroller> = new Map()

  aboutToAppear(): void { void this.reloadSources() }
  aboutToDisappear(): void { this.generation++; this.catSelectionGeneration++ }
  private onActiveChanged(): void {
    if (this.isActive) void this.reloadSources()
    else { this.catSelectionGeneration++; this.catSelecting = false }
  }
  private onForegroundChanged(): void { if (this.appInForeground && this.isActive) void this.reloadSources() }
  private onSelectionChanged(): void {
    this.error = ''; this.showSourceMenu = false
    this.catSelectionGeneration++
    this.catNavigation = new CatVodHomeNavigation(); this.catSelecting = false
    this.embyBackgroundSource = ''; this.embyBackgroundUpdatedAt = 0; this.embyBackgroundColor = ''
  }

  private activeScroller(): Scroller {
    let scroller = this.scrollers.get(this.selectedId)
    if (scroller === undefined) {
      scroller = new Scroller()
      this.scrollers.set(this.selectedId, scroller)
    }
    return scroller
  }

  private async reloadSources(): Promise<void> {
    const generation = ++this.generation
    try {
      const sources = await MediaSourceStore.getAllStrict()
      await ActiveSourceStore.restore()
      if (generation !== this.generation) return
      this.sources = sources
      this.hasServices = HomeSourcePolicy.hasAddedService(sources, UserDownloadFolder.getExistingOwnFolder().length > 0)
      this.loading = false
      this.error = ''
    } catch (_) {
      if (generation === this.generation) { this.loading = false; this.error = '无法读取服务，请重试' }
    }
  }

  private selectedSource(): MediaSourceInstance | undefined {
    return this.sources.find((source: MediaSourceInstance) => source.id === this.selectedId &&
      HomeSourcePolicy.canSelect(source))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        if (this.loading) {
          this.HomeState(true)
        } else if (this.error.length > 0) {
          this.HomeState(false)
        } else if (!this.hasServices) {
          this.NoServicesState()
        } else if (this.selectedSource() === undefined) {
          this.HomeState(false)
        } else {
          ForEach([this.selectedSource()!], (source: MediaSourceInstance) => {
            if (source.providerType === 'emby') {
              EmbyHomeContent({ source: source, isActive: this.isActive, scroller: this.activeScroller(),
                searchToken: this.searchToken, refreshToken: this.refreshToken,
                onBackgroundChanged: (id: string, updatedAt: number, color: string) =>
                  this.onEmbyBackgroundChanged(id, updatedAt, color) })
            } else if (source.providerType === 'webdav') {
              WebDavHomeContent({ source: source, isActive: this.isActive, scroller: this.activeScroller(),
                refreshToken: this.refreshToken })
            } else if (source.providerType === 'catvod' || source.providerType === 'catnode') {
              CatVodContent({ source: source, isActive: this.isActive, scroller: this.activeScroller(),
                refreshToken: this.refreshToken, embeddedHomeTitle: true,
                onNavigationChanged: (state: CatVodHomeNavigation) => this.onCatNavigationChanged(state) })
            } else {
              LibraryPage({ isActive: this.isActive, embedded: true, scroller: this.activeScroller(),
                refreshToken: this.refreshToken })
            }
          }, (source: MediaSourceInstance) => source.id + ':' + source.updatedAt)
        }
      }.width('100%').height('100%').mode(NavigationMode.Stack)
        .titleBar(this.titleOptions()).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
        .backgroundColor(Color.Transparent).bindToScrollable([this.activeScroller()])
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      // Non-interactive anchor: the visible trigger is the native HDS title-menu icon.
      Column().width(44).height(44).backgroundColor(Color.Transparent)
        .position({ x: Math.max(0, this.screenWidth - 112), y: this.topSafeHeight + 6 })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        .bindMenu(this.showSourceMenu, this.sourceMenuItems(), this.sourceMenuOptions())
    }.width('100%').height(LayoutPolicy.matchParent)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [this.homeBackground(true), 0],
          [this.homeBackground(false), 0.35],
          [this.homeBackground(false), 1]
        ]
      }).animation({ duration: 500, curve: Curve.EaseInOut })
  }

  private titleOptions(): HdsNavigationTitleBarOptions {
    const options: HdsNavigationTitleBarOptions = {
      style: this.selectedSource()?.providerType === 'emby' ||
        (this.isCatSource() && this.catNavigation.sourceId === this.selectedId && this.catNavigation.heroVisible)
        ? buildHeroTitleBarStyle(this.hdsMaterialLevel)
        : buildImmersiveTitleBarStyle(this.hdsMaterialLevel),
      content: {
        title: {
          mainTitle: '首页'
        },
        menu: { value: [
          { content: { icon: $r('sys.symbol.externaldrive'), label: '切换首页服务',
            isEnabled: !this.loading && this.selectableSources().length > 0,
            action: () => { this.showSourceMenu = !this.showSourceMenu } } },
          { content: { icon: this.supportsHomeSearch() ?
            $r('sys.symbol.magnifyingglass') : $r('sys.symbol.arrow_clockwise'),
            label: this.supportsHomeSearch() ? '搜索当前服务' : '刷新',
            action: () => this.handleSearchAction() } }
        ] }
      },
      enableComponentSafeArea: false, avoidLayoutSafeArea: true
    }
    if (this.isCatSource() && options.content !== undefined) {
      options.content.title = { mainTitle: '' }
      options.content.stackBuilder = (): void => this.CatSourceTitle()
    }
    return options
  }

  private isCatSource(): boolean {
    const type = this.selectedSource()?.providerType
    return type === 'catnode' || type === 'catvod'
  }

  private onCatNavigationChanged(state: CatVodHomeNavigation): void {
    if (!this.isActive || !this.isCatSource() || state.sourceId !== this.selectedId) return
    this.catNavigation = state
  }

  private homeBackground(top: boolean): ResourceColor {
    const source = this.selectedSource()
    if (!this.loading && this.error.length === 0 && source?.providerType === 'emby' &&
      this.embyBackgroundSource === source.id && this.embyBackgroundUpdatedAt === source.updatedAt &&
      /^#[0-9a-f]{6}$/i.test(this.embyBackgroundColor)) return this.embyBackgroundColor
    if (!this.loading && this.error.length === 0 && this.isCatSource() &&
      this.catNavigation.sourceId === this.selectedId && this.catNavigation.heroVisible &&
      /^#[0-9a-f]{6}$/i.test(this.catNavigation.heroSurface)) return this.catNavigation.heroSurface
    return top ? $r('app.color.home_bg_top') : $r('app.color.page_background')
  }

  private onEmbyBackgroundChanged(sourceId: string, updatedAt: number, color: string): void {
    const source = this.selectedSource()
    if (!this.isActive || source?.providerType !== 'emby' || source.id !== sourceId || source.updatedAt !== updatedAt) return
    this.embyBackgroundSource = sourceId; this.embyBackgroundUpdatedAt = updatedAt
    this.embyBackgroundColor = /^#[0-9a-f]{6}$/i.test(color) ? color : ''
  }

  private catTitleSites(): CatNodeSite[] {
    if (this.selectedSource()?.providerType === 'catnode') {
      return this.catNavigation.sourceId === this.selectedId ? this.catNavigation.sites : []
    }
    return this.selectableSources().filter((source: MediaSourceInstance) => source.providerType === 'catvod' ||
      source.providerType === 'catnode').map((source: MediaSourceInstance): CatNodeSite => {
      const site = new CatNodeSite()
      site.key = source.id; site.name = source.name
      return site
    })
  }

  private catTitleKey(): string {
    return this.selectedSource()?.providerType === 'catnode' ?
      (this.catNavigation.sourceId === this.selectedId ? this.catNavigation.selectedKey : '') : this.selectedId
  }

  private catTitleName(): string {
    return this.catTitleSites().find((site: CatNodeSite) => site.key === this.catTitleKey())?.name ??
      this.selectedSource()?.name ?? ''
  }

  private async selectCatSite(key: string): Promise<void> {
    const source = this.selectedSource()
    if (!this.isActive || source === undefined || this.catSelecting || key === this.catTitleKey() ||
      !this.catTitleSites().some((site: CatNodeSite) => site.key === key)) return
    if (source.providerType !== 'catnode') { await this.select(key); return }
    const navigation = this.catNavigation
    if (navigation.sourceId !== source.id || navigation.loading || navigation.provider === null) return
    const selectionGeneration = ++this.catSelectionGeneration
    this.catSelecting = true
    try {
      await navigation.provider.selectSite(key)
      // Source-store updates remount the content with the persisted selection.
    } catch (error) {
      if (this.isActive && this.selectedId === source.id && selectionGeneration === this.catSelectionGeneration) {
        this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(error instanceof Error ? error.message :
          this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.cat_home_switch_failed').id)))
      }
    } finally {
      if (this.selectedId === source.id && selectionGeneration === this.catSelectionGeneration) this.catSelecting = false
    }
  }

  @Builder
  private CatSourceTitle(): void {
    Row() {
      CatVodHomeTitle({ title: this.catTitleName(), sites: this.catTitleSites(), selectedKey: this.catTitleKey(),
        busy: this.catSelecting || (this.selectedSource()?.providerType === 'catnode' &&
          (this.catNavigation.sourceId !== this.selectedId || this.catNavigation.loading)),
        isActive: this.isActive, maxWidth: Math.max(100, Math.min(320, this.screenWidth - 160)),
        onSelect: (key: string) => { void this.selectCatSite(key) } })
    }.width('100%').height(56).padding({ left: 16, right: 128 })
      .justifyContent(FlexAlign.Start).hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private NoServicesState(): void {
    Column() {
      Column({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(48).fontColor([$r('app.color.text_secondary')])
          .margin({ bottom: 8 }).accessibilityText('暂无服务')
        Text('暂无服务').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center)
        Text('请先添加媒体服务').fontSize(14).fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        Button('前往服务页面').height(46).fontSize(15).fontWeight(FontWeight.Medium)
          .padding({ left: 24, right: 24 }).borderRadius(23)
          .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
          .margin({ top: 14 }).onClick(() => { this.currentTab = 1 })
      }.width('100%').alignItems(HorizontalAlign.Center)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 24, right: 24, top: getTopSpacerHeight(this.topSafeHeight),
        bottom: getBottomSpacerHeight(this.bottomSafeHeight) })
  }

  @Builder
  private HomeState(loading: boolean): void {
    Column() {
      Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
      if (loading) {
        PageLoadingState({ title: '正在读取首页', minHeight: 300 })
      } else {
        PageErrorState({ title: '首页暂不可用', message: this.error,
          onRetry: () => { void this.reloadSources() } })
      }
    }.width('100%').height('100%')
  }

  private sourceMenuItems(): MenuElement[] {
    return this.selectableSources().map((source: MediaSourceInstance): MenuElement => ({
      value: (source.id === this.selectedId ? '✓ ' : '') + source.name,
      action: () => {
        this.showSourceMenu = false
        if (source.id !== this.selectedId) void this.select(source.id)
      }
    }))
  }

  private sourceMenuOptions(): MenuOptions {
    const material = buildDetailSheetMaterial(this.materialThickness)
    const options: MenuOptions = {
      placement: Placement.BottomRight,
      borderRadius: 22,
      backgroundColor: material === undefined ? $r('app.color.card_background') : Color.Transparent,
      onDisappear: () => { this.showSourceMenu = false }
    }
    if (material !== undefined) options.systemMaterial = material
    return options
  }

  private handleSearchAction(): void {
    if (this.selectedSource()?.providerType === 'emby') {
      void this.getUIContext().getRouter().pushUrl({ url: 'pages/home/SearchPage',
        params: { sourceId: this.selectedId } })
    } else if (this.selectedSource()?.providerType === 'catvod' || this.selectedSource()?.providerType === 'catnode') {
      void this.getUIContext().getRouter().pushUrl({ url: 'pages/catvod/CatVodBrowserPage',
        params: { sourceId: this.selectedId } })
    } else if (!this.hasServices) void this.reloadSources()
    else this.refreshToken++
  }

  private selectableSources(): MediaSourceInstance[] {
    return this.sources.filter((source: MediaSourceInstance) => HomeSourcePolicy.canSelect(source))
  }

  private supportsHomeSearch(): boolean {
    const type = this.selectedSource()?.providerType
    return type === 'emby' || type === 'catvod' || type === 'catnode'
  }

  private async select(id: string): Promise<void> {
    try { await ActiveSourceStore.select(id) }
    catch (_) { this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('切换失败，请重试')) }
  }
}
