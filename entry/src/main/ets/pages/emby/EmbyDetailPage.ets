import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode, IconStyleMode } from '@kit.UIDesignKit'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { buildTitleBarOptions, buildImmersiveTitleBarStyle, getDetailContentMaxWidth, isWideDetailLayout,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { MediaPosterCard } from '../../components/media/MediaPosterCard'
import { EpisodeRow } from '../../components/media/EpisodeRow'
import { EmbyDetailPresentation } from '../../providers/emby/EmbyDetailPresentation'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSurface } from '../../ui/theme/AppSurface'
import { ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { ImmersiveDetailStage } from '../../components/media/ImmersiveDetailStage'

@Entry
@Component
struct EmbyDetailPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private sourceId: string = ''
  @State private itemId: string = ''
  @State private initialSeasonId: string = ''
  @State private initialEpisodeId: string = ''
  @State private initialEpisodeIndex: number = 0
  @State private item: EmbyItem | null = null
  @State private loading: boolean = true
  @State private errorText: string = ''
  @State private playing: boolean = false
  @State private seasonItems: EmbyItem[] = []
  @State private episodeItems: EmbyItem[] = []
  @State private collectionItems: EmbyItem[] = []
  @State private selectedSeasonId: string = ''
  @State private playbackVariants: PlaybackVariant[] = []
  @State private selectedVariantId: string = 'auto'
  @State private ambientArtworkUrl: string = ''
  @State private detailScrollOffset: number = 0
  @State private totalEpisodeCount: number = 0
  @State private currentSeasonEpisodeCount: number = 0
  @State private episodeRangeStart: number = 0
  @State private showDetailSheet: boolean = false
  @State private sheetKind: string = 'season'
  @State private aboutSelected: boolean = false
  @State private overviewExpanded: boolean = false
  @State private hideSpoilers: boolean = false
  @State private episodesLoading: boolean = false
  @State private episodesError: string = ''
  @State private loadingMore: boolean = false
  @State private playbackTarget: EmbyItem | null = null
  @State private targetLoading: boolean = false
  @State private heroHeight: number = 480
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  private provider: EmbyProvider | null = null
  private seasonLoadGeneration: number = 0
  private detailLoadGeneration: number = 0
  private scroller: Scroller = new Scroller()
  private heroScroller: Scroller = new Scroller()
  private sheetScroller: Scroller = new Scroller()
  private playbackGeneration: number = 0
  private targetGeneration: number = 0
  private userSelectedSeason: boolean = false
  private readonly EPISODE_PAGE_SIZE: number = 20

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['itemId'] === 'string') this.itemId = (params['itemId'] as string).trim()
      if (typeof params['initialSeasonId'] === 'string') {
        this.initialSeasonId = (params['initialSeasonId'] as string).trim()
      }
      if (typeof params['initialEpisodeId'] === 'string') {
        this.initialEpisodeId = (params['initialEpisodeId'] as string).trim()
      }
      if (typeof params['initialEpisodeIndex'] === 'number') {
        this.initialEpisodeIndex = Math.max(0, Math.floor(params['initialEpisodeIndex'] as number))
      }
    }
    void this.loadItem()
  }

  onPageShow(): void {
    if (this.item !== null && !this.loading) void this.refreshWatchState()
  }

  aboutToDisappear(): void {
    this.detailLoadGeneration++
    this.seasonLoadGeneration++
    this.targetGeneration++
    this.playbackGeneration++
  }

  private async refreshWatchState(): Promise<void> {
    if (this.provider === null || this.item === null) return
    const generation = this.detailLoadGeneration
    const itemId = this.item.id
    try {
      const fresh = await this.provider.getItemRaw(itemId)
      if (generation !== this.detailLoadGeneration || fresh === null) return
      fresh.variantId = this.item === null ? '' : this.item.variantId
      this.item = fresh
      if (this.isEpisodeContainer(fresh)) {
        void this.loadPlaybackTarget(fresh, generation)
        if (!this.episodesLoading && !this.loadingMore) void this.refreshVisibleEpisodes()
      } else {
        void this.loadPlaybackVariants(this.provider, fresh, generation)
      }
    } catch (_) {
      // Keep the visible metadata and watch state when the server is temporarily unavailable.
    }
  }

  build() {
    HdsNavigation() {
      if (this.loading) {
        Column() {
          PageLoadingState({ title: '正在读取媒体详情', minHeight: 300 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0 || this.item === null) {
        Column() {
          PageErrorState({ title: '媒体详情不可用', message: this.errorText.length > 0 ? this.errorText : '媒体不存在',
            onRetry: () => this.loadItem() })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        this.DetailContent(this.item!)
      }
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.item === null ? '媒体详情' : this.item!.name, this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
      .bindToScrollable([this.scroller, this.heroScroller])
      .bindSheet($$this.showDetailSheet, this.SelectionSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: isWideDetailLayout(this.screenWidthVp) ? SheetType.CENTER : SheetType.BOTTOM,
        width: isWideDetailLayout(this.screenWidthVp) ? 560 : '100%',
        showClose: false, dragBar: true,
        backgroundColor: AppSurface.color(AppSurface.SURFACE),
        onDisappear: () => { this.showDetailSheet = false }
      })
  }

  @Builder
  private DetailContent(item: EmbyItem): void {
    Stack({ alignContent: Alignment.Bottom }) {
      if (isWideDetailLayout(this.screenWidthVp)) {
        Row({ space: AppSpacing.XL }) {
          Scroll(this.heroScroller) {
            Column({ space: AppSpacing.MD }) {
              this.Hero(item, true)
              this.OverviewSection(item)
            }.width('100%').alignItems(HorizontalAlign.Start)
              .padding({ bottom: 24 + this.bottomSafeHeight })
          }.width('40%').height('100%').scrollBar(BarState.Off)
          Scroll(this.scroller) {
            Column() { this.DetailSections(item) }.width('100%')
              .padding({ bottom: 24 + this.bottomSafeHeight })
          }.layoutWeight(1).height('100%').scrollBar(BarState.Auto)
        }.width('100%').height('100%').alignItems(VerticalAlign.Top)
          .constraintSize({ maxWidth: getDetailContentMaxWidth(this.screenWidthVp) })
          .padding(ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp))
      } else {
        Scroll(this.scroller) {
          Column({ space: AppSpacing.LG }) {
            this.Hero(item, false)
            Column({ space: AppSpacing.LG }) {
              this.DetailSections(item)
            }.width('100%').padding({ left: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
              right: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp) })
          }.width('100%').padding({ bottom: 112 + this.bottomSafeHeight })
        }.width('100%').height('100%').scrollBar(BarState.Off)
          .onDidScroll(() => {
            this.detailScrollOffset = Math.max(0, this.scroller.currentOffset().yOffset)
          })
      }
      if (!isWideDetailLayout(this.screenWidthVp) && this.detailScrollOffset > this.heroHeight &&
        this.canPlay(item)) this.PlaybackDock(item)
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Hero(item: EmbyItem, wide: boolean): void {
    Column() {
      ImmersiveDetailStage({
        backdropUrl: this.ambientArtworkUrl, posterUrl: this.imageUrl(item),
        title: item.name, meta: this.metaText(item), artworkMode: this.ambientArtworkMode(item),
        actionText: this.primaryActionText(item), actionDescription: this.actionDescription(item),
        actionEnabled: this.canPlay(item), busy: this.playing, progress: this.actionProgress(item),
        variantLabel: this.playbackVariants.length > 1 ? this.selectedVariantLabel() : '',
        wide: wide, contentPadding: wide ? 0 : ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
        sharedTransitionId: this.artworkSharedTransitionId(item),
        onPrimaryAction: () => this.handlePrimaryAction(item),
        onVariantAction: () => this.openVariantMenu()
      })
    }.width('100%').onAreaChange((_oldArea: Area, newArea: Area) => {
      this.heroHeight = Number(newArea.height)
    })
  }

  @Builder
  private PlaybackDock(item: EmbyItem): void {
    Row({ space: AppSpacing.MD }) {
      Column({ space: 4 }) {
        Text(item.name).fontSize(AppTypography.BODY_LARGE).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.actionDescription(item)).fontSize(AppTypography.META)
          .fontColor($r('app.color.text_secondary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button(this.playing ? '准备中' : this.primaryActionText(item), { type: ButtonType.Capsule })
        .fontSize(AppTypography.BODY).constraintSize({ minHeight: 48, maxWidth: 144 })
        .backgroundColor($r('app.color.accent_blue')).fontColor($r('app.color.text_on_primary'))
        .enabled(!this.playing).onClick(() => this.handlePrimaryAction(item))
    }.width('100%').padding(AppSpacing.MD).borderRadius(AppRadius.SURFACE)
      .backgroundColor(AppSurface.color(AppSurface.SURFACE))
      .margin({ bottom: this.bottomSafeHeight + AppSpacing.SM })
      .constraintSize({ maxWidth: Math.max(280, this.screenWidthVp - 32) })
  }

  @Builder
  private OverviewSection(item: EmbyItem): void {
    if (item.overview.length > 0) {
      Column({ space: AppSpacing.SM }) {
        MediaSectionHeader({ title: '简介' })
        Text(item.overview).fontSize(AppTypography.BODY_LARGE)
          .fontColor($r('app.color.text_primary')).lineHeight(26)
          .maxLines(this.overviewExpanded ? 1000 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Button(this.overviewExpanded ? '收起简介' : '展开简介', { type: ButtonType.Normal })
          .fontSize(AppTypography.BODY).fontColor($r('app.color.accent_blue'))
          .backgroundColor(Color.Transparent).constraintSize({ minHeight: 44 })
          .onClick(() => { this.overviewExpanded = !this.overviewExpanded })
      }.width('100%').padding(AppSpacing.MD).alignItems(HorizontalAlign.Start)
        .borderRadius(AppRadius.SURFACE).backgroundColor(AppSurface.color(AppSurface.SURFACE))
    }
  }

  @Builder
  private DetailSections(item: EmbyItem): void {
    Column({ space: AppSpacing.MD }) {
      if (this.isEpisodeContainer(item)) {
        Row({ space: AppSpacing.LG }) {
          this.SectionTab('剧集', false)
          this.SectionTab('关于作品', true)
        }.width('100%')
        if (!this.aboutSelected) {
          this.EpisodeSection()
        } else {
          if (!isWideDetailLayout(this.screenWidthVp)) this.OverviewSection(item)
          this.DetailInfoSection(item)
          Row() {
            Text('隐藏未看剧集内容').fontSize(AppTypography.BODY_LARGE)
              .fontColor($r('app.color.text_primary')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.hideSpoilers })
              .onChange((enabled: boolean) => { this.hideSpoilers = enabled })
              .accessibilityText('隐藏未看剧集内容')
          }.width('100%').padding(AppSpacing.MD).borderRadius(AppRadius.SURFACE)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE))
        }
      } else {
        if (!isWideDetailLayout(this.screenWidthVp)) this.OverviewSection(item)
        if (this.collectionItems.length > 0) this.CollectionSection()
        this.DetailInfoSection(item)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SectionTab(label: string, about: boolean): void {
    Button({ type: ButtonType.Normal }) {
      Text(label).fontSize(AppTypography.FEATURE_TITLE)
        .fontWeight(this.aboutSelected === about ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.aboutSelected === about ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .padding({ top: 12, bottom: 12 })
    }.backgroundColor(Color.Transparent)
      .border({ width: { bottom: this.aboutSelected === about ? 3 : 0 }, color: $r('app.color.accent_blue') })
      .accessibilityText(label + (this.aboutSelected === about ? '，已选中' : ''))
      .onClick(() => { this.aboutSelected = about })
  }

  @Builder
  private DetailInfoSection(item: EmbyItem): void {
    Column({ space: 6 }) {
      MediaSectionHeader({ title: '更多信息' })
      Column() {
        this.DetailInfoRow('类型', EmbyItem.typeLabel(item.type),
          item.productionYear > 0 || item.type === 'Series' || item.type === 'Season' || item.durationMs() > 0 || item.container.length > 0)
        if (item.productionYear > 0) {
          this.DetailInfoRow('年份', String(item.productionYear),
            item.type === 'Series' || item.type === 'Season' || item.durationMs() > 0 || item.container.length > 0)
        }
        if (item.type === 'Series') {
          if (this.seriesSeasonCount(item) > 0) this.DetailInfoRow('季数', String(this.seriesSeasonCount(item)) + ' 季', this.seriesEpisodeCount(item) > 0)
          if (this.seriesEpisodeCount(item) > 0) this.DetailInfoRow('总集数', String(this.seriesEpisodeCount(item)) + ' 集', false)
        } else if (item.type === 'Season' && this.currentSeasonEpisodeCount > 0) {
          this.DetailInfoRow('集数', String(this.currentSeasonEpisodeCount) + ' 集', item.container.length > 0 || item.durationMs() > 0)
        }
        if (item.durationMs() > 0) {
          this.DetailInfoRow('时长', this.formatDuration(item.durationMs()), item.container.length > 0)
        }
        if (item.container.length > 0) this.DetailInfoRow('格式', item.container.toUpperCase(), false)
      }
      .width('100%')
      .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM, left: AppSpacing.MD, right: AppSpacing.MD })
      .borderRadius(AppRadius.SURFACE)
      .backgroundColor(AppSurface.color(AppSurface.SURFACE))
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailInfoRow(label: string, value: string, showDivider: boolean = true): void {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).width(64)
      Text(value).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ top: 7, bottom: 7 })
    .border({ width: { bottom: showDivider ? 0.5 : 0 }, color: $r('app.color.divider_color') })
  }



  private async loadItem(): Promise<void> {
    this.seasonLoadGeneration++
    const generation = ++this.detailLoadGeneration
    this.targetGeneration++
    this.loading = true
    this.errorText = ''
    this.item = null
    this.ambientArtworkUrl = ''
    this.detailScrollOffset = 0
    this.playbackVariants = []
    this.selectedVariantId = 'auto'
    this.seasonItems = []
    this.episodeItems = []
    this.collectionItems = []
    this.selectedSeasonId = ''
    this.totalEpisodeCount = 0
    this.currentSeasonEpisodeCount = 0
    this.episodeRangeStart = 0
    this.episodesError = ''
    this.episodesLoading = false
    this.loadingMore = false
    this.playbackTarget = null
    this.targetLoading = false
    this.overviewExpanded = false
    this.aboutSelected = false
    this.userSelectedSeason = false
    this.showDetailSheet = false
    try {
      if (this.sourceId.length === 0 || this.itemId.length === 0) throw new Error('媒体参数无效')
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (generation !== this.detailLoadGeneration) return
      if (provider === null || !(provider instanceof EmbyProvider)) throw new Error('Emby 来源不可用')
      const loadedItem = await provider.getItemRaw(this.itemId)
      if (generation !== this.detailLoadGeneration) return
      if (loadedItem === null) throw new Error('媒体不存在或已被删除')
      this.provider = provider
      this.item = loadedItem
      this.ambientArtworkUrl = this.ambientRenderArtworkUrl(loadedItem)
      // Metadata paints independently of season, episode and playback-info requests.
      this.loading = false
      if (this.isEpisodeContainer(loadedItem)) {
        this.episodesLoading = true
        void this.loadContainer(loadedItem, generation)
        void this.loadPlaybackTarget(loadedItem, generation)
      } else if (loadedItem.type === 'BoxSet') {
        try {
          const children = await provider.getItemsRaw(loadedItem.id)
          if (generation === this.detailLoadGeneration) {
            this.collectionItems = children.filter((entry: EmbyItem) =>
              entry.type !== 'Folder' && entry.type !== 'CollectionFolder')
          }
        } catch (_) {
          if (generation === this.detailLoadGeneration) promptAction.showToast({ message: '合集内容读取失败' })
        }
      } else if (!loadedItem.isFolder) {
        void this.loadPlaybackVariants(provider, loadedItem, generation)
      }
    } catch (err) {
      if (generation === this.detailLoadGeneration) {
        this.errorText = err instanceof Error ? err.message : '媒体详情读取失败'
      }
    } finally {
      if (generation === this.detailLoadGeneration) this.loading = false
    }
  }

  private async loadContainer(item: EmbyItem, generation: number): Promise<void> {
    if (this.provider === null) return
    this.episodesLoading = true
    this.episodesError = ''
    try {
      if (item.type === 'Series') {
        const seasons = await this.provider.getSeriesSeasonsRaw(item.id)
        if (generation !== this.detailLoadGeneration) return
        this.seasonItems = seasons.filter((entry: EmbyItem) => entry.type === 'Season')
        this.sortByIndex(this.seasonItems)
        this.totalEpisodeCount = item.recursiveItemCount
        if (this.seasonItems.length > 0) this.selectedSeasonId = this.initialSeason(this.seasonItems).id
        void this.loadEpisodeCount(this.provider, item, generation)
      } else {
        this.selectedSeasonId = item.id
      }
      if (this.selectedSeasonId.length > 0) {
        await this.loadEpisodes(this.initialEpisodePageStart())
      }
    } catch (_) {
      if (generation === this.detailLoadGeneration) this.episodesError = '无法读取剧集，请重试'
    } finally {
      if (generation === this.detailLoadGeneration && this.selectedSeasonId.length === 0) this.episodesLoading = false
    }
  }

  private async retryEpisodes(): Promise<void> {
    if (this.item === null) return
    if (this.selectedSeasonId.length === 0) await this.loadContainer(this.item, this.detailLoadGeneration)
    else await this.loadEpisodes(this.episodeRangeStart)
  }

  private async loadPlaybackTarget(item: EmbyItem, detailGeneration: number): Promise<void> {
    if (this.provider === null) return
    const generation = ++this.targetGeneration
    this.targetLoading = true
    try {
      const explicit = this.initialEpisodeId.length > 0 ? await this.provider.getItemRaw(this.initialEpisodeId) : null
      const target = explicit !== null && explicit.type === 'Episode' ?
        explicit : await this.provider.getDetailPlaybackTargetRaw(item.id)
      if (generation !== this.targetGeneration || detailGeneration !== this.detailLoadGeneration) return
      if (target !== null && this.playbackTarget !== null && this.playbackTarget.id === target.id) {
        target.variantId = this.playbackTarget.variantId
      }
      this.playbackTarget = target !== null ? target : EmbyDetailPresentation.preferred(this.episodeItems)
      if (this.playbackTarget !== null) void this.loadPlaybackVariants(this.provider, this.playbackTarget, detailGeneration)
    } catch (_) {
      // Keep an existing target while a refresh is unavailable.
      if (generation === this.targetGeneration && detailGeneration === this.detailLoadGeneration &&
        this.playbackTarget === null) {
        this.playbackTarget = EmbyDetailPresentation.preferred(this.episodeItems, this.initialEpisodeId)
      }
    } finally {
      if (generation === this.targetGeneration && detailGeneration === this.detailLoadGeneration) {
        this.targetLoading = false
      }
    }
  }

  private async loadEpisodes(start: number, append: boolean = false): Promise<void> {
    if (this.provider === null || this.item === null || this.selectedSeasonId.length === 0) return
    const generation = ++this.seasonLoadGeneration
    const seasonId = this.selectedSeasonId
    const seriesId = this.item.type === 'Series' ? this.item.id : this.item.seriesId
    this.episodesError = ''
    this.loadingMore = append
    this.episodesLoading = !append
    if (!append) {
      this.episodeItems = []
      this.episodeRangeStart = start
    }
    try {
      let page = await this.provider.getSeasonEpisodesPageRaw(seriesId, seasonId, start, this.EPISODE_PAGE_SIZE)
      if (generation !== this.seasonLoadGeneration) return
      if (!append && page.items.length === 0 && start > 0) {
        page = await this.provider.getSeasonEpisodesPageRaw(seriesId, seasonId, 0, this.EPISODE_PAGE_SIZE)
        if (generation !== this.seasonLoadGeneration) return
        this.episodeRangeStart = 0
      }
      const items = page.items.filter((entry: EmbyItem) => entry.type === 'Episode')
      if (append) {
        const ids = this.episodeItems.map((entry: EmbyItem) => entry.id)
        this.episodeItems = this.episodeItems.concat(items.filter((entry: EmbyItem) => ids.indexOf(entry.id) < 0))
      } else {
        this.episodeItems = items
      }
      this.currentSeasonEpisodeCount = items.length === 0 && append ? start :
        Math.max(page.totalRecordCount, this.episodeRangeStart + this.episodeItems.length)
      this.sortByIndex(this.episodeItems)
      if (this.playbackTarget === null && !this.targetLoading) {
        this.playbackTarget = EmbyDetailPresentation.preferred(this.episodeItems, this.initialEpisodeId)
        if (this.playbackTarget !== null) {
          void this.loadPlaybackVariants(this.provider, this.playbackTarget, this.detailLoadGeneration)
        }
      }
    } catch (_) {
      if (generation === this.seasonLoadGeneration) this.episodesError = '无法读取剧集，请重试'
    } finally {
      if (generation === this.seasonLoadGeneration) {
        this.episodesLoading = false
        this.loadingMore = false
      }
    }
  }

  private async loadMoreEpisodes(): Promise<void> {
    if (this.episodesLoading || this.loadingMore) return
    await this.loadEpisodes(this.episodeRangeStart + this.episodeItems.length, true)
  }

  private async refreshVisibleEpisodes(): Promise<void> {
    if (this.provider === null || this.item === null || this.selectedSeasonId.length === 0 ||
      this.episodeItems.length === 0) return
    const generation = this.seasonLoadGeneration
    const detailGeneration = this.detailLoadGeneration
    const seasonId = this.selectedSeasonId
    const seriesId = this.item.type === 'Series' ? this.item.id : this.item.seriesId
    try {
      const page = await this.provider.getSeasonEpisodesPageRaw(seriesId, seasonId,
        this.episodeRangeStart, this.episodeItems.length)
      if (generation !== this.seasonLoadGeneration || detailGeneration !== this.detailLoadGeneration) return
      // Update matching rows in place so returning from playback preserves the loaded range and scroll position.
      this.episodeItems = this.episodeItems.map((existing: EmbyItem) => {
        const fresh = page.items.find((entry: EmbyItem) => entry.id === existing.id)
        return fresh === undefined ? existing : fresh
      })
    } catch (_) {
      // A failed background refresh leaves the visible list available.
    }
  }

  private async loadEpisodeCount(provider: EmbyProvider, loadedItem: EmbyItem,
    loadGeneration: number): Promise<void> {
    if (loadedItem.recursiveItemCount > 0) return
    try {
      const count = await provider.getEpisodeCount(loadedItem.id)
      if (loadGeneration !== this.detailLoadGeneration || this.item !== loadedItem) return
      this.totalEpisodeCount = Math.max(0, count)
    } catch (_) {
      if (loadGeneration === this.detailLoadGeneration && this.item === loadedItem) {
        this.totalEpisodeCount = 0
      }
    }
  }

  private async loadPlaybackVariants(provider: EmbyProvider, loadedItem: EmbyItem,
    loadGeneration: number): Promise<void> {
    const generation = ++this.playbackGeneration
    this.playbackVariants = []
    this.selectedVariantId = loadedItem.variantId.length > 0 ? loadedItem.variantId : 'auto'
    try {
      const variants = await provider.getPlaybackVariants(loadedItem)
      if (generation !== this.playbackGeneration || loadGeneration !== this.detailLoadGeneration ||
        this.item === null || this.actionItem(this.item) !== loadedItem) return
      loadedItem.variants = variants
      if (variants.length > 1) {
        const auto = new PlaybackVariant()
        auto.id = 'auto'
        auto.name = '自动'
        this.playbackVariants = [auto].concat(variants)
      }
    } catch (_) {
      // Automatic playback stays available while version metadata is unavailable.
    }
  }

  private imageUrl(item: EmbyItem): string {
    return this.itemProvider() === null ? '' : this.itemProvider()!.imageUrlFor(item, 900)
  }

  private ambientRenderArtworkUrl(item: EmbyItem): string {
    const provider = this.itemProvider()
    if (provider === null) return ''

    const backdrop = provider.backdropUrlFor(item, 1400)
    if (backdrop.length > 0) return backdrop

    const thumbnail = provider.thumbnailUrlFor(item, 1200)
    if (thumbnail.length > 0) return thumbnail

    return provider.imageUrlFor(item, 800)
  }

  private artworkSharedTransitionId(item: EmbyItem): string {
    return 'emby_artwork_' + this.sourceId + '_' + item.id
  }

  private ambientArtworkMode(item: EmbyItem): string {
    const provider = this.itemProvider()
    if (provider === null) return 'none'
    if (provider.backdropUrlFor(item, 1200).length > 0) return 'backdrop'
    if (provider.thumbnailUrlFor(item, 900).length > 0) return 'thumbnail'
    if (provider.imageUrlFor(item, 900).length > 0) return 'poster'
    return 'none'
  }



  private itemProvider(): EmbyProvider | null {
    return this.provider
  }

  private metaText(item: EmbyItem): string {
    const parts: string[] = []
    if (item.productionYear > 0) parts.push(String(item.productionYear))
    parts.push(EmbyItem.typeLabel(item.type))
    if (item.type === 'Series') {
      const seasons = this.seasonItems.length > 0 ? this.seasonItems.length : item.seasonCount
      if (seasons > 0) parts.push(String(seasons) + ' 季')
      const episodes = this.totalEpisodeCount > 0 ? this.totalEpisodeCount : item.recursiveItemCount
      if (episodes > 0) parts.push(String(episodes) + ' 集')
    } else if (item.type === 'Season') {
      if (item.indexNumber > 0) parts[0] = '第 ' + item.indexNumber + ' 季'
      if (this.currentSeasonEpisodeCount > 0) parts.push(String(this.currentSeasonEpisodeCount) + ' 集')
    } else if (item.type === 'Episode') {
      if (item.parentIndexNumber > 0 && item.indexNumber > 0) {
        parts[0] = '第 ' + item.parentIndexNumber + ' 季 · 第 ' + item.indexNumber + ' 集'
      }
      if (item.durationMs() > 0) parts.push(this.formatDuration(item.durationMs()))
    } else if (item.durationMs() > 0) {
      parts.push(this.formatDuration(item.durationMs()))
    }
    return parts.join(' · ')
  }

  private seriesSeasonCount(item: EmbyItem): number {
    return this.seasonItems.length > 0 ? this.seasonItems.length : item.seasonCount
  }

  private seriesEpisodeCount(item: EmbyItem): number {
    return this.totalEpisodeCount > 0 ? this.totalEpisodeCount : item.recursiveItemCount
  }

  private isEpisodeContainer(item: EmbyItem): boolean {
    return item.type === 'Series' || item.type === 'Season'
  }

  private actionItem(item: EmbyItem): EmbyItem | null {
    return this.isEpisodeContainer(item) ? this.playbackTarget : item.isFolder ? null : item
  }

  private canPlay(item: EmbyItem): boolean {
    return this.actionItem(item) !== null
  }

  private primaryActionText(item: EmbyItem): string {
    if (item.type === 'BoxSet') return ''
    const target = this.actionItem(item)
    if (target !== null) return EmbyDetailPresentation.actionLabel(target)
    return this.targetLoading ? '正在读取播放进度' : '暂无可播放内容'
  }

  private actionDescription(item: EmbyItem): string {
    const target = this.actionItem(item)
    return target === null ? '' : EmbyDetailPresentation.actionDescription(target)
  }

  private actionProgress(item: EmbyItem): number {
    const target = this.actionItem(item)
    return target === null ? 0 : EmbyDetailPresentation.progress(target)
  }

  private handlePrimaryAction(item: EmbyItem): void {
    const target = this.actionItem(item)
    if (target === null) return
    if (target.type === 'Episode') void this.playEpisode(target)
    else void this.play(target)
  }

  @Builder
  private EpisodeSection(): void {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.SM }) {
        if (this.seasonItems.length > 0) {
          Button({ type: ButtonType.Capsule }) {
            Row({ space: AppSpacing.SM }) {
              Text(this.selectedSeasonLabel()).fontSize(AppTypography.BODY)
                .fontColor($r('app.color.text_primary')).maxLines(2)
              SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(14)
                .fontColor([$r('app.color.text_secondary')]).accessibilityLevel('no')
            }.padding(12)
          }.backgroundColor(AppSurface.color(AppSurface.SURFACE))
            .constraintSize({ minHeight: 44, maxWidth: '65%' })
            .onClick(() => this.openSeasonSheet())
        }
        Blank()
        if (this.currentSeasonEpisodeCount > 0) {
          Text('共 ' + this.currentSeasonEpisodeCount + ' 集').fontSize(AppTypography.META)
            .fontColor($r('app.color.text_secondary'))
        }
      }.width('100%')
      if (this.currentSeasonEpisodeCount > this.EPISODE_PAGE_SIZE) {
        Button('快速选集 · ' + this.episodeRangeLabel(), { type: ButtonType.Normal })
          .fontSize(AppTypography.BODY).fontColor($r('app.color.accent_blue'))
          .backgroundColor(Color.Transparent).constraintSize({ minHeight: 44 })
          .onClick(() => this.openEpisodeRangeSheet())
      }
      if (this.episodesLoading) {
        PageLoadingState({ title: '正在读取剧集', minHeight: 160 })
      } else if (this.episodesError.length > 0 && this.episodeItems.length === 0) {
        PageErrorState({ title: '剧集暂不可用', message: this.episodesError,
          onRetry: () => { void this.retryEpisodes() } })
      } else if (this.episodeItems.length === 0) {
        Text(this.selectedSeasonId.length > 0 ? '这一季暂无剧集' : '暂无剧集').fontSize(AppTypography.BODY_LARGE)
          .fontColor($r('app.color.text_secondary')).padding({ top: 32, bottom: 32 }).width('100%')
      } else {
        Column() {
          ForEach(this.visibleEpisodeItems(), (episode: EmbyItem, index: number) => {
            EpisodeRow({
              indexLabel: episode.indexNumber > 0 ? String(episode.indexNumber).padStart(2, '0') :
                String(this.episodeRangeStart + index + 1),
              title: episode.name, meta: this.episodeMeta(episode),
              artworkUrl: this.episodeArtworkUrl(episode), progress: this.episodeProgress(episode),
              played: EmbyDetailPresentation.watched(episode),
              isResumeTarget: this.isResumeTarget(episode),
              hideSpoiler: this.hideSpoilers && !EmbyDetailPresentation.watched(episode),
              playbackEnabled: !this.playing, showDivider: index < this.episodeItems.length - 1,
              onRowClick: () => { void this.playEpisode(episode) }
            })
          }, (episode: EmbyItem) => 'detail_episode_' + episode.id)
        }.width('100%').padding({ left: AppSpacing.MD, right: AppSpacing.MD })
          .borderRadius(AppRadius.SURFACE).backgroundColor(AppSurface.color(AppSurface.SURFACE)).clip(true)
        if (this.episodeRangeStart + this.episodeItems.length < this.currentSeasonEpisodeCount) {
          Button(this.loadingMore ? '正在加载' : this.episodesError.length > 0 ? '加载失败，点击重试' : '加载更多剧集',
            { type: ButtonType.Capsule })
            .width('100%').constraintSize({ minHeight: 48 }).fontSize(AppTypography.BODY)
            .fontColor($r('app.color.accent_blue')).backgroundColor(AppSurface.color(AppSurface.SURFACE))
            .enabled(!this.loadingMore).onClick(() => { void this.loadMoreEpisodes() })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CollectionSection(): void {
    Column({ space: AppSpacing.SM }) {
      MediaSectionHeader({ title: '合集内容', actionText: String(this.collectionItems.length) + ' 项' })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
        ForEach(this.collectionItems, (entry: EmbyItem) => {
          MediaPosterCard({
            title: entry.name,
            subtitle: entry.subtitle(),
            artworkUrl: this.itemProvider() === null ? '' : this.itemProvider()!.imageUrlFor(entry, 600),
            cardWidth: this.collectionPosterWidth(),
            sharedTransitionId: this.artworkSharedTransitionId(entry),
            onCardClick: () => { void this.openCollectionItem(entry) }
          })
          .margin({ right: AppSpacing.SM, bottom: AppSpacing.MD })
        }, (entry: EmbyItem) => 'collection_item_' + entry.id)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private collectionPosterWidth(): number {
    const width = ResponsiveSizeClassResolver.posterWidth(this.screenWidthVp)
    return Math.max(112, Math.min(180, width))
  }

  private async openCollectionItem(entry: EmbyItem): Promise<void> {
    if (entry.type === 'Series' || entry.type === 'Season' || entry.type === 'Episode' ||
      entry.type === 'Movie' || entry.type === 'Video' || entry.type === 'BoxSet') {
      const params: Record<string, Object> = { 'sourceId': this.sourceId, 'itemId': entry.id }
      if (entry.type === 'Season' && entry.seriesId.length > 0) {
        params['itemId'] = entry.seriesId
        params['initialSeasonId'] = entry.id
      } else if (entry.type === 'Episode' && entry.seriesId.length > 0) {
        params['itemId'] = entry.seriesId
        params['initialSeasonId'] = entry.seasonId.length > 0 ? entry.seasonId : entry.parentId
        params['initialEpisodeId'] = entry.id
        params['initialEpisodeIndex'] = entry.indexNumber
      }
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyDetailPage', params: params })
      return
    }
    if (entry.isFolder) this.openChildren(entry)
  }

  private episodeMeta(episode: EmbyItem): string {
    const duration = episode.durationMs() > 0 ? this.formatDuration(episode.durationMs()) : ''
    const progress = this.episodeProgress(episode)
    let watchState = ''
    if (episode.userData.played || progress >= 95) {
      watchState = '已看完'
    } else if (progress > 0) {
      watchState = '已观看 ' + String(Math.round(progress)) + '%'
    }
    if (duration.length > 0 && watchState.length > 0) return duration + ' · ' + watchState
    if (duration.length > 0) return duration
    if (watchState.length > 0) return watchState
    return '点击播放'
  }

  private episodeProgress(episode: EmbyItem): number {
    return EmbyDetailPresentation.progress(episode)
  }

  private episodeArtworkUrl(episode: EmbyItem): string {
    const provider = this.itemProvider()
    return provider === null ? '' : provider.thumbnailUrlFor(episode, 320)
  }

  private async selectSeason(season: EmbyItem): Promise<void> {
    if (this.provider === null || season.id.length === 0) return
    this.userSelectedSeason = true
    this.selectedSeasonId = season.id
    this.currentSeasonEpisodeCount = this.seasonEpisodeCount(season)
    this.initialEpisodeId = ''
    await this.loadEpisodes(0)
  }

  private async playEpisode(episode: EmbyItem): Promise<void> {
    if (this.playing || this.provider === null) return
    this.playing = true
    const seasonId = episode.seasonId.length > 0 ? episode.seasonId : episode.parentId
    const generation = this.detailLoadGeneration
    const provider = this.provider
    try {
      let queue: EmbyItem[] = [episode]
      if (seasonId.length > 0) {
        try {
          const allEpisodes = await provider.getSeasonEpisodesRaw(episode.seriesId, seasonId)
          if (allEpisodes.length > 0) {
            queue = allEpisodes.map((entry: EmbyItem) => entry.id === episode.id ? episode : entry)
          }
        } catch (_) {
          // Expanding a queue must not prevent playing the explicitly selected episode.
        }
      }
      if (generation !== this.detailLoadGeneration) return
      this.initialEpisodeId = ''
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, episode, queue,
        EmbyDetailPresentation.watched(episode))
    } catch (_) {
      promptAction.showToast({ message: '无法播放该媒体' })
    } finally {
      this.playing = false
    }
  }

  private async play(item: EmbyItem): Promise<void> {
    if (this.playing) return
    this.playing = true
    try {
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, item, [item],
        EmbyDetailPresentation.watched(item))
    } catch (_) {
      promptAction.showToast({ message: '无法播放该媒体' })
    } finally {
      this.playing = false
    }
  }

  private selectPlaybackVariant(variant: PlaybackVariant): void {
    if (this.item === null || variant.id.length === 0) return
    const target = this.actionItem(this.item)
    if (target === null) return
    this.selectedVariantId = variant.id
    target.variantId = variant.id === 'auto' ? '' : variant.id
  }

  private selectedVariantLabel(): string {
    for (let i = 0; i < this.playbackVariants.length; i++) {
      const variant = this.playbackVariants[i]
      if (variant.id === this.selectedVariantId) {
        const name = variant.name.length > 0 ? variant.name : variant.id
        return variant.quality.length > 0 ? name + ' · ' + variant.quality : name
      }
    }
    return '自动'
  }

  private openVariantMenu(): void {
    if (this.playbackVariants.length < 2) return
    this.sheetKind = 'variant'
    this.showDetailSheet = true
  }

  private selectedSeasonLabel(): string {
    for (let i = 0; i < this.seasonItems.length; i++) {
      const season = this.seasonItems[i]
      if (season.id === this.selectedSeasonId) return season.subtitle().length > 0 ? season.subtitle() : season.name
    }
    return this.seasonItems.length > 0 ? this.seasonItems[0].name : '选择季'
  }

  private openSeasonSheet(): void {
    if (this.seasonItems.length === 0) return
    this.sheetKind = 'season'
    this.showDetailSheet = true
  }

  private openEpisodeRangeSheet(): void {
    if (this.currentSeasonEpisodeCount <= this.EPISODE_PAGE_SIZE) return
    this.sheetKind = 'range'
    this.showDetailSheet = true
  }

  private visibleEpisodeItems(): EmbyItem[] {
    return this.episodeItems
  }

  private episodeRangeStarts(): number[] {
    const starts: number[] = []
    for (let start = 0; start < this.currentSeasonEpisodeCount; start += this.EPISODE_PAGE_SIZE) starts.push(start)
    return starts
  }

  private rangeText(start: number): string {
    const end = Math.min(this.currentSeasonEpisodeCount, start + this.EPISODE_PAGE_SIZE)
    return String(start + 1) + '–' + String(end)
  }

  private episodeRangeLabel(): string {
    return String(this.episodeRangeStart + 1) + '–' +
      String(Math.min(this.currentSeasonEpisodeCount, this.episodeRangeStart + Math.max(1, this.episodeItems.length)))
  }

  private isResumeTarget(episode: EmbyItem): boolean {
    return this.playbackTarget !== null && this.playbackTarget.id === episode.id &&
      EmbyDetailPresentation.canResume(episode)
  }

  private initialSeason(seasons: EmbyItem[]): EmbyItem {
    if (this.initialSeasonId.length > 0) {
      for (let i = 0; i < seasons.length; i++) {
        if (seasons[i].id === this.initialSeasonId) return seasons[i]
      }
    }
    if (this.playbackTarget !== null && !this.userSelectedSeason) {
      const targetSeasonId = this.playbackTarget.seasonId.length > 0 ?
        this.playbackTarget.seasonId : this.playbackTarget.parentId
      for (const season of seasons) { if (season.id === targetSeasonId) return season }
    }
    return seasons[0]
  }

  private initialEpisodePageStart(): number {
    if (this.initialEpisodeIndex <= 0) return 0
    return Math.floor((this.initialEpisodeIndex - 1) / this.EPISODE_PAGE_SIZE) * this.EPISODE_PAGE_SIZE
  }

  @Builder
  private SelectionSheet(): void {
    HdsNavigation() {
      Scroll(this.sheetScroller) {
        Column({ space: AppSpacing.SM }) {
          if (this.sheetKind === 'season') {
            ForEach(this.seasonItems, (season: EmbyItem) => {
              this.SelectionRow(season.subtitle().length > 0 ? season.subtitle() : season.name,
                this.seasonEpisodeCount(season) > 0 ? this.seasonEpisodeCount(season) + ' 集' : '',
                season.id === this.selectedSeasonId, () => {
                  this.showDetailSheet = false
                  if (season.id !== this.selectedSeasonId || this.episodesError.length > 0) void this.selectSeason(season)
                })
            }, (season: EmbyItem) => 'season_' + season.id)
          } else if (this.sheetKind === 'range') {
            ForEach(this.episodeRangeStarts(), (start: number) => {
              this.SelectionRow('第 ' + this.rangeText(start) + ' 集', '', start === this.episodeRangeStart, () => {
                this.showDetailSheet = false
                void this.loadEpisodes(start)
              })
            }, (start: number) => 'range_' + start)
          } else {
            ForEach(this.playbackVariants, (variant: PlaybackVariant) => {
              this.SelectionRow(variant.name.length > 0 ? variant.name : variant.id, variant.quality,
                variant.id === this.selectedVariantId, () => {
                  this.selectPlaybackVariant(variant)
                  this.showDetailSheet = false
                })
            }, (variant: PlaybackVariant) => 'variant_' + variant.id)
          }
        }.width('100%').padding(AppSpacing.MD)
      }.width('100%').height('100%').scrollBar(BarState.Auto)
    }.width('100%').height('100%').mode(NavigationMode.Stack).hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MODAL)
      .titleBar({ style: buildImmersiveTitleBarStyle(this.hdsMaterialLevel), content: {
        title: { mainTitle: this.sheetKind === 'season' ? '选择季' : this.sheetKind === 'range' ? '快速选集' : '播放版本' },
        menu: { value: [{ content: { icon: $r('sys.symbol.xmark'), type: IconStyleMode.SMALL,
          action: () => { this.showDetailSheet = false } } }] }
      } })
      .backgroundColor(AppSurface.color(AppSurface.SURFACE))
      .bindToScrollable([this.sheetScroller])
  }

  @Builder
  private SelectionRow(title: string, subtitle: string, selected: boolean, onSelect: () => void): void {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpacing.MD }) {
        Column({ space: 4 }) {
          Text(title).fontSize(AppTypography.BODY_LARGE).fontColor($r('app.color.text_primary')).width('100%')
          if (subtitle.length > 0) {
            Text(subtitle).fontSize(AppTypography.META).fontColor($r('app.color.text_secondary')).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (selected) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20)
            .fontColor([$r('app.color.accent_blue')]).accessibilityLevel('no')
        }
      }.width('100%').padding(AppSpacing.MD)
    }.width('100%').constraintSize({ minHeight: 56 }).borderRadius(AppRadius.SMALL_BUTTON)
      .backgroundColor(selected ? AppSurface.color(AppSurface.SURFACE_SELECTED) : Color.Transparent)
      .accessibilityText(title + '，' + subtitle + (selected ? '，已选中' : ''))
      .onClick(onSelect)
  }

  private seasonEpisodeCount(season: EmbyItem): number {
    return season.childCount > 0 ? season.childCount : season.recursiveItemCount
  }




  private openChildren(item: EmbyItem): void {
    void this.getUIContext().getRouter().pushUrl({
      url: 'pages/emby/EmbyLibraryPage',
      params: { sourceId: this.sourceId, parentId: item.id, title: item.name }
    })
  }

  private formatDuration(durationMs: number): string {
    const totalMinutes = Math.floor(durationMs / 60000)
    const hours = Math.floor(totalMinutes / 60)
    const minutes = totalMinutes % 60
    return hours > 0 ? hours + ' 小时 ' + minutes + ' 分钟' : minutes + ' 分钟'
  }

  private sortByIndex(items: EmbyItem[]): void {
    items.sort((left: EmbyItem, right: EmbyItem) => {
      const leftIndex = left.indexNumber > 0 ? left.indexNumber : 999999999
      const rightIndex = right.indexNumber > 0 ? right.indexNumber : 999999999
      if (leftIndex !== rightIndex) return leftIndex - rightIndex
      return left.name.localeCompare(right.name)
    })
  }
}
