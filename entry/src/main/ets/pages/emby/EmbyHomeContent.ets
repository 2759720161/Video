import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { common } from '@kit.AbilityKit'
import { ColorMetrics, Theme } from '@kit.ArkUI'
import { HomeHeroColors } from '../../services/media/HomeHeroColors'
import { HomeHeroPalette } from '../../services/media/HomeHeroPalette'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbySourceConfigCodec } from '../../providers/emby/EmbySourceConfig'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { EmbyDetailPresentation } from '../../providers/emby/EmbyDetailPresentation'
import { buildEmbyDetailRouteParams } from '../../providers/emby/EmbyDetailRoute'
import { EmbyLibraryPresentation } from '../../providers/emby/EmbyLibraryPresentation'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { EmbyHomeCoordinator } from '../../services/library/EmbyHomeCoordinator'
import { EmbyHomeSnapshot, EmbyHomeSection } from '../../services/library/EmbyHomeSnapshot'
import { MediaPosterCard } from '../../components/media/MediaPosterCard'
import { ContinueWatchingCard } from '../../components/media/ContinueWatchingCard'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { getMediaContentMaxWidth, getTopSpacerHeight } from '../../utils/HdsPageStyle'
import { PLAYBACK_HISTORY_VERSION_KEY } from '../../store/PlaybackHistoryChangeSignal'

class HomePosition {
  overviewOffset: number = 0
}
const homePositions: Map<string, HomePosition> = new Map()

@Component
export struct EmbyHomeContent {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop @Watch('onActiveChanged') isActive: boolean = true
  @Prop @Watch('toggleSearch') searchToken: number = 0
  @Prop @Watch('refresh') refreshToken: number = 0
  @StorageLink('appInForeground') @Watch('onForegroundChanged') foreground: boolean = true
  @StorageLink(PLAYBACK_HISTORY_VERSION_KEY) @Watch('refresh') historyVersion: number = 0
  @StorageLink('screenWidthVp') screenWidth: number = 360
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State private snapshot: EmbyHomeSnapshot = new EmbyHomeSnapshot()
  @State private provider: EmbyProvider | null = null
  @State private error: string = ''
  @State private refreshing: boolean = false
  @State private playing: boolean = false
  @State private showSearch: boolean = false
  @State private query: string = ''
  @State private searchItems: EmbyItem[] = []
  @State private searching: boolean = false
  @State private searchError: string = ''
  @State private featuredIndex: number = 0
  @State private heroSurface: string = ''
  onBackgroundChanged: (sourceId: string, sourceUpdatedAt: number, color: string) => void = () => {}
  scroller: Scroller = new Scroller()
  private featuredSwiper: SwiperController = new SwiperController()
  private coordinator: EmbyHomeCoordinator | null = null
  private generation: number = 0
  private searchGeneration: number = 0
  private searchTimer: number = -1
  private refreshGeneration: number = 0
  private restorePending: boolean = true
  private alive: boolean = false
  private colorRequest: number = 0
  private heroTone: string = ''
  private themeBase: number = 0
  private featuredKey: string = ''
  private featuredItemId: string = ''
  private failedArtwork: Set<string> = new Set()

  aboutToAppear(): void {
    this.alive = true
    void this.initialize()
  }
  onWillApplyTheme(theme: Theme): void {
    const base = ColorMetrics.resourceColor(theme.colors.backgroundPrimary)
    this.themeBase = (0xff000000 | (base.red << 16) | (base.green << 8) | base.blue) >>> 0
    this.applyHeroTone(this.heroTone)
  }
  aboutToDisappear(): void {
    this.alive = false; this.colorRequest++
    this.generation++
    this.coordinator?.dispose()
    this.cancelSearch()
  }
  private memoryKey(): string { return this.source.id + ':' + this.source.updatedAt }
  private onActiveChanged(): void {
    if (this.isActive) { this.restorePending = true; void this.updateFeaturedColor(); void this.refresh() }
    else { this.colorRequest++; this.refreshGeneration++; this.coordinator?.dispose(); this.refreshing = false; this.cancelSearch() }
  }
  private onForegroundChanged(): void {
    this.colorRequest++
    if (this.foreground && this.isActive) { void this.updateFeaturedColor(); void this.refresh() }
  }

  private async initialize(): Promise<void> {
    const generation = ++this.generation
    try {
      const provider = await ProviderRegistry.get(this.source.id, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (generation !== this.generation) return
      if (!(provider instanceof EmbyProvider)) throw new Error('服务不可用，请检查连接配置')
      this.provider = provider
      const config = EmbySourceConfigCodec.decode(this.source.configJson)
      if (config === null) throw new Error('连接配置无效')
      const cacheKey = 'embySingleHomeV1_' + encodeURIComponent(this.memoryKey() + '|' +
        config.baseUrl + '|' + config.serverId + '|' + config.userId)
      this.coordinator = new EmbyHomeCoordinator(provider, cacheKey)
      if (this.isActive) await this.refresh()
    } catch (_) {
      if (generation === this.generation) { this.error = '无法打开 Emby，请检查连接配置'; this.applyHeroTone('') }
    }
  }

  private async refresh(): Promise<void> {
    if (!this.isActive || this.coordinator === null) return
    this.refreshing = true
    this.failedArtwork.clear()
    const generation = this.generation
    const refreshGeneration = ++this.refreshGeneration
    try {
      await this.coordinator.load((value: EmbyHomeSnapshot) => {
        if (generation === this.generation && this.isActive) {
          this.snapshot = value; this.error = ''; this.syncFeaturedColor()
        }
      })
    } catch (_) { if (generation === this.generation) { this.error = '加载失败，请重试'; this.applyHeroTone('') } }
    finally { if (generation === this.generation && refreshGeneration === this.refreshGeneration) this.refreshing = false }
  }

  private hasFeaturedBackground(): boolean {
    return this.query.trim().length === 0 && this.error.length === 0 && this.provider !== null &&
      this.featuredItems().length > 0
  }

  private publishBackground(): void {
    if (!this.alive || !this.isActive) return
    this.onBackgroundChanged(this.source.id, this.source.updatedAt,
      this.hasFeaturedBackground() ? this.heroSurface : '')
  }

  private applyHeroTone(tone: string): void {
    this.heroTone = tone
    this.heroSurface = HomeHeroColors.surface(tone, this.themeBase)
    this.publishBackground()
  }

  private heroBackground(): ResourceColor {
    return this.hasFeaturedBackground() && this.heroSurface.length > 0 ?
      this.heroSurface : $r('app.color.page_background')
  }

  private syncFeaturedColor(): void {
    const items = this.featuredItems()
    const key = items.map((item: EmbyItem) => item.id + ':' + this.artwork(item, true)).join('|')
    if (key !== this.featuredKey) {
      this.featuredKey = key
      const index = items.findIndex((item: EmbyItem) => item.id === this.featuredItemId)
      this.featuredIndex = Math.max(0, index)
      this.featuredItemId = items[this.featuredIndex]?.id ?? ''
    }
    void this.updateFeaturedColor()
  }

  private onFeaturedChanged(index: number): void {
    const item = this.featuredItems()[index]
    if (item === undefined) return
    this.featuredIndex = index; this.featuredItemId = item.id
    void this.updateFeaturedColor()
  }

  private onFeaturedArtworkError(url: string): void {
    this.failedArtwork.add(url)
    const item = this.featuredItems()[this.featuredIndex]
    if (item !== undefined && this.artwork(item, true) === url) {
      this.colorRequest++; this.applyHeroTone('')
    }
  }

  private async updateFeaturedColor(): Promise<void> {
    const request = ++this.colorRequest
    if (!this.alive || !this.isActive || !this.foreground) return
    const items = this.featuredItems()
    const item = items[this.featuredIndex]
    if (!this.hasFeaturedBackground() || item === undefined) { this.applyHeroTone(''); return }
    const url = this.artwork(item, true)
    if (url.length === 0 || this.failedArtwork.has(url)) { this.applyHeroTone(''); return }
    const generation = this.generation
    const tone = await HomeHeroPalette.resolve(url)
    const current = this.featuredItems()[this.featuredIndex]
    if (!this.alive || !this.isActive || !this.foreground || request !== this.colorRequest ||
      generation !== this.generation || !this.hasFeaturedBackground() || current === undefined || current.id !== item.id ||
      this.artwork(current, true) !== url) return
    this.applyHeroTone(tone)
    const next = items[(this.featuredIndex + 1) % items.length]
    const nextUrl = next !== undefined ? this.artwork(next, true) : ''
    if (nextUrl.length > 0 && nextUrl !== url && !this.failedArtwork.has(nextUrl)) {
      void HomeHeroPalette.resolve(nextUrl)
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 22 }) {
          if (this.showSearch) {
            Search({ value: this.query, placeholder: '搜索' + this.source.name })
              .onChange((value: string) => this.search(value))
              .onSubmit((value: string) => this.search(value))
          }
          if (this.query.trim().length > 0) {
            if (this.searching) PageLoadingState({ title: '正在搜索', minHeight: 160 })
            else if (this.searchError.length > 0) {
              PageErrorState({ title: '搜索暂不可用', message: this.searchError,
                onRetry: () => this.search(this.query) })
            } else if (this.searchItems.length > 0) this.PosterGrid(this.searchItems)
            else PageEmptyState({ title: '没有找到相关内容', minHeight: 180 })
          } else if (this.error.length > 0) {
            PageErrorState({ title: 'Emby 暂不可用', message: this.error,
              onRetry: () => { if (this.coordinator === null) void this.initialize(); else void this.refresh() } })
          } else {
            this.Overview()
          }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: getMediaContentMaxWidth(this.screenWidth) || '100%' })
        .padding({ top: 0,
          left: this.pagePadding(), right: this.pagePadding(), bottom: this.bottomSafeHeight + 120 })
        .onAreaChange(() => this.restorePosition())
    }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
      .backgroundColor(this.hasFeaturedBackground() && this.heroSurface.length > 0 ? this.heroSurface : Color.Transparent)
      .animation({ duration: 500, curve: Curve.EaseInOut })
      .onDidScroll(() => this.savePosition())
  }

  @Builder
  private Overview(): void {
    if (this.featuredItems().length > 0 && this.provider !== null) {
      this.FeaturedCarousel()
    } else if (this.snapshot.librariesLoading || this.snapshot.resumeLoading) {
      PageLoadingState({ title: '正在读取媒体', minHeight: 220 })
    }
    if (this.snapshot.librariesError.length > 0 || this.snapshot.resumeError.length > 0) {
      this.RetryNotice(this.snapshot.timestamp > 0 ? '连接暂不可用，正在显示已缓存内容' :
        '部分内容暂不可用，请重试')
    }
    if (this.otherResume().length > 0) {
      Column({ space: 14 }) {
        MediaSectionHeader({ title: '继续观看', actionText: '全部', onAction: () => this.openResumeList() })
        Scroll() {
          Row({ space: 14 }) {
            ForEach(this.otherResume(), (item: EmbyItem) => {
              ContinueWatchingCard({ title: item.seriesName.length > 0 ? item.seriesName : item.name,
                subtitle: item.subtitle(), artworkUrl: this.artwork(item, true), positionMs: item.resumePositionMs(),
                durationMs: item.durationMs(), cardWidth: ResponsiveSizeClassResolver.landscapeWidth(this.screenWidth),
                onCardClick: () => { void this.play(item) } })
            }, (item: EmbyItem) => this.source.id + ':resume:' + item.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }.width('100%')
    }
    if (this.snapshot.nextUpItems.length > 0) {
      Column({ space: 14 }) {
        MediaSectionHeader({ title: '接着看', actionText: '全部', onAction: () => {
          void this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyLibraryPage',
            params: { sourceId: this.source.id, view: 'nextup', title: '接着看' } })
        } })
        Scroll() {
          Row({ space: 14 }) {
            ForEach(this.snapshot.nextUpItems, (item: EmbyItem) => {
              ContinueWatchingCard({ title: item.seriesName || item.name, subtitle: item.subtitle(),
                artworkUrl: this.artwork(item, true),
                cardWidth: ResponsiveSizeClassResolver.landscapeWidth(this.screenWidth),
                onCardClick: () => this.openDetail(item) })
            }, (item: EmbyItem) => this.source.id + ':next:' + item.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }.width('100%')
    }
    ForEach(this.snapshot.sections, (section: EmbyHomeSection) => {
      if (section.items.length > 0 || section.loading || section.error.length > 0) this.Section(section)
    }, (section: EmbyHomeSection) => this.source.id + ':' + section.id)
    if (!this.snapshot.librariesLoading && !this.snapshot.resumeLoading && this.featuredItems().length === 0 &&
      this.snapshot.librariesError.length === 0 && this.snapshot.resumeError.length === 0 &&
      this.snapshot.sections.every((section: EmbyHomeSection) => !section.loading && section.error.length === 0)) {
      PageEmptyState({ title: '暂无可显示的媒体', message: '可切换到媒体库浏览服务器内容', minHeight: 220 })
    }
  }

  @Builder
  private FeaturedCarousel(): void {
    Stack({ alignContent: Alignment.BottomStart }) {
      Swiper(this.featuredSwiper) {
      ForEach(this.featuredItems(), (item: EmbyItem) => {
        Stack() {
          Image(this.artwork(item, true).length > 0 ? this.artwork(item, true) : $r('app.media.ic_placeholder'))
            .width('100%').height('100%').objectFit(ImageFit.Cover).blur(14).opacity(0.72).draggable(false)
          Image(this.artwork(item, true).length > 0 ? this.artwork(item, true) : $r('app.media.ic_placeholder'))
            .width('100%').height('100%').objectFit(ImageFit.Cover).opacity(0.9).draggable(false)
            .onError(() => this.onFeaturedArtworkError(this.artwork(item, true)))
          Column()
            .width('100%').height('100%')
            .linearGradient({ direction: GradientDirection.Bottom,
              colors: [['#52000000', 0], ['#00000000', 0.22], ['#22000000', 0.35],
                ['#D6000000', 0.78], [this.heroBackground(), 1]] })
            .animation({ duration: 500, curve: Curve.EaseInOut })
          Column({ space: 8 }) {
            Text('精选推荐')
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#E6FFFFFF')
            Text(item.seriesName.length > 0 ? item.seriesName : item.name)
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').lineHeight(28)
            Text(item.subtitle()).fontSize(14).fontColor('#E6FFFFFF')
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').lineHeight(18)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .padding({ left: 20, right: 20, top: this.featuredTopPadding(), bottom: this.featuredBottomPadding() })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%').height(this.featuredHeight()).clip(true)
        .onClick(() => { if (item.isFolder) this.openDetail(item); else void this.play(item) })
      }, (item: EmbyItem) => this.source.id + ':featured:' + item.id)
      }
      .width('100%').height(this.featuredHeight())
      .index(this.featuredIndex)
      .indicator(false).autoPlay(this.isActive && this.foreground && this.featuredItems().length > 1).interval(5000)
      .loop(this.featuredItems().length > 1).duration(500).itemSpace(0)
      .onChange((index: number) => this.onFeaturedChanged(index))

      if (this.featuredItems().length > 1) {
        Row({ space: 6 }) {
          ForEach(this.featuredItems(), (item: EmbyItem, index: number) => {
            Row()
              .width(index === this.featuredIndex ? 20 : 8)
              .height(4).borderRadius(2)
              .backgroundColor(index === this.featuredIndex ? Color.White : '#99FFFFFF')
              .animation({ duration: 200, curve: Curve.EaseOut })
          }, (item: EmbyItem) => this.source.id + ':featured-dot:' + item.id)
        }.margin({ bottom: 16, left: 20 })
      }
    }
    .width('calc(100% + ' + String(this.pagePadding() * 2) + 'vp)')
    .margin({ left: -this.pagePadding(), right: -this.pagePadding() })
    .height(this.featuredHeight())
  }

  @Builder
  private Section(section: EmbyHomeSection): void {
    Column({ space: 14 }) {
      MediaSectionHeader({ title: section.title, actionText: '全部',
        onAction: () => this.openLibrary(section.id, section.title, section.collectionType) })
      if (section.error.length > 0) this.RetryNotice('此栏目暂未更新')
      if (section.items.length === 0 && section.loading) {
        PageLoadingState({ title: '正在读取' + section.title, minHeight: 150 })
      } else {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(section.items, (item: EmbyItem) => {
              this.Poster(item)
            }, (item: EmbyItem) => this.source.id + ':' + section.id + ':' + item.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }.width('100%')
  }

  @Builder
  private Libraries(): void {
    if (this.snapshot.librariesError.length > 0) this.RetryNotice('媒体库暂未更新')
    if (this.snapshot.libraries.length === 0 && this.snapshot.librariesLoading) {
      PageLoadingState({ title: '正在读取媒体库', minHeight: 250 })
    } else if (this.snapshot.libraries.length === 0 && this.snapshot.librariesError.length === 0) {
      PageEmptyState({ title: '此服务暂无媒体库', minHeight: 220 })
    } else {
      Grid() {
        ForEach(this.snapshot.libraries, (library: EmbyItem) => {
          GridItem() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 12 }) {
                Image(this.artwork(library, false).length > 0 ? this.artwork(library, false) : $r('app.media.ic_placeholder'))
                  .width('100%').aspectRatio(1.8).objectFit(ImageFit.Cover).borderRadius(16)
                Text(library.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(EmbyLibraryPresentation.contentLabel(library.collectionType)).fontSize(13)
                  .fontColor($r('app.color.text_secondary')).width('100%')
              }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').backgroundColor($r('app.color.card_background')).borderRadius(22)
              .onClick(() => this.openLibrary(library.id, library.name, library.collectionType))
          }
        }, (library: EmbyItem) => library.id)
      }.columnsTemplate(this.screenWidth >= 840 ? '1fr 1fr 1fr' : '1fr 1fr').columnsGap(14).rowsGap(14).width('100%').scrollBar(BarState.Off)
    }
  }

  @Builder
  private PosterGrid(items: EmbyItem[]): void {
    Grid() {
      ForEach(items, (item: EmbyItem) => {
        GridItem() { this.Poster(item) }
      }, (item: EmbyItem) => this.source.id + ':search:' + item.id)
    }.columnsTemplate('1fr '.repeat(ResponsiveSizeClassResolver.columns(this.screenWidth)).trim())
      .columnsGap(12).rowsGap(18).width('100%').scrollBar(BarState.Off)
  }

  @Builder
  private Poster(item: EmbyItem): void {
    MediaPosterCard({ title: item.name, subtitle: item.subtitle(), artworkUrl: this.artwork(item, false),
      cardWidth: ResponsiveSizeClassResolver.posterWidth(this.screenWidth),
      enableSharedTransition: true,
      onCardClick: (transitionId: string) => this.openDetail(item, transitionId, this.artwork(item, false)) })
  }

  @Builder
  private RetryNotice(message: string): void {
    Button(message + ' · 重试', { type: ButtonType.Normal }).width('100%').constraintSize({ minHeight: 44 })
      .fontSize(14).fontColor($r('app.color.text_secondary')).backgroundColor($r('app.color.card_background'))
      .borderRadius(14).onClick(() => { void this.refresh() })
  }

  private featuredItems(): EmbyItem[] {
    const result: EmbyItem[] = []
    const seen: Set<string> = new Set()
    for (const section of this.snapshot.sections) {
      for (const item of section.items) {
        if (item.isFolder) continue
        if (seen.has(item.id)) continue
        seen.add(item.id)
        result.push(item)
        if (result.length >= 6) return result
      }
    }
    return result
  }
  private otherResume(): EmbyItem[] { return this.snapshot.resumeItems }
  private featuredHeight(): number {
    const width = Number.isFinite(this.screenWidth) && this.screenWidth > 0 ? this.screenWidth : 360
    const base = width >= 840 ? 360 : (width >= 600 ? 340 : 300)
    return base + getTopSpacerHeight(this.topSafeHeight)
  }
  private featuredTopPadding(): number { return this.topSafeHeight > 0 ? getTopSpacerHeight(this.topSafeHeight) + 24 : 60 }
  private featuredBottomPadding(): number { return this.screenWidth >= 600 ? 54 : 48 }
  private pagePadding(): number { return ResponsiveSizeClassResolver.pagePadding(this.screenWidth) }
  private artwork(item: EmbyItem, landscape: boolean): string {
    if (this.provider === null) return ''
    return landscape ? this.provider.backdropUrlFor(item, 1200) || this.provider.thumbnailUrlFor(item, 900) ||
      this.provider.imageUrlFor(item, 900) : this.provider.imageUrlFor(item, 500)
  }
  private openLibrary(id: string, title: string, type: string): void {
    const params: Record<string, Object> = { 'sourceId': this.source.id, 'parentId': id,
      'title': title, 'libraryRoot': true, 'collectionType': type }
    void this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyLibraryPage',
      params: params })
  }
  private openResumeList(): void {
    void this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyLibraryPage',
      params: { sourceId: this.source.id, view: 'resume', title: '继续观看' } })
  }
  private openDetail(item: EmbyItem, artworkTransitionId: string = '', transitionArtworkUrl: string = ''): void {
    const params = buildEmbyDetailRouteParams(this.source.id, item, artworkTransitionId, transitionArtworkUrl)
    if (item.type === 'CollectionFolder' || item.type === 'Folder') this.openLibrary(item.id, item.name, item.collectionType)
    else void this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyDetailPage', params: params })
  }
  private async play(item: EmbyItem): Promise<void> {
    if (this.playing || this.provider === null) return
    this.playing = true
    const generation = this.generation
    try {
      let queue: EmbyItem[] = [item]
      if (item.type === 'Episode' && (item.seasonId || item.parentId).length > 0) {
        try { const episodes = await this.provider.getSeasonEpisodesRaw(item.seriesId, item.seasonId || item.parentId)
          if (episodes.some((episode: EmbyItem) => episode.id === item.id)) queue = episodes
        } catch (_) {}
      }
      if (generation !== this.generation || !this.isActive) return
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.source.id, item, queue, EmbyDetailPresentation.watched(item))
    } catch (_) { this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('无法播放，请重试')) }
    finally { this.playing = false }
  }

  private toggleSearch(): void {
    this.showSearch = !this.showSearch; this.query = ''; this.cancelSearch(); void this.updateFeaturedColor()
  }
  private cancelSearch(): void { this.searchGeneration++; if (this.searchTimer >= 0) clearTimeout(this.searchTimer); this.searchTimer = -1; this.searching = false }
  private search(value: string): void {
    this.cancelSearch(); this.query = value; this.searchItems = []; this.searchError = ''
    void this.updateFeaturedColor()
    if (value.trim().length === 0) return
    this.searching = true
    const generation = this.searchGeneration
    this.searchTimer = setTimeout(() => { void this.runSearch(value.trim(), generation) }, 260)
  }
  private async runSearch(query: string, generation: number): Promise<void> {
    try {
      if (this.provider === null) throw new Error('Service unavailable')
      const items = await this.provider.searchRaw(query)
      if (generation === this.searchGeneration) this.searchItems = items
    } catch (_) { if (generation === this.searchGeneration) this.searchError = '无法连接当前服务' }
    finally { if (generation === this.searchGeneration) this.searching = false }
  }
  private savePosition(): void {
    if (this.restorePending || this.query.length > 0) return
    const position = homePositions.get(this.memoryKey()) ?? new HomePosition()
    position.overviewOffset = this.scroller.currentOffset().yOffset
    homePositions.set(this.memoryKey(), position)
  }
  private restorePosition(): void {
    if (!this.restorePending || this.snapshot.librariesLoading) return
    const position = homePositions.get(this.memoryKey()) ?? new HomePosition()
    if (position.overviewOffset > 0 &&
      (this.snapshot.resumeLoading || this.snapshot.sections.some((section: EmbyHomeSection) => section.loading))) return
    this.scroller.scrollTo({ xOffset: 0, yOffset: position.overviewOffset })
    this.restorePending = false
  }
}
