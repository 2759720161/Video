import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit'
import { SearchTitleMaterialModifier, DetailTitleButtonMaterialModifier, buildDetailToastOptions, buildDetailSheetMaterial, buildDetailSheetOptions } from '../../utils/DetailMaterial'
import { buildEmbyDetailRouteParams } from '../../providers/emby/EmbyDetailRoute'
import { SearchResultCard } from '../../components/media/SearchResultCard'
import { SourceMenuEntry, SourceSelectionMenu } from '../../components/common/SourceSelectionMenu'
import { buildSourceSelectionMenuOptions } from '../../utils/SourceSelectionMenuStyle'
import { PageErrorState } from '../../components/common/PageErrorState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { MediaSearchSession } from '../../services/media/MediaSearchSession'
import { MEDIA_SEARCH_ALL, MediaSearchAggregate, MediaSearchAggregateState } from '../../services/media/MediaSearchAggregate'
import { MediaSearchScopeSelection } from '../../services/media/MediaSearchScopeSelection'
import { CatNodeSearchUnavailableError } from '../../providers/catvod/CatNodeClient'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { MediaSearchItem, MediaSearchPresentation } from '../../services/media/MediaSearchPresentation'
import { PreferencesStore } from '../../store/PreferencesStore'
import { buildMediaDetailTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL,
  getTopSpacerHeight, IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'

@Entry
@Component
struct SearchPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidth: number = 360
  @State private query: string = ''
  @State private submittedQuery: string = ''
  @State private items: MediaSearchItem[] = []
  @State private displayedItems: MediaSearchItem[] = []
  @State private initializing: boolean = true
  @State private initialSearchPending: boolean = false
  @State private searching: boolean = false
  @State private paging: boolean = false
  @State private error: string = ''
  @State private pageError: string = ''
  @State private history: string[] = []
  @State private managingHistory: boolean = false
  @State private scopeName: string = ''
  @State private scopes: CatNodeSite[] = []
  @State private aggregateMode: boolean = false
  @State private aggregateState: MediaSearchAggregateState = new MediaSearchAggregateState()
  @State private aggregateStopped: boolean = false
  @State private selectedScopeKeys: string[] = []
  @State private draftScopeKeys: string[] = []
  @State private scopeFilter: string = ''
  @State private showScopeSettings: boolean = false
  @State private showDirectoryMenu: boolean = false
  @State private scopeSaving: boolean = false
  @State private scopeSaveError: string = ''
  @State private listMode: boolean = false
  @State private order: string = 'default'
  @State private page: number = 0
  @State private pageCount: number = 1
  @State private measuredWidth: number = 0
  @State private visibleLimit: number = 60
  private sourceId: string = ''
  private pageVisible: boolean = false
  private seedTicket: number = 0
  private seedTimer: number = -1
  private session: MediaSearchSession | null = null
  private historyKey: string = ''
  private generation: number = 0
  private initGeneration: number = 0
  private alive: boolean = true
  private scroller: Scroller = new Scroller()
  private aggregate: MediaSearchAggregate | null = null

  aboutToAppear(): void {
    this.alive = true
    this.pageVisible = false
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') this.sourceId = params['sourceId'] as string
    const keyword = params !== undefined && typeof params['keyword'] === 'string' ? params['keyword'] as string : ''
    this.query = MediaSearchPresentation.normalize(keyword)
    this.initialSearchPending = this.query.length > 0
    void this.initialize()
  }

  onPageShow(): void {
    this.pageVisible = true
    hilog.info(0, 'MediaSearch', 'seed_visible pending=%{public}d chars=%{public}d',
      this.initialSearchPending ? 1 : 0, this.query.length)
    this.scheduleInitialSearch()
  }

  onPageHide(): void {
    this.pageVisible = false
    this.clearSeedTimer()
  }

  aboutToDisappear(): void {
    this.onPageHide()
    this.alive = false; this.showScopeSettings = false; this.showDirectoryMenu = false
    this.initGeneration++; this.cancelSearch()
  }

  private label(resource: Resource): string {
    return this.getUIContext().getHostContext()!.resourceManager.getStringSync(resource.id)
  }

  private clearSeedTimer(): void {
    this.seedTicket++
    if (this.seedTimer >= 0) clearTimeout(this.seedTimer)
    this.seedTimer = -1
  }

  private scheduleInitialSearch(): void {
    if (!this.alive || !this.pageVisible || this.initializing ||
      !this.initialSearchPending || this.session === null) return
    this.clearSeedTimer()
    const ticket = this.seedTicket
    const initialization = this.initGeneration
    const word = this.query
    // Router replace does not guarantee transition progress or another render frame.
    // Dispatch in the next event-loop task after visibility and settings are ready.
    this.seedTimer = setTimeout(() => {
      if (!this.alive || !this.pageVisible || this.initializing ||
        ticket !== this.seedTicket || initialization !== this.initGeneration ||
        !this.initialSearchPending || this.session === null || word !== this.query) return
      this.seedTimer = -1
      this.initialSearchPending = false
      hilog.info(0, 'MediaSearch', 'seed_dispatch chars=%{public}d aggregate=%{public}d scopes=%{public}d',
        word.length, this.aggregateMode ? 1 : 0, this.selectedScopeKeys.length)
      this.search(word)
    }, 0)
  }

  private async initialize(): Promise<void> {
    this.clearSeedTimer()
    const ticket = ++this.initGeneration
    this.showDirectoryMenu = false
    this.cancelSearch(); this.initializing = true; this.error = ''; this.session = null
    this.items = []; this.displayedItems = []; this.submittedQuery = ''; this.pageError = ''
    this.page = 0; this.pageCount = 1; this.history = []; this.historyKey = ''; this.scopeName = ''; this.scopes = []
    try {
      let session = await MediaSearchSession.open(this.sourceId,
        this.getUIContext().getHostContext() as common.UIAbilityContext)
      const preferences = PreferencesStore.getInstance()
      const savedScope = await preferences.getString(this.scopePreferenceKey(), '')
      const savedSingle = await preferences.getString(this.singleScopePreferenceKey(), '')
      const single = savedScope !== MEDIA_SEARCH_ALL && savedScope.length > 0 ? savedScope : savedSingle
      const aggregate = session.scopes.length > 0 && (savedScope === MEDIA_SEARCH_ALL || savedScope.length === 0)
      if (session.scopes.some((site: CatNodeSite) => site.key === single)) session = session.forScope(single)
      const selection = MediaSearchScopeSelection.decode(await preferences.getString(this.scopeSelectionPreferenceKey(), ''), session.scopes)
      const historyKey = aggregate ? this.aggregateHistoryKey() : session.historyKey
      const saved = await preferences.getString(historyKey, '')
      const legacy = saved.length === 0 && session.isEmby ? await preferences.getString('emby_search_history', '[]') : saved
      if (!this.alive || ticket !== this.initGeneration) return
      this.session = session; this.aggregateMode = aggregate
      this.scopeName = aggregate ? this.label($r('app.string.media_search_aggregate')) : session.scopeName
      this.historyKey = historyKey; this.scopes = session.scopes
      this.selectedScopeKeys = selection
      this.history = MediaSearchPresentation.history(legacy)
      if (saved.length === 0 && this.history.length > 0) void this.saveHistory()
    } catch (_) {
      hilog.warn(0, 'MediaSearch', 'initialize_failed')
      if (this.alive && ticket === this.initGeneration) this.error = this.label($r('app.string.media_search_connect_failed'))
    } finally {
      if (this.alive && ticket === this.initGeneration) {
        this.initializing = false
        hilog.info(0, 'MediaSearch', 'seed_ready pending=%{public}d visible=%{public}d session=%{public}d',
          this.initialSearchPending ? 1 : 0, this.pageVisible ? 1 : 0, this.session === null ? 0 : 1)
        this.scheduleInitialSearch()
      }
    }
  }

  private cancelSearch(): void {
    this.generation++; this.searching = false; this.paging = false
    this.aggregate?.cancel(); this.aggregate = null
    this.aggregateState = new MediaSearchAggregateState(); this.aggregateStopped = false
    this.visibleLimit = 60
  }

  private scopePreferenceKey(): string { return 'media_search_directory_v1:' + encodeURIComponent(this.sourceId) }
  private singleScopePreferenceKey(): string { return 'media_search_single_directory_v1:' + encodeURIComponent(this.sourceId) }
  private scopeSelectionPreferenceKey(): string { return 'media_search_aggregate_scope_v1:' + encodeURIComponent(this.sourceId) }
  private aggregateHistoryKey(): string { return 'media_search_history_v1:' + encodeURIComponent(this.sourceId) + ':' + encodeURIComponent(MEDIA_SEARCH_ALL) }

  private scopeMenu(): SourceMenuEntry[] {
    return this.scopes.map((site: CatNodeSite): SourceMenuEntry => ({
      key: site.key, value: site.name, action: () => { this.showDirectoryMenu = false; void this.changeScope(site.key) }
    }))
  }

  private toggleDirectoryMenu(): void {
    if (!this.alive || this.aggregateMode || this.initializing || this.scopeSaving || this.scopes.length === 0) return
    this.showDirectoryMenu = !this.showDirectoryMenu
  }

  private setAggregation(enabled: boolean): void {
    if (enabled === this.aggregateMode || this.initializing || this.scopeSaving || this.session === null) return
    const single = this.scopes.some((site: CatNodeSite) => site.key === this.session?.scopeKey) ? this.session.scopeKey : this.scopes[0]?.key
    if (enabled) void this.changeScope(MEDIA_SEARCH_ALL)
    else if (single !== undefined) void this.changeScope(single)
  }

  private openScopeSettings(): void {
    if (!this.alive || this.initializing || this.scopeSaving || this.scopes.length === 0) return
    this.draftScopeKeys = this.selectedScopeKeys.slice(); this.scopeFilter = ''; this.scopeSaveError = ''
    this.showScopeSettings = true
  }

  private filteredScopeChoices(): CatNodeSite[] {
    const filter = this.scopeFilter.trim().toLocaleLowerCase()
    return this.scopes.filter((site: CatNodeSite) => site.name.toLocaleLowerCase().includes(filter))
  }

  private toggleDraftScope(key: string): void {
    if (this.scopeSaving || !this.scopes.some((site: CatNodeSite) => site.key === key)) return
    this.draftScopeKeys = this.draftScopeKeys.includes(key) ? this.draftScopeKeys.filter((value: string) => value !== key) :
      MediaSearchScopeSelection.normalize([...this.draftScopeKeys, key], this.scopes)
    this.scopeSaveError = ''
  }

  private selectAllScopes(selected: boolean): void {
    if (this.scopeSaving) return
    this.draftScopeKeys = selected ? this.scopes.map((site: CatNodeSite) => site.key) : []
    this.scopeSaveError = ''
  }

  private async applyScopeSelection(): Promise<void> {
    if (!this.alive || this.initializing || this.scopeSaving || !this.showScopeSettings || this.session === null) return
    const keys = MediaSearchScopeSelection.normalize(this.draftScopeKeys, this.scopes)
    if (keys.length === 0) { this.scopeSaveError = this.label($r('app.string.media_search_scope_minimum')); return }
    if (MediaSearchScopeSelection.equal(keys, this.selectedScopeKeys)) { this.showScopeSettings = false; return }
    const ticket = this.initGeneration; const session = this.session
    this.scopeSaving = true; this.scopeSaveError = ''
    try {
      await PreferencesStore.getInstance().setStringStrict(this.scopeSelectionPreferenceKey(), JSON.stringify(keys))
      if (!this.alive || ticket !== this.initGeneration || this.session !== session) return
      this.selectedScopeKeys = keys; this.showScopeSettings = false
      if (this.aggregateMode && this.query.trim().length > 0) this.search(this.query, true)
    } catch (_) {
      if (this.alive && ticket === this.initGeneration) this.scopeSaveError = this.label($r('app.string.media_search_scope_save_failed'))
    } finally { this.scopeSaving = false }
  }

  private async changeScope(key: string): Promise<void> {
    const aggregate = key === MEDIA_SEARCH_ALL
    if (!this.alive || this.initializing || this.scopeSaving || this.session === null || this.scopes.length === 0 ||
      (aggregate ? this.aggregateMode : !this.aggregateMode && key === this.session.scopeKey) ||
      (!aggregate && !this.scopes.some((site: CatNodeSite) => site.key === key))) return
    this.showDirectoryMenu = false
    const session = aggregate ? this.session : this.session.forScope(key)
    const word = this.query; const ticket = ++this.initGeneration
    this.cancelSearch(); this.initializing = true; this.session = session; this.aggregateMode = aggregate
    this.scopeName = aggregate ? this.label($r('app.string.media_search_aggregate')) : session.scopeName
    this.historyKey = aggregate ? this.aggregateHistoryKey() : session.historyKey
    this.history = []; this.items = []; this.displayedItems = []
    this.submittedQuery = ''; this.error = ''; this.pageError = ''; this.page = 0; this.pageCount = 1
    try {
      const preferences = PreferencesStore.getInstance()
      const history = await preferences.getString(this.historyKey, '[]')
      if (!this.alive || ticket !== this.initGeneration || this.session !== session) return
      this.history = MediaSearchPresentation.history(history)
      await preferences.setStringStrict(this.scopePreferenceKey(), key)
      if (!aggregate) await preferences.setStringStrict(this.singleScopePreferenceKey(), key)
    } catch (_) {
      hilog.warn(0, 'MediaSearch', 'scope_preferences_failed')
    } finally {
      if (this.alive && ticket === this.initGeneration && this.session === session) {
        this.initializing = false
        if (word.trim().length > 0) this.search(word)
      }
    }
  }

  private editQuery(value: string): void {
    if (value === this.query) return
    if (this.initialSearchPending) hilog.info(0, 'MediaSearch', 'seed_cancel reason=edited')
    this.initialSearchPending = false; this.clearSeedTimer()
    this.cancelSearch(); this.query = value; this.submittedQuery = ''; this.items = []; this.displayedItems = []
    this.page = 0; this.pageCount = 1; this.pageError = ''; this.error = ''; this.managingHistory = false
  }

  private search(value: string, force: boolean = false): void {
    if (!this.alive || this.initializing || this.session === null) return
    this.initialSearchPending = false; this.clearSeedTimer()
    const word = MediaSearchPresentation.normalize(value)
    if (!force && this.searching && word === this.submittedQuery) return
    this.cancelSearch(); this.query = word; this.submittedQuery = word
    this.items = []; this.displayedItems = []; this.error = ''; this.pageError = ''
    this.page = 0; this.pageCount = 1; this.managingHistory = false
    if (word.length === 0) return
    if (!this.aggregateMode && this.session.canSearch === false) {
      this.error = this.label($r('app.string.media_search_directory_unavailable')); return
    }
    if (this.aggregateMode && this.selectedScopeKeys.length === 0) {
      this.error = this.label($r('app.string.media_search_scope_minimum')); return
    }
    this.searching = true
    this.scroller.scrollEdge(Edge.Top)
    void this.runSearch(word, this.generation)
  }

  private async runSearch(word: string, generation: number, page: number = 1): Promise<void> {
    if (this.aggregateMode) { await this.runAggregate(word, generation, page); return }
    const session = this.session
    if (session === null) return
    hilog.info(0, 'MediaSearch', 'request_begin generation=%{public}d page=%{public}d', generation, page)
    try {
      const result = await session.search(word, page)
      if (!this.alive || generation !== this.generation || this.session !== session) return
      this.items = MediaSearchPresentation.merge(page === 1 ? [] : this.items, result.items)
      this.displayedItems = MediaSearchPresentation.sorted(this.items, this.order)
      this.page = result.page; this.pageCount = result.pageCount
      hilog.info(0, 'MediaSearch', 'request_done generation=%{public}d page=%{public}d count=%{public}d',
        generation, page, result.items.length)
      if (page === 1) this.rememberSearch(word)
    } catch (error) {
      if (!this.alive || generation !== this.generation || this.session !== session) return
      const unavailable = error instanceof CatNodeSearchUnavailableError
      hilog.warn(0, 'MediaSearch', 'request_failed generation=%{public}d page=%{public}d kind=%{public}s',
        generation, page, unavailable ? 'directory_unavailable' : 'provider_error')
      if (page === 1) this.error = this.label(unavailable ? $r('app.string.media_search_directory_unavailable') :
        $r('app.string.media_search_failed'))
      else this.pageError = this.label($r('app.string.media_search_page_failed'))
    } finally {
      if (this.alive && generation === this.generation && this.session === session) {
        if (page === 1) this.searching = false
        else this.paging = false
      }
    }
  }

  private more(): void {
    if (this.aggregateMode) {
      if (!this.alive || this.initializing || this.searching || this.paging || this.aggregate === null ||
        !this.aggregateState.hasMore || this.aggregateStopped) return
      this.paging = true
      void this.runSearch(this.submittedQuery, this.generation, 2)
      return
    }
    if (!this.alive || this.initializing || this.searching || this.paging || this.session === null ||
      this.submittedQuery.length === 0 || this.page >= this.pageCount) return
    this.paging = true; this.pageError = ''
    void this.runSearch(this.submittedQuery, this.generation, this.page + 1)
  }

  private async runAggregate(word: string, generation: number, page: number): Promise<void> {
    const session = this.session
    if (session === null) return
    const run = page === 1 ? new MediaSearchAggregate(session, word, 12000, this.selectedScopeKeys) : this.aggregate
    if (run === null) return
    this.aggregate = run
    const current = (): boolean => this.alive && generation === this.generation && this.session === session && this.aggregate === run
    hilog.info(0, 'MediaSearch', 'aggregate_begin generation=%{public}d', generation)
    try {
      const state = await run.round((value: MediaSearchAggregateState) => {
        if (!current()) return
        this.aggregateState = value; this.items = value.items
        this.displayedItems = MediaSearchPresentation.sorted(this.items, this.order)
      })
      if (!current()) return
      this.aggregateState = state
      if (page === 1 && state.succeeded > 0) this.rememberSearch(word)
      hilog.info(0, 'MediaSearch', 'aggregate_done completed=%{public}d failed=%{public}d unsupported=%{public}d count=%{public}d',
        state.completed, state.failed, state.unavailable, state.items.length)
    } catch (_) {
      if (current()) this.pageError = this.label($r('app.string.media_search_failed'))
    } finally {
      if (current()) { this.searching = false; this.paging = false }
    }
  }

  private stopAggregate(): void {
    if (this.aggregate === null) return
    this.generation++; this.aggregate.cancel()
    this.aggregateState = this.aggregate.snapshot(); this.aggregateStopped = true
    this.searching = false; this.paging = false
    if (this.items.length > 0) this.rememberSearch(this.submittedQuery)
  }

  private rememberSearch(value: string): void {
    this.history = MediaSearchPresentation.remember(this.history, value)
    void this.saveHistory()
  }

  private removeHistory(word: string): void { this.history = this.history.filter((value: string) => value !== word); void this.saveHistory() }
  private clearHistory(): void { this.history = []; this.managingHistory = false; void this.saveHistory() }

  private async saveHistory(): Promise<void> {
    const key = this.historyKey; const snapshot = JSON.stringify(this.history)
    if (key.length === 0) return
    try { await PreferencesStore.getInstance().setStringStrict(key, snapshot) }
    catch (_) {
      if (this.alive) this.getUIContext().getPromptAction().showToast(
        buildDetailToastOptions(this.label($r('app.string.media_search_history_failed'))))
    }
  }

  private filteredHistory(): string[] {
    const word = MediaSearchPresentation.normalize(this.query).toLocaleLowerCase()
    return this.history.filter((value: string) => value.toLocaleLowerCase().includes(word))
  }

  private setOrder(value: string): void {
    if (!['default', 'title', 'year'].includes(value)) return
    this.order = value; this.displayedItems = MediaSearchPresentation.sorted(this.items, value)
  }

  private sortLabel(): Resource {
    return this.order === 'title' ? $r('app.string.media_search_sort_title') :
      this.order === 'year' ? $r('app.string.media_search_sort_year') : $r('app.string.media_search_sort_default')
  }

  private sortMenu(): MenuElement[] {
    return ['default', 'title', 'year'].map((order: string): MenuElement => ({
      value: this.label(order === 'title' ? $r('app.string.media_search_sort_title') :
        order === 'year' ? $r('app.string.media_search_sort_year') : $r('app.string.media_search_sort_default')),
      action: () => this.setOrder(order)
    }))
  }

  private sortMenuOptions(): MenuOptions {
    const material = buildDetailSheetMaterial(this.materialThickness)
    const options: MenuOptions = { placement: Placement.BottomRight,
      backgroundColor: material === undefined ? $r('app.color.card_background') : Color.Transparent }
    if (material !== undefined) options.systemMaterial = material
    return options
  }

  private directoryMenuOptions(): MenuOptions {
    return buildSourceSelectionMenuOptions(this.materialThickness, Placement.BottomRight, () => { this.showDirectoryMenu = false })
  }

  @Builder
  private DirectoryMenu(): void {
    SourceSelectionMenu({ entries: this.scopeMenu(), selectedKey: this.session?.scopeKey ?? '',
      disabled: this.initializing || this.scopeSaving })
  }

  private viewportWidth(): number { return this.measuredWidth || MediaSearchPresentation.width(this.screenWidth) }
  private visibleResults(): MediaSearchItem[] { return this.displayedItems.slice(0, this.visibleLimit) }
  private revealResults(): void { this.visibleLimit = Math.min(this.displayedItems.length, this.visibleLimit + 60) }
  private columns(): number { return MediaSearchPresentation.columns(this.viewportWidth()) }
  private cardWidth(): number { return MediaSearchPresentation.cardWidth(this.viewportWidth()) }

  private openItem(item: MediaSearchItem, transitionId: string): void {
    if (item.embyItem !== null) {
      void this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyDetailPage',
        params: buildEmbyDetailRouteParams(this.sourceId, item.embyItem, transitionId, item.artworkUrl) })
    } else {
      void this.getUIContext().getRouter().pushUrl({ url: 'pages/catvod/CatVodDetailPage',
        params: { sourceId: this.sourceId, videoId: item.id, title: item.title, fromSearch: true } })
    }
  }

  private titleOptions(): HdsNavigationTitleBarOptions {
    const options = buildMediaDetailTitleBarOptions(this.label($r('app.string.media_search_title')), this.materialLevel)
    if (options.content !== undefined) {
      options.content.bottomBuilder = { builder: () => { this.SearchField() }, height: this.searchFieldHeight() }
    }
    return options
  }

  private searchFieldHeight(): number { return this.scopes.length > 0 ? 128 : 112 }

  private scopeSheetOptions(): SheetOptions {
    return buildDetailSheetOptions(this.materialThickness, {
      height: SheetSize.LARGE, dragBar: true, showClose: true, backgroundColor: $r('app.color.card_background'),
      onDisappear: () => { this.showScopeSettings = false }
    })
  }

  @Builder
  private ScopeSummary(): void {
    Row({ space: 6 }) {
      if (this.aggregateMode) {
        Text($r('app.string.media_search_control_range')).fontSize(12).fontColor($r('app.color.text_secondary'))
        Text('·').fontSize(12).fontColor($r('app.color.text_hint')).accessibilityLevel('no')
      }
      Text(this.aggregateMode ? this.selectedScopeKeys.length > 0 ? String(this.selectedScopeKeys.length) :
        this.label($r('app.string.media_search_control_choose')) : this.scopeName)
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(this.aggregateMode ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.Start)
      SymbolGlyph(this.aggregateMode ? $r('sys.symbol.chevron_right') : $r('sys.symbol.chevron_down'))
        .fontSize(12).fontColor([$r('app.color.text_muted')]).accessibilityLevel('no')
    }.width('100%')
  }

  @Builder
  private SearchControls(): void {
    Row({ space: 10 }) {
      Stack() {
        // The title-area material is a decorative backplate; only the label and native switch handle input.
        Button({ type: ButtonType.Normal }) {}.width('100%').height(48).borderRadius(24)
          .backgroundColor(this.aggregateMode ? $r('app.color.search_control_scope_surface') : $r('app.color.card_background'))
          .attributeModifier(new DetailTitleButtonMaterialModifier(this.materialThickness))
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        Row({ space: 6 }) {
          Button({ type: ButtonType.Normal }) {
            Text(this.viewportWidth() < 340 ? $r('app.string.media_search_control_short') : $r('app.string.media_search_aggregate'))
              .fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor(this.aggregateMode ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
          }.layoutWeight(1).height(44).padding(0).backgroundColor(Color.Transparent)
            .enabled(!this.initializing && !this.scopeSaving)
            .accessibilityText(this.label($r('app.string.media_search_aggregate')) + '，' + this.label(this.aggregateMode ?
              $r('app.string.media_search_control_on') : $r('app.string.media_search_control_off')))
            .onClick(() => this.setAggregation(!this.aggregateMode))
          Toggle({ type: ToggleType.Switch, isOn: this.aggregateMode }).width(40).height(28)
            .responseRegion({ x: 0, y: -8, width: 40, height: 44 })
            .selectedColor($r('app.color.accent_blue')).enabled(!this.initializing && !this.scopeSaving)
            .accessibilityText(this.label($r('app.string.media_search_aggregate')))
            .onChange((enabled: boolean) => this.setAggregation(enabled))
        }.width('100%').height(48).padding({ left: this.viewportWidth() < 340 ? 10 : 14, right: this.viewportWidth() < 340 ? 8 : 12 })
      }.layoutWeight(1).height(48)
      if (this.aggregateMode) {
        Button({ type: ButtonType.Normal }) { this.ScopeSummary() }
          .layoutWeight(1).height(48).padding({ left: 14, right: 12 }).borderRadius(24)
          .backgroundColor($r('app.color.search_control_scope_surface'))
          .attributeModifier(new DetailTitleButtonMaterialModifier(this.materialThickness))
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
          .accessibilityText(this.label($r('app.string.media_search_scope_settings')) + '，' +
            String(this.selectedScopeKeys.length) + ' / ' + String(this.scopes.length))
          .enabled(!this.initializing && !this.scopeSaving).onClick(() => this.openScopeSettings())
      } else {
        Stack() {
          Button({ type: ButtonType.Normal }) { this.ScopeSummary() }
            .width('100%').height(48).padding({ left: 14, right: 12 }).borderRadius(24)
            .backgroundColor($r('app.color.card_background'))
            .attributeModifier(new DetailTitleButtonMaterialModifier(this.materialThickness))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
            .accessibilityText(this.label($r('app.string.media_search_choose_directory')) + '，' + this.scopeName)
            .enabled(!this.initializing && !this.scopeSaving).onClick(() => this.toggleDirectoryMenu())
        }.layoutWeight(1).height(48)
          .bindMenu(this.showDirectoryMenu, this.DirectoryMenu(), this.directoryMenuOptions())
      }
    }.width('100%').constraintSize({ maxWidth: 520 }).height(56)
  }

  @Builder
  private ScopeSettings(): void {
    Column({ space: 14 }) {
      Text($r('app.string.media_search_scope_settings')).fontSize(21).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%').padding({ right: 36 })
      Text($r('app.string.media_search_scope_hint')).fontSize(13).lineHeight(19)
        .fontColor($r('app.color.text_secondary')).width('100%')
      Search({ value: this.scopeFilter, placeholder: $r('app.string.media_search_scope_filter') })
        .width('100%').height(44).borderRadius(22).enabled(!this.scopeSaving)
        .backgroundColor($r('app.color.page_background')).onChange((value: string) => { this.scopeFilter = value })
      Row({ space: 10 }) {
        Text(this.label($r('app.string.media_search_scope_selected')) + ' ' +
          String(this.draftScopeKeys.length) + ' / ' + String(this.scopes.length))
          .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Button($r('app.string.media_search_scope_all'), { type: ButtonType.Normal }).height(40).fontSize(13)
          .padding({ left: 6, right: 6 }).backgroundColor(Color.Transparent).fontColor($r('app.color.accent_blue'))
          .enabled(!this.scopeSaving && this.draftScopeKeys.length < this.scopes.length).onClick(() => this.selectAllScopes(true))
        Button($r('app.string.media_search_clear'), { type: ButtonType.Normal }).height(40).fontSize(13)
          .padding({ left: 6, right: 6 }).backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
          .enabled(!this.scopeSaving && this.draftScopeKeys.length > 0).onClick(() => this.selectAllScopes(false))
      }.width('100%')
      if (this.filteredScopeChoices().length === 0) {
        Text($r('app.string.media_search_scope_no_match')).fontSize(14).fontColor($r('app.color.text_secondary'))
          .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.filteredScopeChoices(), (site: CatNodeSite) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Text(site.name).fontSize(15).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor(this.draftScopeKeys.includes(site.key) ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
                    .layoutWeight(1).textAlign(TextAlign.Start)
                  Stack() {
                    if (this.draftScopeKeys.includes(site.key)) {
                      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([$r('app.color.text_on_primary')])
                    }
                  }.width(22).height(22).borderRadius(6).border({ width: 1,
                    color: this.draftScopeKeys.includes(site.key) ? $r('app.color.accent_blue') : $r('app.color.border_item') })
                    .backgroundColor(this.draftScopeKeys.includes(site.key) ? $r('app.color.accent_blue') : Color.Transparent)
                    .accessibilityLevel('no')
                }.width('100%')
              }.width('100%').height(54).padding({ left: 14, right: 14 }).borderRadius(14)
                .backgroundColor(this.draftScopeKeys.includes(site.key) ? $r('app.color.category_menu_item_selected') : $r('app.color.page_background'))
                .enabled(!this.scopeSaving).onClick(() => this.toggleDraftScope(site.key))
                .accessibilityText(site.name + '，' + this.label(this.draftScopeKeys.includes(site.key) ?
                  $r('app.string.media_search_scope_checked') : $r('app.string.media_search_scope_unchecked')))
            }
          }, (site: CatNodeSite) => site.key)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      }
      Column({ space: 10 }) {
        if (this.scopeSaveError.length > 0) {
          Text(this.scopeSaveError).fontSize(13).fontColor($r('app.color.text_error')).width('100%')
        }
        Row({ space: 12 }) {
          Button($r('app.string.media_search_scope_cancel')).layoutWeight(1).height(48).fontSize(15).borderRadius(24)
            .backgroundColor($r('app.color.page_background')).fontColor($r('app.color.text_primary'))
            .enabled(!this.scopeSaving).onClick(() => { this.showScopeSettings = false })
          Button(this.scopeSaving ? $r('app.string.media_search_scope_saving') : $r('app.string.media_search_scope_apply'))
            .layoutWeight(1).height(48).fontSize(15).borderRadius(24)
            .backgroundColor($r('app.color.accent_blue')).fontColor($r('app.color.text_on_primary'))
            .enabled(!this.scopeSaving && this.draftScopeKeys.length > 0).onClick(() => { void this.applyScopeSelection() })
        }.width('100%')
      }.width('100%')
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 20, bottom: 16 + this.bottomSafeHeight })
      .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SearchField(): void {
    Column({ space: 8 }) {
      Search({ value: this.query, placeholder: $r('app.string.media_search_placeholder') })
        .width('100%').height(48).borderRadius(24).searchButton($r('app.string.media_search_action'))
        .backgroundColor($r('app.color.card_background'))
        .attributeModifier(new SearchTitleMaterialModifier(this.materialThickness))
        .enabled(!this.initializing && this.session !== null)
        .onChange((value: string) => this.editQuery(value)).onSubmit((value: string) => this.search(value))
      if (this.scopes.length > 0) this.SearchControls()
      else {
        Row({ space: 6 }) {
          Text(this.scopeName.length > 0 ? this.scopeName : $r('app.string.media_search_current_source'))
            .fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (this.initializing) LoadingProgress().width(14).height(14).color($r('app.color.accent_blue'))
        }.width('100%').height(40)
      }
    }.width('100%').constraintSize({ maxWidth: 1200 }).height(this.searchFieldHeight())
      .padding({ left: 20, right: 20, top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private History(): void {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Text(this.query.trim().length > 0 ? $r('app.string.media_search_related_history') : $r('app.string.media_search_history'))
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button(this.managingHistory ? $r('app.string.media_search_done') : $r('app.string.media_search_manage'),
          { type: ButtonType.Normal }).height(40).fontSize(13).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent_blue')).onClick(() => { this.managingHistory = !this.managingHistory })
        if (this.managingHistory) {
          Button($r('app.string.media_search_clear'), { type: ButtonType.Normal }).height(40).fontSize(13)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => this.clearHistory())
        }
      }.width('100%')
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.filteredHistory(), (word: string) => {
          Row() {
            Button(word, { type: ButtonType.Normal }).fontSize(14).height(44)
              .constraintSize({ maxWidth: Math.max(100, this.viewportWidth() - (this.managingHistory ? 108 : 72)) })
              .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent)
              .onClick(() => this.search(word))
            if (this.managingHistory) {
              Button('×', { type: ButtonType.Circle }).width(32).height(32).fontSize(18)
                .fontColor($r('app.color.text_secondary')).backgroundColor(Color.Transparent)
                .accessibilityText(this.label($r('app.string.media_search_delete_history')) + '：' + word)
                .onClick(() => this.removeHistory(word))
            }
          }.padding({ right: this.managingHistory ? 6 : 0 }).borderRadius(22)
            .backgroundColor($r('app.color.card_background')).margin({ right: 8, bottom: 10 })
        }, (word: string) => word)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ResultToolbar(): void {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text($r('app.string.media_search_results')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Row({ space: 4 }) {
          Text($r('app.string.media_search_loaded')).fontSize(12).fontColor($r('app.color.text_muted'))
          Text(String(this.items.length)).fontSize(12).fontColor($r('app.color.text_muted'))
          Text($r('app.string.media_search_items')).fontSize(12).fontColor($r('app.color.text_muted'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 4 }) {
          Text(this.sortLabel()).fontSize(13).fontColor($r('app.color.text_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([$r('app.color.text_secondary')])
        }
      }.height(44).padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent)
        .bindMenu(this.sortMenu(), this.sortMenuOptions()).enabled(this.items.length > 0)
      Button(this.listMode ? $r('app.string.media_search_grid') : $r('app.string.media_search_list'), { type: ButtonType.Normal })
        .height(44).fontSize(13).padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent)
        .fontColor($r('app.color.accent_blue')).enabled(this.items.length > 0)
        .onClick(() => { this.listMode = !this.listMode })
    }.width('100%')
  }

  @Builder
  private Results(): void {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(this.visibleResults(), (item: MediaSearchItem, index: number) => {
        SearchResultCard({ item: item, artworkUrl: item.artworkUrl, listMode: this.listMode, cardWidth: this.cardWidth(),
          showSource: this.aggregateMode,
          onOpen: (transitionId: string) => this.openItem(item, transitionId) })
          .width(this.listMode ? '100%' : this.cardWidth())
          .margin({ right: this.listMode || (index + 1) % this.columns() === 0 ? 0 : 12, bottom: this.listMode ? 12 : 20 })
      }, (item: MediaSearchItem, index: number) => String(this.listMode) + ':' + String(index) + ':' + item.id)
    }.width('100%')
  }

  @Builder
  private AggregateStatus(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.searching || this.paging) LoadingProgress().width(16).height(16).color($r('app.color.accent_blue'))
        Text(this.aggregateStopped ? $r('app.string.media_search_stopped') :
          this.searching || this.paging ? $r('app.string.media_search_aggregate_running') : $r('app.string.media_search_aggregate_done'))
          .fontSize(13).fontColor($r('app.color.text_secondary'))
        Text(String(this.aggregateState.completed) + ' / ' + String(this.aggregateState.total))
          .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        if (this.searching || this.paging) {
          Button($r('app.string.media_search_stop'), { type: ButtonType.Normal }).height(40).fontSize(13)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.accent_blue')).onClick(() => this.stopAggregate())
        }
      }.width('100%')
      if (this.aggregateState.failed > 0 || this.aggregateState.unavailable > 0) {
        Row({ space: 6 }) {
          Text($r('app.string.media_search_aggregate_failed')).fontSize(12).fontColor($r('app.color.text_muted'))
          Text(String(this.aggregateState.failed)).fontSize(12).fontColor($r('app.color.text_muted'))
          Text($r('app.string.media_search_aggregate_unsupported')).fontSize(12).fontColor($r('app.color.text_muted'))
          Text(String(this.aggregateState.unavailable)).fontSize(12).fontColor($r('app.color.text_muted'))
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LoadingResults(): void {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color($r('app.color.accent_blue'))
        Text($r('app.string.media_search_loading')).fontSize(14).fontColor($r('app.color.text_secondary'))
      }
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
          Column({ space: 10 }) {
            Column().width(this.cardWidth()).height(this.cardWidth() * 1.5).borderRadius(12)
              .backgroundColor($r('app.color.skeleton_background'))
            Column().width(this.cardWidth() * 0.8).height(12).borderRadius(6).backgroundColor($r('app.color.skeleton_background'))
          }.width(this.cardWidth()).margin({ right: (index + 1) % this.columns() === 0 ? 0 : 12, bottom: 20 })
        }, (index: number) => String(index))
      }.width('100%').accessibilityLevel('no-hide-descendants')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Footer(): void {
    if (this.displayedItems.length > this.visibleLimit) {
      Button($r('app.string.media_search_show_more_results')).width('100%').height(46).borderRadius(23).fontSize(14)
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent_blue')).onClick(() => this.revealResults())
    }
    if (this.pageError.length > 0) {
      Text(this.pageError).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').textAlign(TextAlign.Center)
    }
    if (this.aggregateMode && this.aggregateState.hasMore && !this.searching && !this.paging && !this.aggregateStopped) {
      Button(this.aggregateState.failed > 0 ? $r('app.string.media_search_aggregate_retry') : $r('app.string.media_search_aggregate_more'))
        .width('100%').height(46).borderRadius(23).fontSize(14)
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent_blue')).onClick(() => this.more())
    } else if (!this.aggregateMode && this.page < this.pageCount) {
      Button(this.pageError.length > 0 ? $r('app.string.media_search_retry') :
        this.paging ? $r('app.string.media_search_loading_more') : $r('app.string.media_search_more'))
        .width('100%').height(46).borderRadius(23).fontSize(14)
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent_blue'))
        .enabled(!this.paging).onClick(() => this.more())
    }
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight) + this.searchFieldHeight())
          if (this.initializing) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color($r('app.color.accent_blue'))
              Text($r('app.string.media_search_connecting')).fontSize(14).fontColor($r('app.color.text_secondary'))
            }
          } else if (this.error.length > 0) {
            PageErrorState({ title: this.label($r('app.string.media_search_unavailable')), message: this.error,
              onRetry: () => { if (this.session === null) void this.initialize(); else this.search(this.query) } })
          } else if (this.initialSearchPending) {
            this.LoadingResults()
          } else if (this.submittedQuery.length === 0) {
            if (this.filteredHistory().length > 0) this.History()
            else PageEmptyState({ icon: $r('sys.symbol.magnifyingglass'),
              title: this.label($r('app.string.media_search_idle_title')),
              message: this.label($r('app.string.media_search_idle_message')), minHeight: 220 })
          } else if (this.searching && !this.aggregateMode) {
            this.LoadingResults()
          } else {
            this.ResultToolbar()
            if (this.aggregateMode) this.AggregateStatus()
            if (this.items.length > 0) this.Results()
            else if (this.searching) this.LoadingResults()
            else PageEmptyState({ icon: $r('sys.symbol.magnifyingglass'),
              title: this.label($r('app.string.media_search_empty_title')),
              message: this.label($r('app.string.media_search_empty_message')), minHeight: 220 })
            this.Footer()
          }
        }.width('100%').constraintSize({ maxWidth: 1200 }).alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, bottom: 28 + this.bottomSafeHeight })
          .onAreaChange((_oldArea: Area, area: Area) => {
            const width = Number(area.width)
            if (Number.isFinite(width) && width >= 240 && Math.abs(width - this.measuredWidth) > 1) this.measuredWidth = width
          })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Vertical).edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(this.titleOptions()).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]).bindToScrollable([this.scroller])
      .bindSheet($$this.showScopeSettings, this.ScopeSettings(), this.scopeSheetOptions())
  }

}
