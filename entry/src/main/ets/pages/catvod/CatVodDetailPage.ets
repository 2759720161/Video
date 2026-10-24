import { common } from '@kit.AbilityKit'
import { ColorMetrics } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { CatVodProvider } from '../../providers/catvod/CatVodProvider'
import { CatNodeProvider } from '../../providers/catvod/CatNodeProvider'
import { CatNodeRecommendationError, CatNodeEmptyDetailError } from '../../providers/catvod/CatNodeClient'
import { MediaSearchPresentation } from '../../services/media/MediaSearchPresentation'
import { CatNodeConfiguration } from '../../providers/catvod/CatNodeConfiguration'
import { CatVodVideo, CatVodRoad } from '../../providers/catvod/CatVodModels'
import { CatVodCodec } from '../../providers/catvod/CatVodCodec'
import { MediaItem } from '../../core/media/MediaItem'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import { HomeHeroPalette } from '../../services/media/HomeHeroPalette'
import { HomeHeroColors } from '../../services/media/HomeHeroColors'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { buildDetailToastOptions, DetailSelectMaterialModifier } from '../../utils/DetailMaterial'
import { buildMediaDetailTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL,
  IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'
import { CatVodDetailAction } from './CatVodDetailAction'
import { CatVodDetailPresentation, CatVodEpisodeRow, CatVodEpisodeRows } from './CatVodDetailPresentation'

@Entry
@Component
struct CatVodDetailPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State private viewportWidth: number = 360
  @State private video: CatVodVideo | null = null
  @State private roadId: string = ''
  @State private episodes: MediaItem[] = []
  @State private selectedEpisodeId: string = ''
  @State private loading: boolean = true
  @State private playing: boolean = false
  @State private error: string = ''
  @State private posterFailed: boolean = false
  @State private heroSurface: string = '#f2f2f2'
  @State private overviewExpanded: boolean = false
  @State private openingConfiguration: boolean = false
  @State private openingSearch: boolean = false
  private requestTitle: string = ''
  private fromSearch: boolean = false
  private themeBase: number = 0xfff2f2f2
  private heroTone: string = ''
  private sourceId: string = ''
  private videoId: string = ''
  private provider: CatVodProvider | null = null
  private generation: number = 0
  private selectionRevision: number = 0
  private alive: boolean = true
  private scroller: Scroller = new Scroller()
  private episodeRows: CatVodEpisodeRows = new CatVodEpisodeRows()

  aboutToAppear(): void {
    this.alive = true; this.playing = false
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      this.sourceId = typeof params['sourceId'] === 'string' ? params['sourceId'] as string : ''
      this.videoId = typeof params['videoId'] === 'string' ? params['videoId'] as string : ''
      this.requestTitle = typeof params['title'] === 'string' ? MediaSearchPresentation.normalize(params['title'] as string) : ''
      this.fromSearch = params['fromSearch'] === true
    }
    void this.load()
  }
  onPageShow(): void { if (this.video !== null && !this.loading) void this.restoreSelection(this.generation) }
  aboutToDisappear(): void { this.alive = false; this.generation++ }
  onWillApplyTheme(theme: Theme): void {
    const base = ColorMetrics.resourceColor(theme.colors.backgroundPrimary)
    this.themeBase = (0xff000000 | (base.red << 16) | (base.green << 8) | base.blue) >>> 0
    this.applyHeroTone(this.heroTone)
  }

  private applyHeroTone(tone: string): void {
    this.heroTone = tone
    // The shared palette helper returns an empty string until a valid tone exists.
    this.heroSurface = HomeHeroColors.surface(tone, this.themeBase) ||
      '#' + (this.themeBase & 0x00ffffff).toString(16).padStart(6, '0')
  }

  private async load(forceRefresh: boolean = false): Promise<void> {
    if (this.playing) return
    const generation = ++this.generation
    this.loading = true; this.error = ''; this.overviewExpanded = false; this.openingConfiguration = false
    this.provider = null; this.video = null; this.episodes = []
    this.episodeRows.replace([], false)
    this.posterFailed = false; this.applyHeroTone('')
    try {
      const provider = await ProviderRegistry.get(this.sourceId, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!this.alive || generation !== this.generation) return
      if (!(provider instanceof CatVodProvider)) throw new Error(this.text($r('app.string.cat_detail_source_unavailable')))
      if (provider instanceof CatNodeProvider && CatNodeConfiguration.isItem(this.videoId, provider.getSiteKey())) {
        this.openingConfiguration = true
        await this.getUIContext().getRouter().replaceUrl({ url: 'pages/catvod/CatNodeConfigurationPage',
          params: { sourceId: this.sourceId } })
        return
      }
      const video = await provider.getDetail(this.videoId, forceRefresh)
      if (!this.alive || generation !== this.generation) return
      if (video === null) throw new Error(this.text($r('app.string.cat_detail_video_unavailable')))
      this.provider = provider; this.video = video
      this.chooseRoad(CatVodProvider.defaultRoad(video)?.id ?? '')
      void this.resolvePalette(video.poster, generation)
      void this.restoreSelection(generation)
    } catch (err) {
      if (this.alive && generation === this.generation) this.openingConfiguration = false
      if (this.alive && generation === this.generation) {
        this.error = err instanceof CatNodeEmptyDetailError ? this.text($r('app.string.cat_detail_empty_response')) :
          err instanceof Error ? err.message : this.text($r('app.string.cat_detail_load_failed'))
        if (err instanceof CatNodeRecommendationError && !this.fromSearch && this.searchTitle().length > 0) {
          await this.openSearch(true)
        }
      }
    } finally { if (this.alive && generation === this.generation) this.loading = false }
  }

  private searchTitle(): string { return MediaSearchPresentation.normalize(this.video?.name || this.requestTitle || '') }

  private async openSearch(replace: boolean = false): Promise<void> {
    const keyword = this.searchTitle()
    if (!this.alive || this.playing || this.openingSearch || keyword.length === 0 || this.sourceId.length === 0) return
    const generation = this.generation
    this.openingSearch = true
    try {
      const options: Record<string, Object> = { 'sourceId': this.sourceId, 'keyword': keyword }
      if (replace) await this.getUIContext().getRouter().replaceUrl({ url: 'pages/home/SearchPage', params: options })
      else await this.getUIContext().getRouter().pushUrl({ url: 'pages/home/SearchPage', params: options })
    } catch (_) {
      if (this.alive && generation === this.generation) this.error = this.text($r('app.string.cat_detail_search_failed'))
    } finally { if (this.alive && generation === this.generation) this.openingSearch = false }
  }

  private async resolvePalette(url: string, generation: number): Promise<void> {
    if (url.length === 0) return
    try {
      const tone = await HomeHeroPalette.resolve(url)
      if (!this.alive || generation !== this.generation || this.video?.poster !== url || this.posterFailed) return
      this.applyHeroTone(tone)
    } catch (_) {}
  }

  private async restoreSelection(generation: number): Promise<void> {
    const revision = this.selectionRevision
    try {
      const records = await new PlaybackHistoryStore().getAll()
      if (!this.alive || generation !== this.generation || revision !== this.selectionRevision || this.playing) return
      const record = records.find((value) => value.sourceId === this.sourceId &&
        CatVodCodec.identity(value.mediaId)?.videoId === this.videoId &&
        this.episodes.some((item: MediaItem) => item.id === value.mediaId))
      if (record !== undefined) this.selectedEpisodeId = record.mediaId
    } catch (_) {}
  }

  private chooseRoad(id: string): void {
    if (this.playing || this.provider === null || this.video === null) return
    if (!this.video.roads.some((road: CatVodRoad) => road.id === id)) {
      this.roadId = ''; this.episodes = []; this.selectedEpisodeId = ''; this.episodeRows.replace([], false); return
    }
    this.selectionRevision++; this.roadId = id
    this.episodes = this.provider.episodeItems(this.video, id)
    this.selectedEpisodeId = CatVodDetailPresentation.target(this.episodes, this.selectedEpisodeId)?.id ?? ''
    this.episodeRows.replace(this.episodes, false)
  }

  private primaryItem(): MediaItem | null {
    return CatVodDetailPresentation.target(this.episodes, this.selectedEpisodeId)
  }
  private async playPrimary(): Promise<void> {
    const item = this.primaryItem()
    if (item !== null) await this.play(item)
  }
  private async play(item: MediaItem): Promise<void> {
    if (this.playing || this.provider === null || !this.alive) return
    this.selectionRevision++; this.selectedEpisodeId = item.id; this.playing = true
    try { await ProviderPlaybackLauncher.openWithProvider(this.getUIContext(), this.provider, item, this.episodes) }
    catch (err) {
      if (this.alive) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(err instanceof Error ? err.message :
        this.text($r('app.string.cat_detail_play_failed'))))
    } finally { if (this.alive) this.playing = false }
  }

  private text(resource: Resource): string {
    return this.getUIContext().getHostContext()!.resourceManager.getStringSync(resource.id)
  }
  private titleOptions(): HdsNavigationTitleBarOptions {
    return buildMediaDetailTitleBarOptions('', this.materialLevel)
  }

  build() {
    Stack() {
      HdsNavigation() {
        if (this.loading || this.openingConfiguration || this.openingSearch) {
          Column() {
            PageLoadingState({ title: this.text(this.openingConfiguration ? $r('app.string.cat_config_loading') :
              $r('app.string.cat_detail_loading')), minHeight: 400 })
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (this.error.length > 0 || this.video === null) {
          Column() {
            PageErrorState({ title: this.text($r('app.string.cat_detail_unavailable')), message: this.error,
              onRetry: () => { void this.load(true) } })
            if (this.searchTitle().length > 0) {
              CatVodDetailAction({ label: this.text($r('app.string.cat_detail_search_same_title')),
                onAction: () => { void this.openSearch() } }).width('76%').constraintSize({ maxWidth: 320 })
            }
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller, space: 10 }) {
            ListItem() {
              Column({ space: 18 }) {
                this.Hero(this.video)
                this.Synopsis(this.video)
                this.RoadSelector(this.video)
                if (this.episodes.length === 0) {
                  Text($r('app.string.catvod_no_playable')).fontSize(14).fontColor($r('app.color.text_secondary'))
                    .width('100%').padding(20)
                  CatVodDetailAction({ label: this.text($r('app.string.cat_detail_search_same_title')),
                    onAction: () => { void this.openSearch() } }).width('100%')
                }
              }.width('100%').alignItems(HorizontalAlign.Center).backgroundColor(this.heroSurface)
            }
            LazyForEach(this.episodeRows, (row: CatVodEpisodeRow) => {
              ListItem() {
                Row({ space: 10 }) {
                  ForEach(row.items, (item: MediaItem) => {
                    CatVodDetailAction({ label: item.subtitle, selected: item.id === this.selectedEpisodeId,
                      actionEnabled: !this.playing, leftAligned: true, scrollOverflow: true,
                      onAction: () => { void this.play(item) } })
                      .layoutWeight(1)
                  }, (item: MediaItem) => item.id)
                }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 18, right: 18 })
              }.width('100%').align(Alignment.Center)
            }, (row: CatVodEpisodeRow) => row.key)
            ListItem() { Row().height(this.bottomSafeHeight + 28) }
          }.width('100%').height('100%').backgroundColor(this.heroSurface).scrollBar(BarState.Off).cachedCount(4)
        }
      }.width('100%').height('100%').mode(NavigationMode.Stack)
        .titleBar(this.titleOptions()).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
        .backgroundColor(this.heroSurface).bindToScrollable([this.scroller])
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }.width('100%').height('100%').backgroundColor(this.heroSurface)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width)
        if (Number.isFinite(width) && width > 0) this.viewportWidth = width
      })
  }

  @Builder
  private Hero(video: CatVodVideo): void {
    Stack({ alignContent: Alignment.Bottom }) {
      if (video.poster.length > 0 && !this.posterFailed) {
        Image(video.poster).width('100%')
          .height(CatVodDetailPresentation.heroHeight(this.viewportWidth, this.topSafeHeight)).objectFit(ImageFit.Cover)
          .accessibilityLevel('no').draggable(false).onError(() => {
            if (this.video?.poster === video.poster) {
              this.posterFailed = true; this.applyHeroTone('')
            }
          })
      } else {
        SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(56)
          .fontColor([$r('app.color.text_muted')]).align(Alignment.Center).accessibilityLevel('no')
      }
      // Match the historical home page: ordinary image plus a scrim ending in the page surface.
      Row().width('100%').height(CatVodDetailPresentation.heroHeight(this.viewportWidth, this.topSafeHeight))
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: CatVodDetailPresentation.posterGradient(this.heroSurface) })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Column({ space: 16 }) {
        Text(video.name).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (CatVodDetailPresentation.metadata(video).length > 0) {
          Text(CatVodDetailPresentation.metadata(video)).fontSize(14).fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        CatVodDetailAction({ label: this.text($r('app.string.cat_detail_play')), icon: $r('sys.symbol.play_circle'),
          busy: this.playing, actionEnabled: this.episodes.length > 0,
          onAction: () => { void this.playPrimary() } }).width('100%').margin({ top: 4 })
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 18, right: 18, bottom: 8 })
    }.width('100%').height(CatVodDetailPresentation.heroHeight(this.viewportWidth, this.topSafeHeight))
      .backgroundColor(this.heroSurface).clip(true)
  }

  @Builder
  private Synopsis(video: CatVodVideo): void {
    if (video.overview.length > 0) {
      Row({ space: 8 }) {
        Text(video.overview).fontSize(15).lineHeight(22).fontColor($r('app.color.text_primary'))
          .maxLines(this.overviewExpanded ? 9999 : 2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        SymbolGlyph(this.overviewExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(12).fontColor([$r('app.color.text_secondary')]).accessibilityLevel('no')
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 20, right: 20 })
        .onClick(() => { this.overviewExpanded = !this.overviewExpanded })
        .accessibilityText(this.text(this.overviewExpanded ? $r('app.string.cat_detail_collapse') :
          $r('app.string.cat_detail_expand')) + '，' + video.overview)
    }
  }

  @Builder
  private RoadSelector(video: CatVodVideo): void {
    Row({ space: 12 }) {
      Select(video.roads.map((road: CatVodRoad): SelectOption => ({ value: road.name })))
        .selected(video.roads.findIndex((road: CatVodRoad) => road.id === this.roadId))
        .value(video.roads.find((road: CatVodRoad) => road.id === this.roadId)?.name ?? this.text($r('app.string.cat_detail_road')))
        .font({ size: 18, weight: FontWeight.Bold }).fontColor($r('app.color.text_primary'))
        .optionFontColor($r('app.color.text_primary')).selectedOptionFontColor($r('app.color.accent_blue'))
        .attributeModifier(new DetailSelectMaterialModifier(this.materialThickness))
        .constraintSize({ minWidth: 88, maxWidth: Math.min(260, Math.max(88, (Math.min(this.viewportWidth, 760) - 36) * 0.68)) })
        .height(44).enabled(!this.playing && video.roads.length > 0)
        .accessibilityText(this.text($r('app.string.cat_detail_road')))
        .onSelect((index: number) => { if (index >= 0 && index < video.roads.length) this.chooseRoad(video.roads[index].id) })
      Blank().layoutWeight(1)
      Text(this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.cat_detail_episode_count').id,
        this.episodes.length)).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1).flexShrink(0)
    }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 18, right: 18 })
  }
}
