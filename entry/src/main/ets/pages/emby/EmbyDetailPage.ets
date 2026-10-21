import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { Logger } from '../../utils/Logger'
import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyItem, EmbyPerson } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { buildMediaDetailTitleBarOptions, getDetailContentMaxWidth, getTopSpacerHeight, isWideDetailLayout,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL, IMMERSIVE_STYLE_DEFAULT,
  PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'
import { buildDetailToastOptions,
  DetailSelectMaterialModifier, DetailToggleButtonMaterialModifier } from '../../utils/DetailMaterial'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { MediaPosterCard } from '../../components/media/MediaPosterCard'
import { EmbyDetailPresentation } from '../../providers/emby/EmbyDetailPresentation'
import { buildEmbyDetailRouteParams } from '../../providers/emby/EmbyDetailRoute'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSurface } from '../../ui/theme/AppSurface'
import { ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { ImmersiveDetailStage } from '../../components/media/ImmersiveDetailStage'
import { DetailTrackOption } from '../../components/media/DetailTrackSelect'
import { EmbyMediaSource, EmbyMediaTrack } from '../../providers/emby/EmbyPlaybackInfo'
import { EmbyPlaybackPolicy } from '../../providers/emby/EmbyPlaybackPolicy'
import { PlaybackTrackSelection } from '../../core/playback/PlaybackTrackSelection'

const playbackInfoLogger: Logger = new Logger('EmbyDetailTracks')

enum EmbyDetailSheetType {
  PLAYBACK_VARIANTS,
  OVERVIEW,
  INFORMATION
}

@Entry
@Component
struct EmbyDetailPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private sourceId: string = ''
  @State private itemId: string = ''
  @State private artworkTransitionId: string = ''
  @State private transitionArtworkUrl: string = ''
  @State private transitionArtworkFailed: boolean = false
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
  @State private similarItems: EmbyItem[] = []
  @State private selectedSeasonId: string = ''
  @State private playbackVariants: PlaybackVariant[] = []
  @State private selectedVariantId: string = 'auto'
  @State private playbackSources: EmbyMediaSource[] = []
  @State private audioOptions: DetailTrackOption[] = []
  @State private subtitleOptions: DetailTrackOption[] = []
  @State private selectedAudioId: number = -1
  @State private selectedSubtitleId: number = -1
  @State private tracksLoading: boolean = false
  private trackItemId: string = ''
  private trackSourceId: string = ''
  private autoSourceIndex: number = 0
  @State private ambientArtworkUrl: string = ''
  @State private totalEpisodeCount: number = 0
  @State private currentSeasonEpisodeCount: number = 0
  @State private episodeRangeStart: number = 0
  @State private showDetailSheet: boolean = false
  @State private overviewExpanded: boolean = false
  @State private detailSheetType: EmbyDetailSheetType = EmbyDetailSheetType.PLAYBACK_VARIANTS
  @State private episodesLoading: boolean = false
  @State private episodesError: string = ''
  @State private loadingMore: boolean = false
  @State private playbackTarget: EmbyItem | null = null
  @State private targetLoading: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  private provider: EmbyProvider | null = null
  private seasonLoadGeneration: number = 0
  private episodeNextStart: number = 0
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
      if (typeof params['artworkTransitionId'] === 'string') {
        this.artworkTransitionId = params['artworkTransitionId'] as string
      }
      if (typeof params['transitionArtworkUrl'] === 'string') {
        this.transitionArtworkUrl = params['transitionArtworkUrl'] as string
      }
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
    Stack() {
    HdsNavigation() {
      if (this.loading) {
        this.LoadingContent()
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
      .titleBar(buildMediaDetailTitleBarOptions(this.item === null ? '媒体详情' : this.item!.name,
        this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .bindToScrollable([this.scroller, this.heroScroller])
    }.width('100%').height('100%')
      .bindSheet($$this.showDetailSheet, this.DetailSheet(), this.buildReferenceSheetOptions())
  }

  private buildReferenceSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      height: 410,
      maskColor: '#66000000',
      showClose: false,
      dragBar: false,
      onDisappear: () => { this.showDetailSheet = false }
    }
    if (deviceInfo.sdkApiVersion >= 26) {
      options.backgroundColor = Color.Transparent
      options.systemMaterial = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK })
    } else {
      options.backgroundColor = $r('app.color.card_background')
    }
    return options
  }

  @Builder
  private DetailContent(item: EmbyItem): void {
    Stack({ alignContent: Alignment.Bottom }) {
      this.DetailAtmosphere()
      if (isWideDetailLayout(this.screenWidthVp)) {
        Row({ space: AppSpacing.XL }) {
          Scroll(this.heroScroller) {
            Column({ space: AppSpacing.MD }) {
              Blank().width('100%').height(getTopSpacerHeight(this.topSafeHeight))
              this.Hero(item, true)
            }.width('100%').alignItems(HorizontalAlign.Start)
              .padding({ bottom: 24 + this.bottomSafeHeight })
          }.width('40%').height('100%').scrollBar(BarState.Off)
          Scroll(this.scroller) {
            Column() {
              Blank().width('100%').height(getTopSpacerHeight(this.topSafeHeight))
              this.DetailSections(item)
            }.width('100%')
              .padding({ bottom: 24 + this.bottomSafeHeight })
          }.layoutWeight(1).height('100%').scrollBar(BarState.Off)
        }.width('100%').height('100%').alignItems(VerticalAlign.Top)
          .constraintSize({ maxWidth: getDetailContentMaxWidth(this.screenWidthVp) })
          .padding(ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp))
      } else {
        Scroll(this.scroller) {
          Column({ space: AppSpacing.LG }) {
            Blank().width('100%').height(getTopSpacerHeight(this.topSafeHeight))
            this.Hero(item, false)
            Column({ space: AppSpacing.LG }) {
              this.DetailSections(item)
            }.width('100%').padding({ left: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
              right: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp) })
          }.width('100%').padding({ bottom: 24 + this.bottomSafeHeight })
        }.width('100%').height('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  /** Keeps a destination poster in the tree from the first frame of a shared transition. */
  @Builder
  private LoadingContent(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      this.DetailAtmosphere()
      if (isWideDetailLayout(this.screenWidthVp)) {
        Row({ space: AppSpacing.XL }) {
          Scroll(this.heroScroller) {
            Column({ space: AppSpacing.MD }) {
              Blank().width('100%').height(getTopSpacerHeight(this.topSafeHeight))
              this.LoadingHero(true)
            }.width('100%').alignItems(HorizontalAlign.Start)
              .padding({ bottom: 24 + this.bottomSafeHeight })
          }.width('40%').height('100%').scrollBar(BarState.Off)
          Scroll(this.scroller) {
            Column() {
              Blank().width('100%').height(getTopSpacerHeight(this.topSafeHeight))
              this.LoadingSections()
            }.width('100%').padding({ bottom: 24 + this.bottomSafeHeight })
          }.layoutWeight(1).height('100%').scrollBar(BarState.Off)
        }.width('100%').height('100%').alignItems(VerticalAlign.Top)
          .constraintSize({ maxWidth: getDetailContentMaxWidth(this.screenWidthVp) })
          .padding(ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp))
      } else {
        Scroll(this.scroller) {
          Column({ space: AppSpacing.LG }) {
            Blank().width('100%').height(getTopSpacerHeight(this.topSafeHeight))
            this.LoadingHero(false)
            Column({ space: AppSpacing.LG }) {
              this.LoadingSections()
            }.width('100%').padding({ left: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
              right: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp) })
          }.width('100%').padding({ bottom: 24 + this.bottomSafeHeight })
        }.width('100%').height('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private LoadingHero(wide: boolean): void {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        this.LoadingPoster(wide)
        Column({ space: AppSpacing.SM }) {
          Column().width('82%').height(30).borderRadius(AppRadius.SMALL_BUTTON)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
          Column().width('54%').height(14).borderRadius(AppRadius.SMALL_BUTTON)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
          Column().width('100%').height(40).borderRadius(20)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
          Column().width('80%').height(40).borderRadius(20)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Top)
      Column({ space: AppSpacing.SM }) {
        Column().width('100%').height(48).borderRadius(AppRadius.BUTTON)
          .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
        Column().width('58%').height(13).borderRadius(AppRadius.SMALL_BUTTON)
          .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
      }.width('100%').alignItems(HorizontalAlign.Center)
    }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: wide ? 0 : ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
        right: wide ? 0 : ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
        top: AppSpacing.LG, bottom: AppSpacing.SM })
  }

  @Builder
  private LoadingPoster(wide: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      if (this.transitionArtworkUrl.length > 0 && !this.transitionArtworkFailed) {
        Image(this.transitionArtworkUrl).width(this.loadingPosterWidth(wide)).height(this.loadingPosterHeight(wide))
          .objectFit(ImageFit.Cover).accessibilityLevel('no')
          .borderRadius(AppRadius.MEDIA_POSTER).clip(true)
          .sharedTransition(this.artworkTransitionId, { duration: 360, curve: Curve.FastOutSlowIn })
          .onError(() => { this.transitionArtworkFailed = true })
      } else {
        Column().width(this.loadingPosterWidth(wide)).height(this.loadingPosterHeight(wide))
          .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
      }
    }.width(this.loadingPosterWidth(wide)).height(this.loadingPosterHeight(wide))
      .borderRadius(AppRadius.MEDIA_POSTER).clip(true)
      .border({ width: 0.5, color: AppSurface.borderColor() })
      .shadow({ radius: 24, color: $r('app.color.shadow_surface'), offsetY: 9 })
  }

  @Builder
  private LoadingSections(): void {
    Column({ space: AppSpacing.SECTION_COMPACT }) {
      this.LoadingTextSection(3, '100%')
      this.LoadingTextSection(4, '88%')
      this.LoadingTextSection(2, '68%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LoadingTextSection(lineCount: number, lastLineWidth: string): void {
    Column({ space: AppSpacing.SM }) {
      Column().width('36%').height(20).borderRadius(AppRadius.SMALL_BUTTON)
        .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
      Column({ space: AppSpacing.XS }) {
        ForEach(Array.from({ length: lineCount }), (_value: number, index: number) => {
          Column().width(index === lineCount - 1 ? lastLineWidth : '100%').height(14)
            .borderRadius(AppRadius.SMALL_BUTTON)
            .backgroundColor(AppSurface.color(AppSurface.SURFACE_SECONDARY))
        }, (_value: number, index: number) => 'detail_skeleton_' + lineCount + '_' + index)
      }.width('100%').padding(AppSpacing.MD).alignItems(HorizontalAlign.Start)
        .borderRadius(AppRadius.SURFACE).backgroundColor(AppSurface.color(AppSurface.SURFACE))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private loadingPosterWidth(wide: boolean): number {
    return wide ? 144 : 112
  }

  private loadingPosterHeight(wide: boolean): number {
    return wide ? 216 : 168
  }

  @Builder
  private DetailAtmosphere(): void {
    Stack() {
      if (this.ambientArtworkUrl.length > 0) {
        Image(this.ambientArtworkUrl)
          .width('100%').height('100%').objectFit(ImageFit.Cover)
           .blur(92).opacity(0.76).scale({ x: 1.24, y: 1.24 })
          .accessibilityLevel('no')
      }
      // 约束海报背景的明暗范围，让深浅主题的正文和次要文字都保持可读。
      Column().width('100%').height('100%')
        .backgroundColor($r('app.color.detail_atmosphere_wash'))
        .accessibilityLevel('no')
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private Hero(item: EmbyItem, wide: boolean): void {
    Column() {
      ImmersiveDetailStage({
        posterUrl: this.imageUrl(item), title: item.name, meta: this.metaText(item),
        actionText: this.primaryActionText(item), actionDescription: this.actionDescription(item),
        actionEnabled: this.canPlay(item), busy: this.playing,
        variantLabel: this.playbackVariants.length > 1 ? this.selectedVariantLabel() : '',
        wide: wide, contentPadding: wide ? 0 : ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
        sharedTransitionId: this.artworkTransitionId,
        audioOptions: this.audioOptions, subtitleOptions: this.subtitleOptions,
        selectedAudioId: this.selectedAudioId, selectedSubtitleId: this.selectedSubtitleId,
        tracksLoading: this.tracksLoading || this.targetLoading,
        onAudioSelect: (id: number) => { this.selectedAudioId = id },
        onSubtitleSelect: (id: number) => { this.selectedSubtitleId = id },
        onPrimaryAction: () => this.handlePrimaryAction(item),
        onVariantAction: () => this.openVariantMenu()
      })
    }.width('100%')
  }

  @Builder
  private OverviewSection(item: EmbyItem): void {
    Column({ space: AppSpacing.SM }) {
      Text('关于作品').fontSize(AppTypography.SECTION_TITLE).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      if (item.overview.length > 0) {
        Toggle({ type: ToggleType.Button, isOn: this.overviewExpanded }) {
          Text(item.overview).fontSize(AppTypography.BODY_LARGE)
            .fontColor($r('app.color.text_primary')).lineHeight(26)
            .maxLines(this.overviewExpanded ? Infinity : 3)
            .textOverflow({ overflow: this.overviewExpanded ? TextOverflow.None : TextOverflow.Ellipsis })
            .width('100%')
        }.width('100%').constraintSize({ minHeight: 44 }).padding(18).borderRadius(22)
          .attributeModifier(new DetailToggleButtonMaterialModifier(this.materialThickness,
            this.overviewExpanded, 'overview', AppSurface.color(AppSurface.SURFACE_INTERACTIVE),
            AppSurface.color(AppSurface.SURFACE_SELECTED)))
          .accessibilityText(this.overviewExpanded ? '作品简介，已展开，点击收起' : '作品简介，已收起，点击展开')
          .onChange((isOn: boolean) => { this.overviewExpanded = isOn })
      } else {
        Text('暂无作品简介').fontSize(AppTypography.BODY)
          .fontColor($r('app.color.detail_text_secondary')).padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailSections(item: EmbyItem): void {
    Column({ space: AppSpacing.SECTION_COMPACT }) {
      this.OverviewSection(item)
      if (this.isEpisodeContainer(item)) {
        this.EpisodeSection()
        if (this.seasonItems.length > 0) this.SeasonSection()
        if (item.people.length > 0) this.PeopleSection(item)
        if (this.similarItems.length > 0) this.SimilarSection()
        this.DetailInfoSection(item)
      } else {
        if (this.collectionItems.length > 0) this.CollectionSection()
        if (item.people.length > 0) this.PeopleSection(item)
        if (this.similarItems.length > 0) this.SimilarSection()
        this.DetailInfoSection(item)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailInfoSection(item: EmbyItem): void {
    Column({ space: AppSpacing.MD }) {
      Toggle({ type: ToggleType.Button, isOn: true }) {
        Column({ space: AppSpacing.MD }) {
          Text('作品信息').fontSize(AppTypography.SECTION_TITLE).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          this.DetailInformationContent(item)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ minHeight: 44 }).padding(18).borderRadius(22)
        .attributeModifier(new DetailToggleButtonMaterialModifier(this.materialThickness,
          true, 'information', AppSurface.color(AppSurface.SURFACE_INTERACTIVE),
          AppSurface.color(AppSurface.SURFACE_SELECTED)))
        .accessibilityText('作品信息')
        .hitTestBehavior(HitTestMode.None)
        .focusable(false)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private detailInfoSummary(item: EmbyItem): string {
    const parts: string[] = [EmbyItem.typeLabel(item.type)]
    if (item.productionYear > 0) parts.push(String(item.productionYear))
    if (item.container.length > 0) parts.push(item.container.toUpperCase())
    return parts.join(' · ')
  }

  @Builder
  private DetailInformationContent(item: EmbyItem): void {
    Column({ space: AppSpacing.LG }) {
      Column() {
        this.DetailInfoGroupHeading('基本信息')
        this.DetailInfoRow('媒体类型', EmbyItem.typeLabel(item.type))
        if (item.productionYear > 0) {
          this.DetailInfoRow('年份', String(item.productionYear))
        }
        if (item.type === 'Series') {
          if (this.seriesSeasonCount(item) > 0) this.DetailInfoRow('季数', String(this.seriesSeasonCount(item)) + ' 季')
          if (this.seriesEpisodeCount(item) > 0) this.DetailInfoRow('总集数', String(this.seriesEpisodeCount(item)) + ' 集')
        } else if (item.type === 'Season' && this.currentSeasonEpisodeCount > 0) {
          this.DetailInfoRow('集数', String(this.currentSeasonEpisodeCount) + ' 集')
        }
        if (item.durationMs() > 0) {
          this.DetailInfoRow('时长', this.formatDuration(item.durationMs()))
        }
        if (item.container.length > 0) this.DetailInfoRow('格式', item.container.toUpperCase())
      }.width('100%').alignItems(HorizontalAlign.Start)
      if (item.communityRating > 0 || item.genres.length > 0 || item.officialRating.length > 0) {
        Column() {
          this.DetailInfoGroupHeading('评分与分类')
          if (item.communityRating > 0) this.DetailInfoRow('评分', item.communityRating.toFixed(1))
          if (item.genres.length > 0) this.DetailInfoRow('题材', item.genres.join(' · '))
          if (item.officialRating.length > 0) this.DetailInfoRow('分级', item.officialRating)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (item.studios.length > 0 || item.premiereDate.length > 0) {
        Column() {
          this.DetailInfoGroupHeading('制作与发行')
          if (item.studios.length > 0) this.DetailInfoRow('制作', item.studios.join(' · '))
          if (item.premiereDate.length > 0) this.DetailInfoRow('首播', this.displayDate(item.premiereDate))
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailInfoGroupHeading(title: string): void {
    Text(title).fontSize(AppTypography.BODY_LARGE).fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary')).padding({ bottom: AppSpacing.SM })
  }

  @Builder
  private DetailInfoRow(label: string, value: string): void {
    Row({ space: AppSpacing.SM }) {
      Text(label).fontSize(AppTypography.BODY).fontColor($r('sys.color.font_secondary')).width(76)
      Text(value).fontSize(AppTypography.BODY).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        .lineHeight(24)
    }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 7, bottom: 7 })
  }



  private async loadItem(): Promise<void> {
    this.seasonLoadGeneration++
    const generation = ++this.detailLoadGeneration
    this.targetGeneration++
    this.loading = true
    this.transitionArtworkFailed = false
    this.errorText = ''
    this.item = null
    this.ambientArtworkUrl = ''
    this.playbackVariants = []
    this.selectedVariantId = 'auto'
    this.seasonItems = []
    this.episodeItems = []
    this.collectionItems = []
    this.similarItems = []
    this.selectedSeasonId = ''
    this.totalEpisodeCount = 0
    this.currentSeasonEpisodeCount = 0
    this.episodeRangeStart = 0
    this.episodesError = ''
    this.episodesLoading = false
    this.loadingMore = false
    this.playbackTarget = null
    this.targetLoading = false
    this.detailSheetType = EmbyDetailSheetType.PLAYBACK_VARIANTS
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
      void this.loadSimilarItems(provider, loadedItem, generation)
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
          if (generation === this.detailLoadGeneration) this.showDetailToast('合集内容读取失败')
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

  private async loadSimilarItems(provider: EmbyProvider, loadedItem: EmbyItem,
    generation: number): Promise<void> {
    try {
      const items = await provider.getSimilarItemsRaw(loadedItem.id, 12)
      if (generation !== this.detailLoadGeneration || this.item === null || this.item.id !== loadedItem.id) return
      this.similarItems = items.filter((entry: EmbyItem) => entry.id !== loadedItem.id &&
        entry.type !== 'Folder' && entry.type !== 'CollectionFolder')
    } catch (_) {
      if (generation === this.detailLoadGeneration) this.similarItems = []
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
      this.episodeNextStart = start
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
      // 按服务器返回的条目推进分页，避免去重后重复请求同一页。
      this.episodeNextStart = (append ? start : this.episodeRangeStart) + page.items.length
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
    if (this.episodesLoading || this.loadingMore || this.episodeItems.length === 0 ||
      this.episodeNextStart >= this.currentSeasonEpisodeCount) return
    await this.loadEpisodes(this.episodeNextStart, true)
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
    let stage: string = 'variants'
    playbackInfoLogger.info('load start generation=%{public}d type=%{public}s', generation, loadedItem.type)
    this.tracksLoading = true
    this.audioOptions = []
    this.subtitleOptions = []
    this.playbackSources = []
    this.playbackVariants = []
    this.selectedVariantId = loadedItem.variantId.length > 0 ? loadedItem.variantId : 'auto'
    try {
      const variants = await provider.getPlaybackVariants(loadedItem)
      stage = 'sources'
      const sources = await provider.getPlaybackSources(loadedItem)
      playbackInfoLogger.info('load response generation=%{public}d variants=%{public}d sources=%{public}d',
        generation, variants.length, sources.length)
      sources.forEach((source: EmbyMediaSource, index: number) => {
        playbackInfoLogger.info('source generation=%{public}d index=%{public}d tracks=%{public}d audio=%{public}d externalAudio=%{public}d subtitles=%{public}d',
          generation, index, source.tracks.length,
          source.tracks.filter((track: EmbyMediaTrack) => track.type === 'Audio' && !track.isExternal).length,
          source.tracks.filter((track: EmbyMediaTrack) => track.type === 'Audio' && track.isExternal).length,
          source.tracks.filter((track: EmbyMediaTrack) => track.type === 'Subtitle').length)
      })
      stage = 'policy'
      const mode = await EmbyPlaybackPolicy.loadMode()
      if (!this.isCurrentPlaybackRequest(loadedItem.id, generation, loadGeneration)) {
        playbackInfoLogger.info('load discarded generation=%{public}d reason=stale_target', generation)
        return
      }
      loadedItem.variants = variants
      this.playbackSources = sources
      if (sources.length > 0) {
        this.autoSourceIndex = sources.indexOf(EmbyPlaybackPolicy.selectSource(sources, mode))
        const preserve = this.trackItemId === loadedItem.id
        this.trackItemId = loadedItem.id
        this.updateTrackOptions(preserve)
      } else {
        playbackInfoLogger.warn('load empty generation=%{public}d reason=no_media_sources', generation)
      }
      if (variants.length > 1) {
        const auto = new PlaybackVariant()
        auto.id = 'auto'
        auto.name = '自动'
        this.playbackVariants = [auto].concat(variants)
      }
    } catch (err) {
      // Never log raw error messages: network errors can include credential-bearing URLs.
      const code = (err as BusinessError).code
      playbackInfoLogger.warn('load failed generation=%{public}d stage=%{public}s code=%{public}d',
        generation, stage, typeof code === 'number' ? code : -1)
      // Automatic playback stays available while version metadata is unavailable.
    } finally {
      if (generation === this.playbackGeneration && loadGeneration === this.detailLoadGeneration) {
        this.tracksLoading = false
      }
    }
  }

  private isCurrentPlaybackRequest(itemId: string, generation: number, loadGeneration: number): boolean {
    if (generation !== this.playbackGeneration || loadGeneration !== this.detailLoadGeneration ||
      this.item === null) return false
    // @State may wrap model objects; compare stable media identity rather than references.
    const target = this.actionItem(this.item)
    return target !== null && target.id === itemId
  }

  private updateTrackOptions(preserve: boolean = false): void {
    const index = this.selectedVariantId === 'auto' ? this.autoSourceIndex :
      this.playbackSources.findIndex((source: EmbyMediaSource, i: number) =>
        (source.id || 'source_' + i) === this.selectedVariantId)
    const source = this.playbackSources[index]
    if (source === undefined) {
      playbackInfoLogger.warn('selection missing sourceIndex=%{public}d sources=%{public}d',
        index, this.playbackSources.length)
      this.audioOptions = []
      this.subtitleOptions = []
      return
    }
    const sourceId = source.id || 'source_' + index
    preserve = preserve && this.trackSourceId === sourceId
    this.trackSourceId = sourceId
    const audio = source.tracks.filter((track: EmbyMediaTrack) => track.type === 'Audio' && !track.isExternal)
    const subtitles = source.tracks.filter((track: EmbyMediaTrack) => track.type === 'Subtitle')
    this.audioOptions = audio.map((track: EmbyMediaTrack) => this.trackOption(track))
    const off = new DetailTrackOption()
    off.id = -1
    off.title = '无'
    this.subtitleOptions = [off].concat(subtitles.map((track: EmbyMediaTrack) => this.trackOption(track)))
    if (!preserve || !audio.some((track: EmbyMediaTrack) => track.index === this.selectedAudioId)) {
      const defaultAudio = audio.find((track: EmbyMediaTrack) => track.index === source.defaultAudioIndex) ||
        audio.find((track: EmbyMediaTrack) => track.isDefault) || audio[0]
      this.selectedAudioId = defaultAudio === undefined ? -1 : defaultAudio.index
    }
    if (!preserve || !this.subtitleOptions.some((option: DetailTrackOption) => option.id === this.selectedSubtitleId)) {
      this.selectedSubtitleId = subtitles.some((track: EmbyMediaTrack) => track.index === source.defaultSubtitleIndex) ?
        source.defaultSubtitleIndex : -1
    }
    playbackInfoLogger.info('selection sourceIndex=%{public}d audioOptions=%{public}d subtitleTracks=%{public}d subtitleOptions=%{public}d selectedAudio=%{public}d selectedSubtitle=%{public}d',
      index, this.audioOptions.length, subtitles.length, this.subtitleOptions.length,
      this.selectedAudioId, this.selectedSubtitleId)
  }

  private trackOption(track: EmbyMediaTrack): DetailTrackOption {
    const option = new DetailTrackOption()
    option.id = track.index
    option.title = track.label()
    option.detail = track.detail()
    option.summary = track.codec.toUpperCase() + (track.channels > 0 ? ' ' + track.channels + 'ch' : '')
    return option
  }

  private selectionFor(item: EmbyItem): PlaybackTrackSelection | null {
    if (this.tracksLoading || this.targetLoading || this.trackItemId !== item.id || this.playbackSources.length === 0) return null
    const selection = new PlaybackTrackSelection()
    selection.variantId = this.trackSourceId
    selection.audioIndex = this.selectedAudioId
    selection.subtitleIndex = this.selectedSubtitleId
    return selection
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
        Text('剧集').fontSize(AppTypography.SECTION_TITLE).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.currentSeasonEpisodeCount > 0) {
          Text(String(this.currentSeasonEpisodeCount) + ' 集').fontSize(AppTypography.META)
            .fontColor($r('app.color.detail_text_secondary'))
        }
        Blank()
        if (this.seasonItems.length > 0) {
          Select(this.seasonSelectOptions())
            .selected(this.selectedSeasonIndex())
            .value(this.selectedSeasonLabel())
            .font({ size: 15, weight: FontWeight.Medium })
            .fontColor($r('sys.color.font_primary'))
            .optionFontColor($r('sys.color.font_primary'))
            .selectedOptionBgColor(Color.Transparent)
            .selectedOptionFontColor($r('sys.color.brand'))
            .attributeModifier(new DetailSelectMaterialModifier(this.materialThickness))
            .constraintSize({ minHeight: 44, maxWidth: '56%' })
            .accessibilityText('选择季，' + this.selectedSeasonLabel())
            .onSelect((index: number) => {
              if (index < 0 || index >= this.seasonItems.length) return
              const season = this.seasonItems[index]
              if (season.id !== this.selectedSeasonId || this.episodesError.length > 0) {
                void this.selectSeason(season)
              }
            })
        }
      }.width('100%').alignItems(VerticalAlign.Center)
      if (this.currentSeasonEpisodeCount > this.EPISODE_PAGE_SIZE) {
        Row({ space: AppSpacing.SM }) {
          Text('快速选集').fontSize(AppTypography.BODY)
            .fontColor($r('app.color.detail_text_secondary'))
          Blank()
          Select(this.episodeRangeSelectOptions())
            .selected(this.episodeRangeStarts().indexOf(this.episodeRangeStart))
            .value('第 ' + this.rangeText(this.episodeRangeStart) + ' 集')
            .font({ size: 15, weight: FontWeight.Medium })
            .fontColor($r('sys.color.font_primary'))
            .optionFontColor($r('sys.color.font_primary'))
            .selectedOptionBgColor(Color.Transparent)
            .selectedOptionFontColor($r('sys.color.brand'))
            .attributeModifier(new DetailSelectMaterialModifier(this.materialThickness))
            .constraintSize({ minHeight: 44, maxWidth: '56%' })
            .accessibilityText('快速选集，第 ' + this.rangeText(this.episodeRangeStart) + ' 集')
            .onSelect((index: number) => {
              const starts = this.episodeRangeStarts()
              if (index < 0 || index >= starts.length) return
              void this.loadEpisodes(starts[index])
            })
        }.width('100%').alignItems(VerticalAlign.Center)
      }
      if (this.episodesLoading) {
        PageLoadingState({ title: '正在读取剧集', minHeight: 160 })
      } else if (this.episodesError.length > 0 && this.episodeItems.length === 0) {
        PageErrorState({ title: '剧集暂不可用', message: this.episodesError,
          onRetry: () => { void this.retryEpisodes() } })
      } else if (this.episodeItems.length === 0) {
        Text(this.selectedSeasonId.length > 0 ? '这一季暂无剧集' : '暂无剧集').fontSize(AppTypography.BODY_LARGE)
          .fontColor($r('app.color.detail_text_secondary')).padding({ top: 32, bottom: 32 }).width('100%')
      } else {
        Scroll() {
          Row({ space: AppSpacing.SM }) {
            ForEach(this.visibleEpisodeItems(), (episode: EmbyItem, index: number) => {
              this.EpisodeRailCard(episode, index)
            }, (episode: EmbyItem) => 'detail_episode_' + episode.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .align(Alignment.TopStart)
          .onReachEnd(() => {
            if (this.episodesError.length === 0) void this.loadMoreEpisodes()
          })
        if (this.loadingMore) {
          Row({ space: AppSpacing.SM }) {
            LoadingProgress().width(20).height(20).color($r('app.color.accent_blue'))
            Text('正在加载剧集').fontSize(AppTypography.META)
              .fontColor($r('app.color.detail_text_secondary'))
          }.width('100%').justifyContent(FlexAlign.Center).height(44)
        } else if (this.episodesError.length > 0) {
          Button('加载失败，点击重试', { type: ButtonType.Normal })
            .fontSize(AppTypography.BODY).fontColor($r('app.color.accent_blue'))
            .backgroundColor(Color.Transparent).constraintSize({ minHeight: 44 })
            .onClick(() => { void this.loadMoreEpisodes() })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EpisodeRailCard(episode: EmbyItem, index: number): void {
    Column({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(this.episodeArtworkUrl(episode).length > 0 ? this.episodeArtworkUrl(episode) :
          $r('app.media.ic_placeholder'))
          .width('100%').height(112).objectFit(ImageFit.Cover)
          .accessibilityLevel('no')
        Column().width('100%').height(58)
          .linearGradient({ direction: GradientDirection.Top,
            colors: [['#B3000000', 0], ['#00000000', 1]] })
        Row({ space: AppSpacing.XS }) {
          if (EmbyDetailPresentation.watched(episode)) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(17)
              .fontColor([Color.White]).accessibilityLevel('no')
          } else {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(15)
              .fontColor([Color.White]).accessibilityLevel('no')
          }
          Text(this.episodeIndexLabel(episode, index)).fontSize(AppTypography.CAPTION)
            .fontWeight(FontWeight.Medium).fontColor(Color.White)
        }.padding({ left: 10, right: 10, bottom: 9 })
      }.width(this.episodeCardWidth()).height(112).borderRadius(AppRadius.MEDIA_LANDSCAPE).clip(true)
        .border({ width: this.isResumeTarget(episode) ? 2 : 0,
          color: $r('app.color.accent_blue') })
        .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
      Text(episode.name)
        .width(this.episodeCardWidth()).fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.episodeMeta(episode)).width(this.episodeCardWidth()).fontSize(AppTypography.CAPTION)
        .fontColor($r('app.color.detail_text_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width(this.episodeCardWidth()).alignItems(HorizontalAlign.Start)
      .enabled(!this.playing).accessibilityGroup(true)
      .accessibilityText('第 ' + this.episodeIndexLabel(episode, index) + ' 集，' + episode.name)
      .onClick(() => { void this.playEpisode(episode) })
  }

  @Builder
  private SeasonSection(): void {
    Column({ space: AppSpacing.MD }) {
      MediaSectionHeader({ title: '季', actionText: String(this.seasonItems.length) + ' 季' })
      Scroll() {
        Row({ space: AppSpacing.SM }) {
          ForEach(this.seasonItems, (season: EmbyItem) => {
            this.SeasonRailCard(season)
          }, (season: EmbyItem) => 'detail_season_' + season.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .align(Alignment.TopStart)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SeasonRailCard(season: EmbyItem): void {
    Column({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(this.seasonArtworkUrl(season).length > 0 ? this.seasonArtworkUrl(season) :
          $r('app.media.ic_placeholder'))
          .width(112).height(168).objectFit(ImageFit.Cover).accessibilityLevel('no')
      }.width(112).height(168).borderRadius(AppRadius.MEDIA_POSTER).clip(true)
        .border({ width: season.id === this.selectedSeasonId ? 2 : 0,
          color: $r('app.color.accent_blue') })
        .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
      Text(season.subtitle().length > 0 ? season.subtitle() : season.name)
        .width(112).fontSize(AppTypography.BODY).fontWeight(FontWeight.Medium)
        .fontColor(season.id === this.selectedSeasonId ? $r('app.color.accent_blue') :
          $r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width(112).alignItems(HorizontalAlign.Start)
      .accessibilityText((season.subtitle().length > 0 ? season.subtitle() : season.name) +
        (season.id === this.selectedSeasonId ? '，当前季' : ''))
      .onClick(() => {
        if (season.id !== this.selectedSeasonId || this.episodesError.length > 0) void this.selectSeason(season)
      })
  }

  private episodeCardWidth(): number {
    return Math.max(176, Math.min(236, this.screenWidthVp * 0.58))
  }

  private episodeIndexLabel(episode: EmbyItem, index: number): string {
    return episode.indexNumber > 0 ? String(episode.indexNumber).padStart(2, '0') :
      String(this.episodeRangeStart + index + 1)
  }

  @Builder
  private PeopleSection(item: EmbyItem): void {
    Column({ space: AppSpacing.MD }) {
      MediaSectionHeader({ title: '演职人员', actionText: String(item.people.length) + ' 人' })
      Scroll() {
        Row({ space: AppSpacing.MD }) {
          ForEach(this.visiblePeople(item), (person: EmbyPerson) => {
            this.PersonCard(person)
          }, (person: EmbyPerson) => 'detail_person_' + person.id + '_' + person.name)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PersonCard(person: EmbyPerson): void {
    Column({ space: AppSpacing.SM }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.personArtworkUrl(person).length > 0) {
          Image(this.personArtworkUrl(person)).width(76).height(76).objectFit(ImageFit.Cover)
            .accessibilityLevel('no')
        } else {
          Circle().width(76).height(76).fill($r('app.color.detail_surface'))
          Text(this.personInitial(person)).fontSize(AppTypography.PAGE_TITLE).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent_blue'))
        }
      }.width(76).height(76).borderRadius(38).clip(true)
        .border({ width: 1, color: AppSurface.borderColor() })
        .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
      Text(person.name).width(92).fontSize(AppTypography.BODY).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).maxLines(1).textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.personRole(person)).width(92).fontSize(AppTypography.CAPTION)
        .fontColor($r('app.color.detail_text_secondary')).maxLines(1).textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width(92).alignItems(HorizontalAlign.Center).accessibilityGroup(true)
      .accessibilityText(person.name + '，' + this.personRole(person))
  }

  @Builder
  private SimilarSection(): void {
    Column({ space: AppSpacing.MD }) {
      MediaSectionHeader({ title: '相似作品' })
      Scroll() {
        Row({ space: AppSpacing.SM }) {
          ForEach(this.similarItems, (entry: EmbyItem) => {
            MediaPosterCard({
              title: entry.name,
              subtitle: entry.subtitle(),
              subtitleColor: $r('app.color.detail_text_secondary'),
              artworkUrl: this.imageUrl(entry),
              cardWidth: this.collectionPosterWidth(),
              enableSharedTransition: true,
              onCardClick: (transitionId: string) => { void this.openCollectionItem(entry, transitionId,
                this.imageUrl(entry)) }
            })
          }, (entry: EmbyItem) => 'detail_similar_' + entry.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private visiblePeople(item: EmbyItem): EmbyPerson[] {
    return item.people.slice(0, 16)
  }

  private personArtworkUrl(person: EmbyPerson): string {
    return this.provider === null ? '' : this.provider.personImageUrlFor(person, 320)
  }

  private personInitial(person: EmbyPerson): string {
    return person.name.length > 0 ? person.name.substring(0, 1) : '人'
  }

  private personRole(person: EmbyPerson): string {
    if (person.role.length > 0) return person.role
    if (person.type === 'Director') return '导演'
    if (person.type === 'Writer') return '编剧'
    if (person.type === 'Producer') return '制片'
    if (person.type === 'Actor') return '演员'
    return person.type.length > 0 ? person.type : '演职人员'
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
            subtitleColor: $r('app.color.detail_text_secondary'),
            artworkUrl: this.itemProvider() === null ? '' : this.itemProvider()!.imageUrlFor(entry, 600),
            cardWidth: this.collectionPosterWidth(),
            enableSharedTransition: true,
            onCardClick: (transitionId: string) => { void this.openCollectionItem(entry, transitionId,
              this.itemProvider() === null ? '' : this.itemProvider()!.imageUrlFor(entry, 600)) }
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

  private async openCollectionItem(entry: EmbyItem, artworkTransitionId: string = '',
    transitionArtworkUrl: string = ''): Promise<void> {
    if (entry.type === 'Series' || entry.type === 'Season' || entry.type === 'Episode' ||
      entry.type === 'Movie' || entry.type === 'Video' || entry.type === 'BoxSet') {
      const params = buildEmbyDetailRouteParams(this.sourceId, entry, artworkTransitionId, transitionArtworkUrl)
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
    if (provider === null) return this.ambientArtworkUrl
    const thumbnail = provider.thumbnailUrlFor(episode, 640)
    if (thumbnail.length > 0) return thumbnail
    const backdrop = provider.backdropUrlFor(episode, 640)
    if (backdrop.length > 0) return backdrop
    const primary = provider.imageUrlFor(episode, 640)
    return primary.length > 0 ? primary : this.ambientArtworkUrl
  }

  private seasonArtworkUrl(season: EmbyItem): string {
    const provider = this.itemProvider()
    if (provider === null) return ''
    const seasonPoster = provider.imageUrlFor(season, 640)
    if (seasonPoster.length > 0) return seasonPoster
    return this.item === null ? '' : provider.imageUrlFor(this.item, 640)
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
        EmbyDetailPresentation.watched(episode), this.selectionFor(episode))
    } catch (_) {
      this.showDetailToast('无法播放该媒体')
    } finally {
      this.playing = false
    }
  }

  private async play(item: EmbyItem): Promise<void> {
    if (this.playing) return
    this.playing = true
    try {
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, item, [item],
        EmbyDetailPresentation.watched(item), this.selectionFor(item))
    } catch (_) {
      this.showDetailToast('无法播放该媒体')
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
    this.updateTrackOptions()
  }

  private showDetailToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(message, this.materialThickness))
    } catch (_) {
      // The page may already be gone when an asynchronous playback request fails.
    }
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
    this.detailSheetType = EmbyDetailSheetType.PLAYBACK_VARIANTS
    this.showDetailSheet = true
  }

  private openMetadataSheet(type: EmbyDetailSheetType): void {
    if (this.item === null || this.loading || this.showDetailSheet) return
    if (type === EmbyDetailSheetType.OVERVIEW && this.item.overview.length === 0) return
    this.detailSheetType = type
    this.showDetailSheet = true
  }

  private seasonSelectOptions(): SelectOption[] {
    return this.seasonItems.map((season: EmbyItem): SelectOption => {
      return { value: season.subtitle().length > 0 ? season.subtitle() : season.name }
    })
  }

  private selectedSeasonIndex(): number {
    return this.seasonItems.findIndex((season: EmbyItem) => season.id === this.selectedSeasonId)
  }

  private selectedSeasonLabel(): string {
    const index = this.selectedSeasonIndex()
    if (index < 0) return '选择季'
    const season = this.seasonItems[index]
    return season.subtitle().length > 0 ? season.subtitle() : season.name
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

  private episodeRangeSelectOptions(): SelectOption[] {
    return this.episodeRangeStarts().map((start: number): SelectOption => {
      return { value: '第 ' + this.rangeText(start) + ' 集' }
    })
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
  private DetailSheet(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      HdsNavigation() {
      Scroll(this.sheetScroller) {
        Column({ space: AppSpacing.SM }) {
          if (this.detailSheetType === EmbyDetailSheetType.PLAYBACK_VARIANTS) {
            ForEach(this.playbackVariants, (variant: PlaybackVariant) => {
              this.SelectionRow(variant.name.length > 0 ? variant.name : variant.id, variant.quality,
                variant.id === this.selectedVariantId, () => {
                  this.selectPlaybackVariant(variant)
                  this.showDetailSheet = false
                })
            }, (variant: PlaybackVariant) => 'variant_' + variant.id)
          } else if (this.item !== null) {
            Text(this.item!.name).fontSize(AppTypography.META).fontColor($r('sys.color.font_secondary'))
              .width('100%').padding({ bottom: AppSpacing.SM })
            if (this.detailSheetType === EmbyDetailSheetType.OVERVIEW) {
              Text(this.item!.overview).fontSize(AppTypography.BODY_LARGE).lineHeight(28)
                .fontColor($r('sys.color.font_primary')).width('100%').copyOption(CopyOptions.LocalDevice)
            } else {
              this.DetailInformationContent(this.item!)
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 24, bottom: 24 })
      }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor(Color.Transparent)
        .onAppear(() => this.sheetScroller.scrollTo({ xOffset: 0, yOffset: 0 }))
      }.width('100%').height('100%').mode(NavigationMode.Stack)
        .hideTitleBar(true).hideBackButton(true)
        .backgroundColor(deviceInfo.sdkApiVersion >= 26 ? Color.Transparent : $r('app.color.page_background'))
    }.width('100%').height('100%')
      // The bindSheet backplate owns the material and the unsupported-device surface fallback.
      .backgroundColor(Color.Transparent)
  }

  @Builder
  private SelectionRow(title: string, subtitle: string, selected: boolean, onSelect: () => void): void {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpacing.MD }) {
        Column({ space: 4 }) {
          Text(title).fontSize(AppTypography.BODY_LARGE).fontColor($r('sys.color.font_primary')).width('100%')
          if (subtitle.length > 0) {
            Text(subtitle).fontSize(AppTypography.META).fontColor($r('sys.color.font_secondary')).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (selected) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20)
            .fontColor([$r('sys.color.brand')]).accessibilityLevel('no')
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

  private displayDate(value: string): string {
    const date = value.indexOf('T') > 0 ? value.substring(0, value.indexOf('T')) : value
    return date.length > 0 ? date : value
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
