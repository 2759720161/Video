import { common } from '@kit.AbilityKit'
import { ColorMetrics, FrameCallback, Theme } from '@kit.ArkUI'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaItem } from '../../core/media/MediaItem'
import { CatVodProvider } from '../../providers/catvod/CatVodProvider'
import { CatNodeProvider } from '../../providers/catvod/CatNodeProvider'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { CatVodCategory, CatVodPage, CatVodVideo } from '../../providers/catvod/CatVodModels'
import { CatHomeCache, CatHomeSnapshot } from '../../services/media/CatHomeCache'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { ContinueWatchingCard } from '../../components/media/ContinueWatchingCard'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { ProviderIcon } from '../../components/source/ProviderIcon'
import { PageErrorState } from '../../components/common/PageErrorState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { CatNodeSubscriptionCodec } from '../../providers/catvod/CatNodeSubscription'
import { CatNodeSiteSheet } from './CatNodeSiteSheet'
import { CatVodPosterCard } from './CatVodPosterCard'
import { CatVodCategoryTab } from './CatVodCategoryTab'
import { CatVodHomeNavigation } from './CatVodHomeNavigation'
import { CatVodHeroBanner } from './CatVodHeroBanner'
import { CatVodHeroPresentation } from './CatVodHeroPresentation'
import { ResumeFrameStore } from '../../services/media/ResumeFrameStore'
import { PLAYBACK_HISTORY_VERSION_KEY } from '../../store/PlaybackHistoryChangeSignal'
import { ContinueWatchingPresentation } from '../../components/media/ContinueWatchingPresentation'
import { HomeHeroColors } from '../../services/media/HomeHeroColors'
import { HomeHeroSyncTrace } from '../../services/media/HomeHeroSyncTrace'
import { Logger } from '../../utils/Logger'
import { buildDetailToastOptions, buildDetailSheetOptions } from '../../utils/DetailMaterial'
import { getTopSpacerHeight, IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

const cacheLogger = new Logger('CatHomeCache')

@Component
export struct CatVodContent {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop @Watch('refresh') refreshToken: number = 0
  @Prop @Watch('onActiveChanged') isActive: boolean = true
  @Prop embeddedHomeTitle: boolean = false
  onNavigationChanged: (state: CatVodHomeNavigation) => void = () => {}
  onHeroSurfaceChanged: (sourceId: string, updatedAt: number, color: string) => void = () => {}
  @StorageLink('screenWidthVp') screenWidth: number = 360
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PLAYBACK_HISTORY_VERSION_KEY) @Watch('onPlaybackHistoryChanged') historyVersion: number = 0
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
  @State private historyOpeningId: string = ''
  @State private historyError: string = ''
  private historyRequest: number = 0
  private openingHistoryPage: boolean = false
  @State private error: string = ''
  @State private pageError: string = ''
  @State private nodeSites: CatNodeSite[] = []
  @State private nodeSiteKey: string = ''
  @State private showSites: boolean = false
  @State private measuredWidth: number = 0
  private provider: CatVodProvider | null = null
  private generation: number = 0
  private contentRevision: number = 0
  private artworkSnapshot: CatHomeSnapshot | null = null
  private artworkGeneration: number = -1
  private alive: boolean = false
  private refreshPending: boolean = true
  private startupPending: boolean = true
  private refreshing: boolean = false
  private resumeGeneration: number = 0
  private navigationPending: boolean = false
  private navigationTicket: number = 0
  private paginationPending: boolean = false
  private paginationTicket: number = 0
  private viewportHeight: number = 0
  private configurationOpening: boolean = false
  private detailOpening: boolean = false
  private resumeWarmKey: string = ''
  private heroColor: string = ''
  private themeBase: number = 0
  scroller: Scroller = new Scroller()

  aboutToAppear(): void { this.alive = true; this.playingHistory = false; this.historyOpeningId = ''; this.onActiveChanged() }
  onWillApplyTheme(theme: Theme): void {
    const base = ColorMetrics.resourceColor(theme.colors.backgroundPrimary)
    this.themeBase = (0xff000000 | (base.red << 16) | (base.green << 8) | base.blue) >>> 0
    this.updateHeroSurface()
  }
  aboutToDisappear(): void {
    this.alive = false; this.showSites = false; this.generation++; this.resumeGeneration++
    this.historyRequest++; this.playingHistory = false; this.historyOpeningId = ''
    this.cancelNavigationPublication()
    this.cancelPaginationCheck()
    if (this.loading) this.refreshPending = true
    this.refreshing = false; this.loading = false; this.paging = false
  }
  private onActiveChanged(): void {
    if (!this.isActive) {
      this.historyRequest++; this.playingHistory = false; this.historyOpeningId = ''
      this.showSites = false; this.cancelNavigationPublication(); this.cancelPaginationCheck(); return
    }
    if (!this.alive) return
    if (this.refreshPending) {
      if (this.startupPending && this.embeddedHomeTitle) { this.startupPending = false; void this.initializeHome() }
      else void this.refresh()
      return
    }
    this.publishNavigation()
    if (!this.refreshing && this.page > 0) {
      void this.refreshResume()
      if (this.artworkSnapshot !== null) void this.restoreCachedArtwork(this.artworkSnapshot, this.generation, this.contentRevision)
      this.queuePaginationCheck()
    }
  }

  private label(resource: Resource): string {
    return this.getUIContext().getHostContext()!.resourceManager.getStringSync(resource.id)
  }

  private onPlaybackHistoryChanged(): void {
    if (!this.alive || !this.isActive) return
    // Progress commits and exit-frame publication are separate events; refresh both without reloading the catalog.
    cacheLogger.info('history_change refresh')
    void this.refreshResume()
  }

  private publishNavigation(): void {
    if (!this.embeddedHomeTitle || !this.alive || !this.isActive || this.navigationPending) return
    this.navigationPending = true
    const ticket = ++this.navigationTicket
    // Prop watchers/aboutToAppear may run during the parent's render. Publish only after that render.
    this.getUIContext().postFrameCallback(new CatVodNavigationFrame(() => {
      if (ticket !== this.navigationTicket) return
      this.navigationPending = false
      if (!this.alive || !this.isActive || !this.embeddedHomeTitle) return
      const state = new CatVodHomeNavigation()
      state.sourceId = this.source.id; state.sites = this.nodeSites.slice(); state.selectedKey = this.nodeSiteKey
      state.loading = this.loading
      state.heroVisible = this.showHero()
      state.heroSurface = state.heroVisible ? this.heroSurface : ''
      state.provider = this.provider instanceof CatNodeProvider ? this.provider : null
      this.onNavigationChanged(state)
    }))
  }

  private cancelNavigationPublication(): void {
    this.navigationTicket++; this.navigationPending = false
  }

  private async initializeHome(categoryId: string = ''): Promise<void> {
    const generation = ++this.generation
    this.cancelPaginationCheck()
    this.refreshPending = false; this.refreshing = true; this.loading = true; this.paging = false
    this.artworkSnapshot = null
    this.page = 0; this.heroVideos = []; this.heroColor = ''; this.heroSurface = ''; this.error = ''; this.pageError = ''
    this.publishNavigation()
    try {
      const cached = await CatHomeCache.get(this.source, categoryId)
      if (!this.alive || generation !== this.generation) return
      if (cached !== null && cached.categoryId === categoryId) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext
        const provider = this.source.providerType === 'catnode' ?
          CatNodeProvider.fromCachedSites(this.source, context, cached.sites, cached.siteKey) :
          await CatVodProvider.fromSource(this.source)
        if (!this.alive || generation !== this.generation) return
        this.provider = provider; this.nodeSites = cached.sites; this.nodeSiteKey = cached.siteKey
        this.categories = cached.categories; this.categoryId = categoryId; this.keyword = ''; this.query = ''
        const restored = CatHomeCache.artwork(cached)
        const page = new CatVodPage(); page.videos = restored; page.pageCount = cached.pageCount
        this.applyPage(page, 1)
        this.artworkSnapshot = CatHomeCache.needsProxy(cached) ? cached : null
        const revision = this.contentRevision
        cacheLogger.info(`restore_hit category=${categoryId.length > 0} fresh=${CatHomeCache.fresh(cached)} videos=${restored.length} proxy=${CatHomeCache.needsProxy(cached)}`)
        this.loading = false; this.refreshing = false; this.publishNavigation()
        this.queuePaginationCheck()
        void this.refreshResume()
        // Start image preparation immediately, independently of an optional stale-data refresh.
        void this.restoreCachedArtwork(cached, generation, revision)
        if (!CatHomeCache.fresh(cached)) await this.loadHome(true)
        return
      }
      cacheLogger.info(`restore_miss category=${categoryId.length > 0}`)
    } catch (_) { cacheLogger.warn('restore_failed falling_back_to_request') }
    if (!this.alive || generation !== this.generation) return
    this.refreshing = false
    await this.refresh()
  }

  private async restoreCachedArtwork(cached: CatHomeSnapshot, generation: number, revision: number): Promise<void> {
    if (!(this.provider instanceof CatNodeProvider) || !CatHomeCache.needsProxy(cached) || this.artworkGeneration === generation) return
    this.artworkGeneration = generation
    cacheLogger.info(`artwork_prepare_begin revision=${revision}`)
    try {
      const base = await this.provider.cachedArtworkBase()
      if (!this.alive || generation !== this.generation || this.contentRevision !== revision ||
        this.categoryId !== cached.categoryId || this.keyword.length > 0) return
      const restored = CatHomeCache.artwork(cached, base)
      // Preserve pages appended while the runtime was starting; only replace the cached first-page items.
      this.videos = this.videos.map((video: CatVodVideo) =>
        restored.find((item: CatVodVideo) => item.id === video.id) ?? video)
      this.heroVideos = CatVodHeroPresentation.select(restored)
      this.heroVersion++
      this.artworkSnapshot = null
      this.publishNavigation()
      cacheLogger.info(`artwork_prepare_done revision=${revision} videos=${this.videos.length} hero=${this.heroVideos.length}`)
    } catch (_) { cacheLogger.warn(`artwork_prepare_failed revision=${revision}`) }
    finally { if (this.artworkGeneration === generation) this.artworkGeneration = -1 }
  }

  private async refresh(): Promise<void> {
    this.startupPending = false
    await this.loadHome(this.page > 0 && this.keyword.length === 0)
  }

  private async loadHome(preserveVisible: boolean): Promise<void> {
    if (!this.alive || !this.isActive) { this.refreshPending = true; return }
    this.refreshPending = false; this.refreshing = true
    const generation = ++this.generation
    this.cancelPaginationCheck()
    this.loading = !preserveVisible; this.paging = false; this.error = ''; this.pageError = ''
    if (!preserveVisible) { this.page = 0; this.heroColor = ''; this.heroSurface = '' }
    this.publishNavigation()
    try {
      const provider = await ProviderRegistry.get(this.source.id, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!this.alive || generation !== this.generation) return
      if (!(provider instanceof CatVodProvider)) throw new Error('猫源不可用或已停用')
      let sites: CatNodeSite[] = []
      let siteKey = ''
      if (provider instanceof CatNodeProvider) {
        sites = await provider.sites()
        if (!this.alive || generation !== this.generation) return
        siteKey = provider.getSiteKey()
      }
      // Keep the valid catalog usable even if this particular directory's home request fails.
      this.provider = provider; this.nodeSites = sites; this.nodeSiteKey = siteKey
      this.publishNavigation()
      const categories = await provider.getClient().categories()
      if (!this.alive || generation !== this.generation) return
      const categoryId = categories.some((category: CatVodCategory) => category.id === this.categoryId) ? this.categoryId : ''
      const result = await provider.getClient().page(this.keyword.length > 0 ? '' : categoryId, this.keyword, 1)
      if (!this.alive || generation !== this.generation) return
      if (result.page !== 1) throw new Error('来源没有返回请求的分页，请稍后重试')
      this.provider = provider; this.nodeSites = sites; this.nodeSiteKey = siteKey
      this.categories = categories; this.categoryId = categoryId
      this.applyPage(result, 1)
      this.saveHomeCache()
      await this.refreshResume()
    } catch (err) {
      if (this.alive && generation === this.generation) {
        if (preserveVisible) {
          if (this.isActive) this.getUIContext().getPromptAction().showToast(
            buildDetailToastOptions(this.label($r('app.string.cat_home_cache_update_failed'))))
        } else this.error = err instanceof Error ? err.message : this.label($r('app.string.cat_home_read_failed'))
      }
    } finally {
      if (this.alive && generation === this.generation) {
        this.refreshing = false; this.loading = false; this.publishNavigation()
        this.queuePaginationCheck()
        if (this.artworkSnapshot !== null) void this.restoreCachedArtwork(this.artworkSnapshot, generation, this.contentRevision)
      }
    }
  }

  private saveHomeCache(): void {
    if (!this.embeddedHomeTitle || this.keyword.length > 0 || this.page !== 1) return
    const snapshot = new CatHomeSnapshot()
    snapshot.savedAt = Date.now(); snapshot.pageCount = Math.max(1, this.pageCount)
    snapshot.siteKey = this.nodeSiteKey; snapshot.sites = this.nodeSites
    snapshot.categoryId = this.categoryId
    snapshot.categories = this.categories; snapshot.videos = this.videos
    void CatHomeCache.put(this.source, snapshot).catch(() => {})
  }

  /** Returning from playback updates history without replacing the catalog or resetting the hero. */
  private async refreshResume(): Promise<void> {
    const provider = this.provider
    if (!this.alive || provider === null) return
    const generation = this.generation
    const request = ++this.resumeGeneration
    try {
      const resume = await provider.getResumeItems(6)
      if (!this.alive || generation !== this.generation || request !== this.resumeGeneration) return
      if (provider instanceof CatNodeProvider && resume.some((item: MediaItem) =>
        CatHomeCache.rebaseArtwork(item.poster) !== item.poster || CatHomeCache.rebaseArtwork(item.backdrop) !== item.backdrop)) {
        let base = ''
        try { base = await provider.cachedArtworkBase() } catch (_) { cacheLogger.warn('history_artwork_prepare_failed') }
        if (!this.alive || generation !== this.generation || request !== this.resumeGeneration) return
        for (const item of resume) {
          item.poster = CatHomeCache.rebaseArtwork(item.poster, base)
          item.backdrop = CatHomeCache.rebaseArtwork(item.backdrop, base)
        }
      }
      for (const item of resume) {
        const frame = await ResumeFrameStore.resolve(this.getUIContext().getHostContext() as common.UIAbilityContext,
          this.source.id, item.id, item.positionMs)
        if (!this.alive || generation !== this.generation || request !== this.resumeGeneration) return
        if (frame.length > 0) item.backdrop = frame
      }
      if (this.alive && generation === this.generation && request === this.resumeGeneration) {
        this.resume = resume
        cacheLogger.info('history_refresh_done records=%{public}d frames=%{public}d', resume.length,
          resume.filter((item: MediaItem) => (item.backdrop || '').startsWith('file://')).length)
        this.warmRecentResume(provider, resume, generation)
      }
    } catch (_) {}
  }

  private warmRecentResume(provider: CatVodProvider, resume: MediaItem[], generation: number): void {
    if (!(provider instanceof CatNodeProvider) || !this.alive || !this.isActive || this.playingHistory || resume.length === 0) return
    const first = resume[0]
    const key = JSON.stringify([this.source.id, this.source.updatedAt, this.source.configJson, first.id])
    if (key === this.resumeWarmKey) return
    this.resumeWarmKey = key
    const current = (): boolean => this.alive && this.isActive && !this.playingHistory &&
      generation === this.generation && this.provider === provider
    cacheLogger.info('resume_prepare_begin')
    void provider.prepareResume(first.id, current).then(() => {
      if (current()) cacheLogger.info('resume_prepare_done')
      else if (this.resumeWarmKey === key) this.resumeWarmKey = ''
    }).catch(() => {
      if (this.resumeWarmKey === key) this.resumeWarmKey = ''
      cacheLogger.warn('resume_prepare_failed')
    })
  }

  private async loadPage(page: number, generation: number): Promise<void> {
    if (this.provider === null) return
    const result = await this.provider.getClient().page(this.keyword.length > 0 ? '' : this.categoryId, this.keyword, page)
    if (!this.alive || generation !== this.generation) return
    this.applyPage(result, page)
  }

  private applyPage(result: CatVodPage, page: number): void {
    // 防止接口忽略 pg 重复返回第一页，导致“加载更多”永远追加同一批内容。
    if (result.page !== page) throw new Error('来源没有返回请求的分页，请稍后重试')
    const merged = page === 1 ? [] : this.videos.slice()
    const seen = new Set(merged.map((video: CatVodVideo) => video.id))
    for (let i = 0; i < result.videos.length; i++) {
      if (!seen.has(result.videos[i].id)) { merged.push(result.videos[i]); seen.add(result.videos[i].id) }
    }
    // Automatic paging must stop if a source returns an empty or duplicate-only next page.
    const exhausted = page > 1 && merged.length === this.videos.length
    this.videos = merged; this.page = result.page; this.pageCount = exhausted ? result.page : result.pageCount
    this.error = ''; this.pageError = ''
    if (page === 1) {
      this.contentRevision++
      this.artworkSnapshot = null
      this.heroVideos = this.keyword.length === 0 ?
        CatVodHeroPresentation.select(result.videos) : []
      this.heroVersion++
    }
  }

  private async more(): Promise<void> {
    if (!this.alive || !this.isActive || this.refreshing || this.provider === null || this.page < 1 ||
      this.loading || this.paging || this.page >= this.pageCount) return
    const generation = this.generation
    this.paging = true; this.pageError = ''
    try { await this.loadPage(this.page + 1, generation) }
    catch (err) { if (this.alive && generation === this.generation) this.pageError = err instanceof Error ? err.message : this.label($r('app.string.cat_home_read_failed')) }
    finally {
      if (this.alive && generation === this.generation) { this.paging = false; this.queuePaginationCheck() }
    }
  }

  private cancelPaginationCheck(): void { this.paginationTicket++; this.paginationPending = false }

  private queuePaginationCheck(): void {
    if (!this.alive || !this.isActive || this.loading || this.refreshing || this.paging || this.page < 1 ||
      this.videos.length === 0 || this.pageError.length > 0 || this.page >= this.pageCount || this.paginationPending) return
    this.paginationPending = true
    const ticket = ++this.paginationTicket
    const generation = this.generation
    // Read native geometry after rendering; repeated scroll/resize events share one check per frame.
    this.getUIContext().postFrameCallback(new CatVodPaginationFrame(() => {
      if (ticket !== this.paginationTicket) return
      this.paginationPending = false
      if (!this.alive || !this.isActive || generation !== this.generation || this.loading || this.refreshing ||
        this.paging || this.pageError.length > 0 || this.page >= this.pageCount || this.viewportHeight <= 0) return
      try {
        // Index 1 is the group containing the category header and poster content, in List coordinates.
        const content = this.scroller.getItemRect(1)
        if (Number.isFinite(content.y) && Number.isFinite(content.height) && content.height > 0 &&
          content.y + content.height - this.viewportHeight <= Math.max(240, this.viewportHeight * 0.5)) void this.more()
      } catch (_) { /* The controller can be unbound before the first native layout. */ }
    }))
  }

  private choose(id: string): void {
    if (id === this.categoryId && this.keyword.length === 0) return
    this.categoryId = id; this.query = ''; this.keyword = ''; this.videos = []
    this.scroller.scrollEdge(Edge.Top)
    if (this.embeddedHomeTitle) void this.initializeHome(id)
    else void this.refresh()
  }

  private search(): void {
    this.keyword = this.query.trim(); this.videos = []
    this.scroller.scrollEdge(Edge.Top)
    void this.refresh()
  }

  private async chooseNodeSite(key: string): Promise<void> {
    this.showSites = false
    if (this.loading || !(this.provider instanceof CatNodeProvider) || !this.nodeSites.some((site: CatNodeSite) => site.key === key)) return
    if (key === 'baseset') {
      if (!this.alive || !this.isActive || this.configurationOpening) return
      this.configurationOpening = true
      try {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/catvod/CatNodeConfigurationPage',
          params: { sourceId: this.source.id } })
      } catch (error) {
        if (this.alive && this.isActive) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(
          error instanceof Error ? error.message : this.label($r('app.string.cat_config_unavailable'))))
      } finally { this.configurationOpening = false }
      return
    }
    if (key === this.nodeSiteKey) return
    const generation = ++this.generation
    this.loading = true
    try {
      await this.provider.selectSite(key)
      if (!this.alive || generation !== this.generation) return
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
    Stack() {
      List({ scroller: this.scroller }) {
        ListItem() { this.BeforeCategories() }
        ListItemGroup({ header: this.CategoryTabs() }) {
          ListItem() { this.CategoryContent() }
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 1200 })
        // Native sticky headers respect this inset, including the status area and MINI title bar.
        .contentStartOffset(getTopSpacerHeight(this.topSafeHeight)).sticky(StickyStyle.Header)
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        .onDidScroll(() => this.queuePaginationCheck())
        .onReachEnd(() => this.queuePaginationCheck())
        .onAreaChange((_oldArea: Area, area: Area) => {
          const width = Number(area.width)
          if (Number.isFinite(width) && width > 40 && Math.abs(width - this.measuredWidth) > 1) this.measuredWidth = width
          const height = Number(area.height)
          if (Number.isFinite(height) && height > 0) this.viewportHeight = height
          this.queuePaginationCheck()
        })
      if (this.loading) {
        Column() {
          PageLoadingState({ title: this.label($r('app.string.cat_home_loading')) })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center).hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').backgroundColor(this.heroBackground())
      .bindSheet($$this.showSites, this.SourceSheet(), buildDetailSheetOptions(this.materialThickness, {
        height: SheetSize.LARGE, dragBar: true, showClose: true,
        title: { title: this.label($r('app.string.cat_home_choose_source')) },
        backgroundColor: $r('app.color.card_background'),
        onDisappear: () => { this.showSites = false }
      }))
  }

  @Builder
  private BeforeCategories(): void {
    Column({ space: 16 }) {
      if (this.showHero()) {
        // The List supplies the title inset once for both the hero and the pinned category row.
        CatVodHeroBanner({ items: this.heroVideos, version: this.heroVersion,
          topInset: 0, viewportWidth: this.viewportWidth(), isActive: this.isActive,
          onColorChanged: (color: string) => this.setHeroColor(color),
          onOpen: (video: CatVodVideo) => this.detail(video) })
      } else if (!this.embeddedHomeTitle) {
        this.SourceHeader()
        Search({ value: this.query, placeholder: $r('app.string.catvod_search_hint') })
          .height(46).width('100%').backgroundColor($r('app.color.card_background'))
          .enabled(!this.loading)
          .onChange((value: string) => {
            this.query = value
            if (value.trim().length === 0 && this.keyword.length > 0) this.search()
          }).onSubmit(() => this.search())
      }
    }.width('100%').padding({ left: this.showHero() ? 0 : 20, right: this.showHero() ? 0 : 20,
      top: this.showHero() ? 0 : 12, bottom: this.showHero() ? 20 : (this.embeddedHomeTitle ? 0 : 16) })
  }

  @Builder
  private CategoryTabs(): void {
    // Do not create a lone synthetic tab while the initial catalog/cache is still pending.
    if (this.page > 0 || this.categories.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          this.CategoryButton('', this.label(this.source.providerType === 'catnode' ?
            $r('app.string.cat_home_recommended') : $r('app.string.cat_home_all')))
          ForEach(this.categories, (category: CatVodCategory) => this.CategoryButton(category.id, category.name),
            (category: CatVodCategory) => category.id)
        }.padding({ left: 4, right: 4, top: 4, bottom: 4 })
      }.width('100%').padding({ left: 20, right: 20 })
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).clip(false)
    }
  }

  private posterVideos(): CatVodVideo[] {
    return this.showHero() ? CatVodHeroPresentation.belowHero(this.videos, this.heroVideos) : this.videos
  }

  @Builder
  private CategoryContent(): void {
    Column({ space: 24 }) {
      if (this.error.length > 0) {
        PageErrorState({ title: this.label($r('app.string.cat_home_unavailable')), message: this.error,
          onRetry: () => { void this.refresh() } })
      } else if (!this.loading) {
        if (this.keyword.length === 0 && this.categoryId.length === 0 && this.resume.length > 0) this.ContinueWatching()
        if (this.posterVideos().length > 0 || this.videos.length === 0) this.LibraryHeader()
        if (this.posterVideos().length > 0) {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(this.posterVideos(), (video: CatVodVideo, index: number) => {
              CatVodPosterCard({ title: video.name, remarks: video.remarks, poster: video.poster,
                cardWidth: this.cardWidth(), scaleOnlyPress: this.embeddedHomeTitle, onOpen: () => this.detail(video) })
                .margin({ right: (index + 1) % this.columns() === 0 ? 0 : 12, bottom: 18 })
            }, (video: CatVodVideo, _index: number) => CatVodHeroPresentation.posterKey(video))
          }
          .width('100%')
        } else if (this.videos.length === 0) {
          PageEmptyState({ icon: $r('sys.symbol.magnifyingglass'),
            title: this.label($r('app.string.catvod_no_results')),
            message: this.label(this.keyword.length > 0 ? $r('app.string.cat_home_search_empty') : $r('app.string.cat_home_browse_empty')),
            minHeight: 220 })
        }
        this.PageFooter()
      }
    }.width('100%').padding({ left: 20, right: 20, top: 24, bottom: this.bottomSafeHeight + 120 })
      .alignItems(HorizontalAlign.Start)
      .onAreaChange(() => this.queuePaginationCheck())
  }

  private showHero(): boolean {
    return this.embeddedHomeTitle && !this.loading && this.error.length === 0 &&
      this.keyword.length === 0 && this.heroVideos.length > 0
  }

  private viewportWidth(): number { return this.measuredWidth || Math.min(1200, this.screenWidth) }

  private setHeroColor(color: string): void {
    if (!this.alive || !this.isActive || !this.showHero() || this.heroColor === color) return
    this.heroColor = color; this.updateHeroSurface()
  }

  private updateHeroSurface(): void {
    this.heroSurface = HomeHeroColors.surface(this.heroColor, this.themeBase)
    HomeHeroSyncTrace.applied('cat', 'content', this.heroSurface)
    if (this.embeddedHomeTitle && this.alive && this.isActive) {
      this.onHeroSurfaceChanged(this.source.id, this.source.updatedAt, this.heroSurface)
    }
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
      MediaSectionHeader({ title: this.label($r('app.string.catvod_continue')), chevronAction: true,
        actionText: this.label($r('app.string.continue_watching_title')), onAction: () => { void this.openContinueWatching() } })
      if (this.historyError.length > 0) {
        Text(this.historyError).fontSize(13).fontColor($r('app.color.text_error')).maxLines(3).width('100%')
      }
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.resume, (item: MediaItem) => {
            ContinueWatchingCard({ title: item.title, subtitle: item.subtitle, artworkUrl: item.backdrop || item.poster,
              positionMs: item.positionMs, durationMs: item.durationMs, scaleOnlyPress: this.embeddedHomeTitle,
              loading: this.playingHistory && this.historyOpeningId === item.id,
              cardWidth: ContinueWatchingPresentation.width(this.contentWidth()),
              onCardClick: () => { void this.playHistory(item) } })
              .enabled(!this.playingHistory)
          }, (item: MediaItem) => JSON.stringify(['resume', item.id, item.backdrop, item.poster,
            item.title, item.subtitle, item.positionMs, item.durationMs]))
        }
      }.width('100%').align(Alignment.TopStart).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }.width('100%')
  }

  private async openContinueWatching(): Promise<void> {
    if (this.openingHistoryPage || this.playingHistory) return
    this.openingHistoryPage = true
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/local/ContinueWatchingPage',
        params: { view: 'continue', sourceId: this.source.id,
          spiderKey: this.source.providerType === 'catnode' ? this.nodeSiteKey : '',
          scopeName: this.nodeSites.find((site: CatNodeSite) => site.key === this.nodeSiteKey)?.name || this.source.name } })
    } catch (_) {
      this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(this.label($r('app.string.continue_watching_open_failed'))))
    } finally { this.openingHistoryPage = false }
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
  private PageFooter(): void {
    if (this.pageError.length > 0) {
      Column({ space: 10 }) {
        Text(this.pageError).fontSize(13).fontColor($r('app.color.text_muted')).maxLines(3).textAlign(TextAlign.Center)
        Button($r('app.string.cat_home_retry')).height(40).fontSize(14)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent_blue'))
          .onClick(() => { void this.more() })
      }.width('100%').padding(12)
    } else if (this.page < this.pageCount) {
      Row({ space: 8 }) {
        if (this.paging) {
          LoadingProgress().width(18).height(18).color($r('app.color.accent_blue'))
          Text($r('app.string.catvod_loading_more')).fontSize(14).fontColor($r('app.color.text_muted'))
        }
      }.width('100%').height(32).justifyContent(FlexAlign.Center)
    } else if (this.videos.length > 0) {
      Text($r('app.string.cat_home_end')).fontSize(12).fontColor($r('app.color.text_hint'))
        .width('100%').textAlign(TextAlign.Center).padding(12)
    }
  }

  @Builder
  private CategoryButton(id: string, name: string): void {
    CatVodCategoryTab({ name: name, selected: id === this.categoryId && this.keyword.length === 0,
      selectionEnabled: !this.loading, materialThickness: this.materialThickness, onSelect: () => this.choose(id) })
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
    void this.openDetail(video)
  }

  private async openDetail(video: CatVodVideo): Promise<void> {
    if (!this.alive || !this.isActive || this.detailOpening) return
    const generation = this.generation; const sourceId = this.source.id; const provider = this.provider
    const current = (): boolean => this.alive && this.isActive && generation === this.generation &&
      sourceId === this.source.id && provider === this.provider
    this.detailOpening = true
    try {
      let searchOnly = video.searchOnly
      if (!searchOnly && provider instanceof CatNodeProvider && video.name.trim().length > 0) {
        // Cached cards/catalogs may predate the intent flag. Resolve before entering a page,
        // instead of pushing detail and replacing it during its enter animation.
        try {
          const sites = await provider.sites()
          if (!current()) return
          searchOnly = sites.some((site: CatNodeSite) => site.key === provider.getSiteKey() && site.indexOnly)
        } catch (_) {
          if (!current()) return
          cacheLogger.warn('detail_intent_lookup_failed')
        }
      }
      if (!current()) return
      if (searchOnly && video.name.trim().length > 0) {
        cacheLogger.info('detail_route search=1')
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/home/SearchPage',
          params: { sourceId: sourceId, keyword: video.name } })
      } else {
        cacheLogger.info('detail_route search=0')
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/catvod/CatVodDetailPage',
          params: { sourceId: sourceId, videoId: video.id, title: video.name } })
      }
    } catch (_) {
      if (current()) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(
        this.label($r('app.string.cat_detail_load_failed'))))
    } finally { this.detailOpening = false }
  }


  private async playHistory(item: MediaItem): Promise<void> {
    if (this.playingHistory || !this.alive || !this.isActive) return
    const request = ++this.historyRequest
    const generation = this.generation
    const sourceId = this.source.id
    const current = (): boolean => this.alive && this.isActive && request === this.historyRequest &&
      generation === this.generation && sourceId === this.source.id
    this.playingHistory = true; this.historyOpeningId = item.id; this.historyError = ''
    try {
      await ProviderPlaybackLauncher.openById(this.getUIContext(), sourceId, item.id, item.positionMs, false, current)
    } catch (err) {
      if (current()) {
        this.historyError = (err instanceof Error ? err.message : this.label($r('app.string.continue_watching_failed'))).slice(0, 240)
        this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(this.historyError))
      }
    } finally {
      if (request === this.historyRequest) { this.playingHistory = false; this.historyOpeningId = '' }
    }
  }
}

class CatVodNavigationFrame extends FrameCallback {
  private publish: () => void
  constructor(publish: () => void) { super(); this.publish = publish }
  onFrame(): void { this.publish() }
}

class CatVodPaginationFrame extends FrameCallback {
  private check: () => void
  constructor(check: () => void) { super(); this.check = check }
  onFrame(): void { this.check() }
}
