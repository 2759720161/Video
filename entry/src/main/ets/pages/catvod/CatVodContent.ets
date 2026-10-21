import { common } from '@kit.AbilityKit'
import { ColorMetrics, Theme } from '@kit.ArkUI'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaItem } from '../../core/media/MediaItem'
import { CatVodProvider } from '../../providers/catvod/CatVodProvider'
import { CatNodeProvider } from '../../providers/catvod/CatNodeProvider'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { CatVodCategory, CatVodVideo } from '../../providers/catvod/CatVodModels'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { ContinueWatchingCard } from '../../components/media/ContinueWatchingCard'
import { ProviderIcon } from '../../components/source/ProviderIcon'
import { PageErrorState } from '../../components/common/PageErrorState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { CatNodeSubscriptionCodec } from '../../providers/catvod/CatNodeSubscription'
import { CatNodeSiteSheet } from './CatNodeSiteSheet'
import { CatVodPosterCard } from './CatVodPosterCard'
import { CatVodHomeNavigation } from './CatVodHomeNavigation'
import { CatVodHeroBanner } from './CatVodHeroBanner'
import { CatVodHeroPresentation } from './CatVodHeroPresentation'
import { HomeHeroColors } from '../../services/media/HomeHeroColors'
import { buildDetailToastOptions, buildDetailSheetOptions } from '../../utils/DetailMaterial'
import { getTopSpacerHeight, IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

@Component
export struct CatVodContent {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop @Watch('refresh') refreshToken: number = 0
  @Prop @Watch('onActiveChanged') isActive: boolean = true
  @Prop embeddedHomeTitle: boolean = false
  onNavigationChanged: (state: CatVodHomeNavigation) => void = () => {}
  @StorageLink('screenWidthVp') screenWidth: number = 360
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @State private categories: CatVodCategory[] = []
  @State private videos: CatVodVideo[] = []
  @State private heroVideos: CatVodVideo[] = []
  @State private heroVersion: number = 0
  @State private heroSurface: string = ''
  @State private resume: MediaItem[] = []
  @State private categoryId: string = ''
  @State private query: string = ''
  @State private keyword: string = ''
  @State private page: number = 0
  @State private pageCount: number = 1
  @State private loading: boolean = true
  @State private paging: boolean = false
  @State private playingHistory: boolean = false
  @State private error: string = ''
  @State private pageError: string = ''
  @State private nodeSites: CatNodeSite[] = []
  @State private nodeSiteKey: string = ''
  @State private showSites: boolean = false
  @State private measuredWidth: number = 0
  private provider: CatVodProvider | null = null
  private generation: number = 0
  private alive: boolean = false
  private heroColor: string = ''
  private themeBase: number = 0
  scroller: Scroller = new Scroller()

  aboutToAppear(): void { this.alive = true; this.playingHistory = false; void this.refresh() }
  onWillApplyTheme(theme: Theme): void {
    const base = ColorMetrics.resourceColor(theme.colors.backgroundPrimary)
    this.themeBase = (0xff000000 | (base.red << 16) | (base.green << 8) | base.blue) >>> 0
    this.updateHeroSurface()
  }
  aboutToDisappear(): void { this.alive = false; this.showSites = false; this.generation++ }
  private onActiveChanged(): void {
    if (this.isActive) void this.refresh()
    else { this.generation++; this.showSites = false; this.loading = false; this.paging = false }
  }

  private label(resource: Resource): string {
    return this.getUIContext().getHostContext()!.resourceManager.getStringSync(resource.id)
  }

  private publishNavigation(): void {
    if (!this.embeddedHomeTitle || !this.alive || !this.isActive) return
    const state = new CatVodHomeNavigation()
    state.sourceId = this.source.id; state.sites = this.nodeSites.slice(); state.selectedKey = this.nodeSiteKey
    state.loading = this.loading
    state.heroVisible = this.showHero()
    state.heroSurface = state.heroVisible ? this.heroSurface : ''
    state.provider = this.provider instanceof CatNodeProvider ? this.provider : null
    this.onNavigationChanged(state)
  }

  private async refresh(): Promise<void> {
    if (!this.isActive) return
    const generation = ++this.generation
    this.loading = true; this.paging = false; this.error = ''; this.pageError = ''; this.page = 0
    this.heroColor = ''; this.heroSurface = ''
    this.publishNavigation()
    try {
      const provider = await ProviderRegistry.get(this.source.id, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!this.alive || generation !== this.generation) return
      if (!(provider instanceof CatVodProvider)) throw new Error('猫源不可用或已停用')
      this.provider = provider
      if (provider instanceof CatNodeProvider) {
        const sites = await provider.sites()
        if (!this.alive || generation !== this.generation) return
        this.nodeSites = sites; this.nodeSiteKey = provider.getSiteKey()
      } else { this.nodeSites = []; this.nodeSiteKey = '' }
      this.publishNavigation()
      const categories = await provider.getClient().categories()
      if (!this.alive || generation !== this.generation) return
      this.categories = categories
      if (!categories.some((category: CatVodCategory) => category.id === this.categoryId)) this.categoryId = ''
      await this.loadPage(1, generation)
      try {
        const resume = await provider.getResumeItems(6)
        if (this.alive && generation === this.generation) this.resume = resume
      } catch (_) {}
    } catch (err) {
      if (this.alive && generation === this.generation) this.error = err instanceof Error ? err.message : this.label($r('app.string.cat_home_read_failed'))
    } finally {
      if (this.alive && generation === this.generation) { this.loading = false; this.publishNavigation() }
    }
  }

  private async loadPage(page: number, generation: number): Promise<void> {
    if (this.provider === null) return
    const result = await this.provider.getClient().page(this.keyword.length > 0 ? '' : this.categoryId, this.keyword, page)
    if (!this.alive || generation !== this.generation) return
    // 防止接口忽略 pg 重复返回第一页，导致“加载更多”永远追加同一批内容。
    if (result.page !== page) throw new Error('来源没有返回请求的分页，请稍后重试')
    const merged = page === 1 ? [] : this.videos.slice()
    const seen = new Set(merged.map((video: CatVodVideo) => video.id))
    for (let i = 0; i < result.videos.length; i++) {
      if (!seen.has(result.videos[i].id)) { merged.push(result.videos[i]); seen.add(result.videos[i].id) }
    }
    this.videos = merged; this.page = result.page; this.pageCount = result.pageCount; this.error = ''; this.pageError = ''
    if (page === 1) {
      this.heroVideos = this.keyword.length === 0 && this.categoryId.length === 0 ?
        CatVodHeroPresentation.select(result.videos) : []
      this.heroVersion++
    }
  }

  private async more(): Promise<void> {
    if (this.loading || this.paging || this.page >= this.pageCount) return
    const generation = this.generation
    this.paging = true; this.pageError = ''
    try { await this.loadPage(this.page + 1, generation) }
    catch (err) { if (this.alive && generation === this.generation) this.pageError = err instanceof Error ? err.message : this.label($r('app.string.cat_home_read_failed')) }
    finally { if (this.alive && generation === this.generation) this.paging = false }
  }

  private choose(id: string): void {
    if (id === this.categoryId && this.keyword.length === 0) return
    this.categoryId = id; this.query = ''; this.keyword = ''; this.videos = []
    this.scroller.scrollEdge(Edge.Top)
    void this.refresh()
  }

  private search(): void {
    this.keyword = this.query.trim(); this.videos = []
    this.scroller.scrollEdge(Edge.Top)
    void this.refresh()
  }

  private async chooseNodeSite(key: string): Promise<void> {
    this.showSites = false
    if (this.loading || !(this.provider instanceof CatNodeProvider) || !this.nodeSites.some((site: CatNodeSite) => site.key === key)) return
    if (key === this.nodeSiteKey) return
    const generation = ++this.generation
    this.loading = true
    try {
      await this.provider.selectSite(key)
      if (!this.alive || !this.isActive || generation !== this.generation) return
      this.categoryId = ''; this.query = ''; this.keyword = ''; this.videos = []; this.resume = []
      this.categories = []; this.nodeSiteKey = key; this.scroller.scrollEdge(Edge.Top)
      await this.refresh()
    } catch (error) {
      if (this.alive && generation === this.generation) {
        this.loading = false
        this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(error instanceof Error ? error.message :
          this.label($r('app.string.cat_home_switch_failed'))))
      }
    }
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        if (this.showHero()) {
          CatVodHeroBanner({ items: this.heroVideos, version: this.heroVersion,
            topInset: getTopSpacerHeight(this.topSafeHeight), viewportWidth: this.viewportWidth(), isActive: this.isActive,
            surfaceColor: this.heroBackground(), onColorChanged: (color: string) => this.setHeroColor(color),
            onOpen: (video: CatVodVideo) => this.detail(video) })
        }
        Column({ space: 24 }) {
          Column({ space: 16 }) {
            if (!this.embeddedHomeTitle) this.SourceHeader()
            Search({ value: this.query, placeholder: $r('app.string.catvod_search_hint') })
              .height(46).width('100%').backgroundColor($r('app.color.card_background'))
              .enabled(!this.loading)
              .onChange((value: string) => {
                this.query = value
                if (value.trim().length === 0 && this.keyword.length > 0) this.search()
              }).onSubmit(() => this.search())
            Scroll() {
              Row({ space: 8 }) {
                this.CategoryButton('', this.label(this.source.providerType === 'catnode' ?
                  $r('app.string.cat_home_recommended') : $r('app.string.cat_home_all')))
                ForEach(this.categories, (category: CatVodCategory) => this.CategoryButton(category.id, category.name),
                  (category: CatVodCategory) => category.id)
              }
            }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          }.width('100%')
          if (this.loading) {
            this.LoadingGrid()
          } else if (this.error.length > 0) {
            PageErrorState({ title: this.label($r('app.string.cat_home_unavailable')), message: this.error,
              onRetry: () => { void this.refresh() } })
          } else {
            if (this.keyword.length === 0 && this.categoryId.length === 0 && this.resume.length > 0) this.ContinueWatching()
            this.LibraryHeader()
            if (this.videos.length > 0) {
              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                ForEach(this.videos, (video: CatVodVideo, index: number) => {
                  CatVodPosterCard({ title: video.name, remarks: video.remarks, poster: video.poster,
                    cardWidth: this.cardWidth(), onOpen: () => this.detail(video) })
                    .margin({ right: (index + 1) % this.columns() === 0 ? 0 : 12, bottom: 18 })
                }, (video: CatVodVideo) => video.id)
              }.width('100%')
            } else {
              PageEmptyState({ icon: $r('sys.symbol.magnifyingglass'),
                title: this.label($r('app.string.catvod_no_results')),
                message: this.label(this.keyword.length > 0 ? $r('app.string.cat_home_search_empty') : $r('app.string.cat_home_browse_empty')),
                minHeight: 220 })
            }
            this.PageFooter()
          }
        }.width('100%')
          .padding({ left: 20, right: 20, top: this.showHero() ? 20 : getTopSpacerHeight(this.topSafeHeight) + 12,
            bottom: this.bottomSafeHeight + 120 }).alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxWidth: 1200 })
        .onAreaChange((_oldArea: Area, area: Area) => {
          const width = Number(area.width)
          if (Number.isFinite(width) && width > 40 && Math.abs(width - this.measuredWidth) > 1) this.measuredWidth = width
        })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      .backgroundColor(this.heroBackground()).animation({ duration: 500, curve: Curve.EaseInOut })
      .bindSheet($$this.showSites, this.SourceSheet(), buildDetailSheetOptions(this.materialThickness, {
        height: SheetSize.LARGE, dragBar: true, showClose: true,
        title: { title: this.label($r('app.string.cat_home_choose_source')) },
        backgroundColor: $r('app.color.card_background'),
        onDisappear: () => { this.showSites = false }
      }))
  }

  private showHero(): boolean {
    return this.embeddedHomeTitle && !this.loading && this.error.length === 0 &&
      this.keyword.length === 0 && this.categoryId.length === 0 && this.heroVideos.length > 0
  }

  private viewportWidth(): number { return this.measuredWidth || Math.min(1200, this.screenWidth) }

  private setHeroColor(color: string): void {
    if (!this.alive || !this.isActive || !this.showHero()) return
    this.heroColor = color; this.updateHeroSurface()
  }

  private updateHeroSurface(): void {
    this.heroSurface = HomeHeroColors.surface(this.heroColor, this.themeBase)
    this.publishNavigation()
  }

  private heroBackground(): ResourceColor {
    return this.showHero() && this.heroSurface.length > 0 ? this.heroSurface : $r('app.color.page_background')
  }

  @Builder
  private SourceHeader(): void {
      Row({ space: 14 }) {
        Row() {
          ProviderIcon({ providerType: this.source.providerType, imageUri: this.subscriptionIcon(), iconSize: 26 })
        }.width(50).height(50).borderRadius(16).justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.cat_home_selected_surface'))
        Column({ space: 5 }) {
          Text(this.currentSiteName()).fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
          Text(this.nodeSites.length > 0 ? this.source.name : this.label($r('app.string.cat_home_discover')))
            .fontSize(12).fontColor($r('app.color.text_muted')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.nodeSites.length > 1) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              Text($r('app.string.cat_home_switch')).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent_blue'))
              SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(11).fontColor([$r('app.color.accent_blue')])
            }.padding({ left: 12, right: 12, top: 10, bottom: 10 })
          }.height(40).backgroundColor($r('app.color.cat_home_selected_surface')).borderRadius(20)
            .enabled(!this.loading).accessibilityText($r('app.string.cat_home_choose_source'))
            .onClick(() => { this.showSites = true })
        }
      }.width('100%')
  }

  @Builder
  private SourceSheet(): void {
    CatNodeSiteSheet({ sites: this.nodeSites, selectedKey: this.nodeSiteKey,
      onSelect: (key: string) => { void this.chooseNodeSite(key) } })
  }

  @Builder
  private ContinueWatching(): void {
    Column({ space: 14 }) {
      Text($r('app.string.catvod_continue')).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.resume, (item: MediaItem) => {
            ContinueWatchingCard({ title: item.title, subtitle: item.subtitle, artworkUrl: item.backdrop || item.poster,
              positionMs: item.positionMs, durationMs: item.durationMs,
              cardWidth: Math.min(260, this.contentWidth() * 0.72),
              onCardClick: () => { void this.playHistory(item) } })
              .enabled(!this.playingHistory)
          }, (item: MediaItem) => 'resume:' + item.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }.width('100%')
  }

  @Builder
  private LibraryHeader(): void {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.keyword.length > 0 ? $r('app.string.cat_home_search_results') : this.categoryName())
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.keyword.length > 0) {
          Text('“' + this.keyword + '”').fontSize(12).fontColor($r('app.color.text_muted'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.keyword.length > 0) {
        Button($r('app.string.cat_home_clear_search')).fontSize(13).height(36)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent_blue'))
          .onClick(() => { this.query = ''; this.search() })
      }
    }.width('100%')
  }

  @Builder
  private LoadingGrid(): void {
    Column({ space: 18 }) {
      Row({ space: 10 }) {
        LoadingProgress().width(18).height(18).color($r('app.color.accent_blue'))
        Text($r('app.string.cat_home_loading')).fontSize(13).fontColor($r('app.color.text_muted'))
      }.width('100%')
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
          Column({ space: 10 }) {
            Column().width(this.cardWidth()).height(this.cardWidth() * 1.45).borderRadius(12)
              .backgroundColor($r('app.color.skeleton_background'))
            Column().width(this.cardWidth() * 0.7).height(12).borderRadius(6)
              .backgroundColor($r('app.color.skeleton_background'))
          }.width(this.cardWidth()).alignItems(HorizontalAlign.Start)
            .margin({ right: (index + 1) % this.columns() === 0 ? 0 : 12, bottom: 20 })
        }, (index: number) => String(index))
      }.width('100%').accessibilityLevel('no-hide-descendants')
    }.width('100%')
  }

  @Builder
  private PageFooter(): void {
    if (this.pageError.length > 0) {
      Column({ space: 10 }) {
        Text(this.pageError).fontSize(13).fontColor($r('app.color.text_muted')).maxLines(3).textAlign(TextAlign.Center)
        Button($r('app.string.cat_home_retry')).height(40).fontSize(14)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent_blue'))
          .onClick(() => { void this.more() })
      }.width('100%').padding(12)
    } else if (this.page < this.pageCount) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          if (this.paging) LoadingProgress().width(18).height(18).color($r('app.color.accent_blue'))
          Text(this.paging ? $r('app.string.catvod_loading_more') : $r('app.string.catvod_load_more'))
            .fontSize(14).fontColor($r('app.color.accent_blue'))
        }.justifyContent(FlexAlign.Center)
      }.width('100%').height(48).borderRadius(16).enabled(!this.paging)
        .backgroundColor($r('app.color.card_background')).onClick(() => { void this.more() })
    } else if (this.videos.length > 0) {
      Text($r('app.string.cat_home_end')).fontSize(12).fontColor($r('app.color.text_hint'))
        .width('100%').textAlign(TextAlign.Center).padding(12)
    }
  }

  @Builder
  private CategoryButton(id: string, name: string): void {
    Button(name).height(38).fontSize(14).padding({ left: 18, right: 18 })
      .fontWeight(id === this.categoryId && this.keyword.length === 0 ? FontWeight.Medium : FontWeight.Regular)
      .backgroundColor(id === this.categoryId && this.keyword.length === 0 ? $r('app.color.cat_home_selected_surface') : $r('app.color.card_background'))
      .fontColor(id === this.categoryId && this.keyword.length === 0 ? $r('app.color.accent_blue') : $r('app.color.text_muted'))
      .enabled(!this.loading)
      .onClick(() => this.choose(id))
  }

  private contentWidth(): number { return Math.max(160, (this.measuredWidth || Math.min(1200, this.screenWidth)) - 40) }
  private columns(): number { return Math.max(2, Math.min(6, Math.floor((this.contentWidth() + 12) / 108))) }
  private cardWidth(): number { return Math.floor((this.contentWidth() - 12 * (this.columns() - 1)) / this.columns() * 100) / 100 }
  private currentSiteName(): string {
    return this.nodeSites.find((site: CatNodeSite) => site.key === this.nodeSiteKey)?.name ?? this.source.name
  }
  private categoryName(): string {
    return this.categories.find((category: CatVodCategory) => category.id === this.categoryId)?.name ??
      this.label(this.source.providerType === 'catnode' ? $r('app.string.cat_home_recommended') : $r('app.string.cat_home_all'))
  }
  private subscriptionIcon(): string {
    if (this.source.providerType !== 'catnode') return ''
    const icon = CatNodeSubscriptionCodec.decode(this.source.configJson).iconUri
    return icon.startsWith('file://') ? icon : ''
  }

  private detail(video: CatVodVideo): void {
    void this.getUIContext().getRouter().pushUrl({ url: 'pages/catvod/CatVodDetailPage',
      params: { sourceId: this.source.id, videoId: video.id } })
  }


  private async playHistory(item: MediaItem): Promise<void> {
    if (this.playingHistory) return
    this.playingHistory = true
    try { await ProviderPlaybackLauncher.openById(this.getUIContext(), this.source.id, item.id, item.positionMs) }
    catch (err) { if (this.alive) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(err instanceof Error ? err.message : '无法打开播放')) }
    finally { if (this.alive) this.playingHistory = false }
  }
}
