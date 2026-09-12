import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  HdsNavigation,
  HdsNavigationIconOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalPlaybackLauncher } from '../../services/LocalPlaybackLauncher'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import { PlaybackHistoryRecord } from '../../models/PlaybackHistoryRecord'
import { PlaybackHistoryViewItem } from '../../models/PlaybackHistoryViewItem'
import { PlaybackHistoryRepository } from '../../services/PlaybackHistoryRepository'
import { LOCAL_VIDEO_HISTORY_VERSION_KEY } from '../../store/LocalVideoHistoryChangeSignal'
import { LOCAL_MEDIA_LIBRARY_VERSION_KEY } from '../../store/LocalMediaLibraryChangeSignal'
import { UserDownloadFolder, UserFolderEntry } from '../../services/UserDownloadFolder'
import { Logger } from '../../utils/Logger'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import {
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  getBottomTabHideDistance,
  requestBottomTabAnimation,
  resolveBottomTabOffsetByDelta,
  resolveBottomTabSnapTarget
} from '../../utils/BottomTabAutoHide'
import { HIDE_MEDIA_CARDS_DEFAULT, PREFS_KEY_HIDE_CONTINUE_WATCHING, PREFS_KEY_HIDE_LOCAL_MEDIA } from '../../utils/MediaVisibilityPreferences'
import { PreferencesStore } from '../../store/PreferencesStore'
import { MediaSourceStore, MEDIA_SOURCE_VERSION_KEY } from '../../store/MediaSourceStore'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { PLAYBACK_HISTORY_VERSION_KEY } from '../../store/PlaybackHistoryChangeSignal'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { MediaItem } from '../../core/media/MediaItem'
import { MediaItemType } from '../../core/media/MediaItem'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { ProviderHomeSnapshot } from '../../models/ProviderHomeSnapshot'
import { LibraryHomeCoordinator } from '../../services/library/LibraryHomeCoordinator'
import { getMediaContentMaxWidth } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppDimensions } from '../../ui/theme/AppDimensions'
import { ResponsiveSizeClass, ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { MediaHero } from '../../components/media/MediaHero'
import { EmptyLibraryHero } from '../../components/media/EmptyLibraryHero'
import { ContinueWatchingCard as V2ContinueWatchingCard } from '../../components/media/ContinueWatchingCard'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { MediaShortcutTile } from '../../components/navigation/MediaShortcutTile'
import { MediaSourceShortcutCard } from '../../components/source/MediaSourceShortcutCard'
import { MediaLandscapeCard } from '../../components/media/MediaLandscapeCard'
import { MediaPosterCard } from '../../components/media/MediaPosterCard'

const logger = new Logger('LibraryPage')
const HOME_HISTORY_LIMIT = 6

@Entry
@Component
export struct LibraryPage {
  // 独立路由实例默认可用；首页嵌入时由 Index 显式传入当前 Tab 状态。
  @Prop @Watch('onActiveChanged') isActive: boolean = true
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onLocalHistoryVersionChanged') localHistoryVersion: number = 0
  @StorageLink(LOCAL_MEDIA_LIBRARY_VERSION_KEY) @Watch('onMediaLibraryChanged') mediaLibraryVersion: number = 0
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') appInForeground: boolean = true
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink(PREFS_KEY_HIDE_LOCAL_MEDIA) hideLocalMedia: boolean = HIDE_MEDIA_CARDS_DEFAULT
  @StorageLink(PREFS_KEY_HIDE_CONTINUE_WATCHING) hideContinueWatching: boolean = HIDE_MEDIA_CARDS_DEFAULT
  @StorageLink(MEDIA_SOURCE_VERSION_KEY) @Watch('onMediaSourceChanged') mediaSourceVersion: number = 0
  @StorageLink(PLAYBACK_HISTORY_VERSION_KEY) @Watch('onPlaybackHistoryChanged') playbackHistoryVersion: number = 0
  @State localHistory: LocalVideoRecord[] = []
  @State continueWatching: PlaybackHistoryViewItem[] = []
  @State ownFolderVideoCount: number = 0
  @State ownFolderCount: number = 0
  @State rootFolderEntries: UserFolderEntry[] = []
  @State rootFolderCoverRenderVersion: number = 0
  @State ownFolderScanned: boolean = false
  @State ownFolderScanning: boolean = false
  @State ownFolderScanFailed: boolean = false
  @State private mediaSources: MediaSourceInstance[] = []
  @State private homeSnapshots: ProviderHomeSnapshot[] = []
  private scroller: Scroller = new Scroller()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private unifiedHistoryStore: PlaybackHistoryStore = new PlaybackHistoryStore()
  private historyRepository: PlaybackHistoryRepository = new PlaybackHistoryRepository()
  private homeCoordinator: LibraryHomeCoordinator = new LibraryHomeCoordinator()
  private reloadGeneration: number = 0
  private reloadInFlight: boolean = false
  private reloadAgain: boolean = false
  private homeSnapshotInFlight: boolean = false
  private homeSnapshotAgain: boolean = false
  private hasScannedOwnFolder: boolean = false
  private isGeneratingCovers: boolean = false
  private pendingHistoryCoverGeneration: boolean = false
  private historyCoverGenerationToken: number = 0
  private isGeneratingRootEntryCovers: boolean = false
  private pendingRootEntryCoverGeneration: boolean = false
  private rootCoverGenerationToken: number = 0

  aboutToAppear(): void {
    this.reloadPageData()
  }

  onPageShow(): void {
    this.reloadPageData()
  }

  onPageHide(): void {
    this.cancelBackgroundCoverWork()
  }

  aboutToDisappear(): void {
    this.cancelBackgroundCoverWork()
  }

  onRdbReadyChanged(): void {
    if (this.appRdbReady && this.isActive) {
      void this.reloadPageData()
    }
  }

  onLocalHistoryVersionChanged(): void {
    if (this.appRdbReady && this.isActive) {
      void this.reloadPageData()
    }
  }

  onMediaLibraryChanged(): void {
    if (this.isActive) {
      this.reloadPageData()
    }
  }

  onMediaSourceChanged(): void {
    if (this.isActive) void this.reloadPageData()
  }

  onPlaybackHistoryChanged(): void {
    if (this.appRdbReady && this.isActive) void this.reloadPageData()
  }

  onActiveChanged(): void {
    if (this.isActive) {
      this.reloadPageData()
    } else {
      this.cancelBackgroundCoverWork()
    }
  }

  onAppForegroundChanged(): void {
    if (this.appInForeground && this.isActive) {
      this.reloadPageData()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: 0 }) {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')

            this.MediaLibraryContent()

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ left: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
            right: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp) })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .clip(false)
        .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
          this.updateBottomTabOffset(yOffset)
        })
        .onScrollStop(() => this.snapBottomTabOffset())
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildLocalTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.home_bg_top'), 0],
        [$r('app.color.page_background'), 0.22],
        [$r('app.color.page_background'), 1]
      ]
    })
  }

  @Builder
  private MediaLibraryContent(): void {
    Column({ space: 0 }) {
      this.HomeHeroSectionV2()
      if (this.getSecondaryHistory().length > 0) {
        this.RecentWatchingSectionV2()
      }
      this.QuickAccessSectionV2()
      this.LocalMediaSectionV2()
      this.RemoteHomeSectionV2()
    }
    .width('100%')
    .constraintSize({ maxWidth: getMediaContentMaxWidth(this.screenWidthVp) || '100%' })
  }

  @Builder
  private HomeHeroSectionV2(): void {
    if (this.getHeroHistory() !== null) {
      MediaHero({
        title: this.heroTitle(),
        subtitle: this.heroSubtitle(),
        artworkUrl: this.heroArtworkUrl(),
        positionMs: this.heroPositionMs(),
        durationMs: this.heroDurationMs(),
        heightVp: AppDimensions.HERO_PHONE_HEIGHT,
        widthVp: this.screenWidthVp,
        onPlay: () => this.openHeroHistory()
      })
        .margin({ top: 12 })
    } else {
      EmptyLibraryHero({
        minHeight: this.emptyHeroMinHeight(),
        onOpenVideo: () => { void this.openVideoFile() },
        onOpenLocal: () => this.openFolderPage(),
        onConnectSource: () => router.pushUrl({ url: 'pages/sources/AddSourcePage' })
      })
        .margin({ top: AppSpacing.MD })
    }
  }

  @Builder
  private RecentWatchingSectionV2(): void {
    Column({ space: 10 }) {
      MediaSectionHeader({ title: '最近观看', actionText: '全部',
        onAction: () => this.openPlaybackHistoryPage() })
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.getSecondaryHistory(), (record: PlaybackHistoryViewItem) => {
            V2ContinueWatchingCard({
              title: record.title,
              subtitle: this.watchSummary(record),
              artworkUrl: record.artworkUrl,
              positionMs: record.positionMs,
              durationMs: record.durationMs,
              cardWidth: ResponsiveSizeClassResolver.landscapeWidth(this.screenWidthVp),
              onCardClick: () => {
                void this.openHistoryRecord(record)
              }
            })
          }, (record: PlaybackHistoryViewItem) => 'home_recent_' + record.key + '_' + record.positionMs)
        }
        .padding({ right: 24 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('calc(100% + 16vp)')
      .margin({ right: -16 })
    }
    .width('100%')
    .margin({ top: AppSpacing.SECTION_COMPACT })
  }

  @Builder
  private QuickAccessSectionV2(): void {
    Column({ space: 10 }) {
      MediaSectionHeader({ title: '我的媒体', actionText: '', onAction: () => undefined })
      Scroll() {
        Row({ space: 10 }) {
          MediaShortcutTile({ title: '打开视频', subtitle: '选择本地文件', iconKind: 'play',
            tileWidth: ResponsiveSizeClassResolver.shortcutWidth(this.screenWidthVp),
            tileHeight: ResponsiveSizeClassResolver.shortcutHeight(this.screenWidthVp),
            onClickAction: () => {
              void this.openVideoFile()
            } })
          MediaShortcutTile({ title: '本地媒体', subtitle: '应用专属目录', iconKind: 'folder',
            tileWidth: ResponsiveSizeClassResolver.shortcutWidth(this.screenWidthVp),
            tileHeight: ResponsiveSizeClassResolver.shortcutHeight(this.screenWidthVp),
            onClickAction: () => this.openFolderPage() })
          ForEach(this.quickAccessSources(), (source: MediaSourceInstance) => {
            MediaSourceShortcutCard({
              title: source.name,
              providerType: source.providerType,
              statusText: this.sourceStatus(source),
              isEnabled: source.enabled || source.providerType === 'local',
              tileWidth: ResponsiveSizeClassResolver.shortcutWidth(this.screenWidthVp),
              tileHeight: ResponsiveSizeClassResolver.shortcutHeight(this.screenWidthVp),
              onCardClick: () => this.openSource(source)
            })
          }, (source: MediaSourceInstance) => 'home_quick_source_' + source.id)
          MediaShortcutTile({ title: '添加媒体源', subtitle: 'Emby / WebDAV', iconKind: 'plus',
            tileWidth: ResponsiveSizeClassResolver.shortcutWidth(this.screenWidthVp),
            tileHeight: ResponsiveSizeClassResolver.shortcutHeight(this.screenWidthVp),
            onClickAction: () => router.pushUrl({ url: 'pages/sources/AddSourcePage' }) })
        }
        .padding({ right: 24 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('calc(100% + 16vp)')
      .margin({ right: -16 })
    }
    .width('100%')
    .margin({ top: AppSpacing.SECTION_COMPACT })
  }

  @Builder
  private RemoteHomeSectionV2(): void {
    if (this.homeSnapshots.length > 0) {
      Column({ space: 14 }) {
        ForEach(this.homeSnapshots, (snapshot: ProviderHomeSnapshot) => {
          ForEach(snapshot.sections, (section: import('../../core/media/MediaSection').MediaSection) => {
            Column({ space: 8 }) {
              MediaSectionHeader({
                title: snapshot.sourceName.length > 0 ? snapshot.sourceName + ' · ' + section.title : section.title,
                actionText: '浏览',
                onAction: () => this.openHomeSection(snapshot.sourceId, section.id, section.title)
              })
              Scroll() {
                Row({ space: 10 }) {
                  ForEach(section.items.slice(0, 8), (item: MediaItem) => {
                    this.RemoteHomeItem(item)
                  }, (item: MediaItem) => 'home_remote_' + item.sourceId + '_' + item.id)
                }.padding({ right: 24 })
              }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                .width('calc(100% + 16vp)').margin({ right: -16 })
            }.width('100%')
          }, (section: import('../../core/media/MediaSection').MediaSection) =>
            'home_remote_section_' + snapshot.sourceId + '_' + section.id)
        }, (snapshot: ProviderHomeSnapshot) => 'home_remote_source_' + snapshot.sourceId)
      }.width('100%').margin({ top: 18 })
    }
  }

  @Builder
  private RemoteHomeItem(item: MediaItem): void {
    if (this.isPosterHomeItem(item)) {
      MediaPosterCard({
        title: item.title,
        subtitle: item.subtitle.length > 0 ? item.subtitle : (item.browsable ? '浏览' : '播放'),
        artworkUrl: item.poster,
        cardWidth: ResponsiveSizeClassResolver.posterWidth(this.screenWidthVp),
        sharedTransitionId: this.embyArtworkSharedTransitionId(item),
        onCardClick: () => {
          void this.openHomeItem(item)
        }
      })
    } else {
      MediaLandscapeCard({
        title: item.title,
        subtitle: item.subtitle.length > 0 ? item.subtitle : (item.browsable ? '浏览' : '播放'),
        artworkUrl: item.poster,
        positionMs: item.positionMs,
        durationMs: item.durationMs,
        cardWidth: ResponsiveSizeClassResolver.landscapeWidth(this.screenWidthVp),
        onCardClick: () => {
          void this.openHomeItem(item)
        }
      })
    }
  }

  private sourceStatus(source: MediaSourceInstance): string {
    if (source.providerType === 'local' || source.enabled) return ''
    return '已停用'
  }

  private quickAccessSources(): MediaSourceInstance[] {
    const result: MediaSourceInstance[] = []
    for (let i = 0; i < this.mediaSources.length; i++) {
      if (this.mediaSources[i].providerType !== 'local' && this.mediaSources[i].id !== 'local') {
        result.push(this.mediaSources[i])
      }
    }
    return result
  }

  @Builder
  private LocalMediaSectionV2(): void {
    Column({ space: 10 }) {
      MediaSectionHeader({ title: '本地媒体', actionText: '浏览',
        onAction: () => this.openFolderPage() })
      if (this.hideLocalMedia) {
        this.HiddenCardsHint()
      } else {
        if (this.recentLocalEntries().length > 0) {
          Text('最近文件')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.recentLocalEntries(), (entry: UserFolderEntry) => {
                this.LocalRecentEntryCard(entry)
              }, (entry: UserFolderEntry) => 'home_local_recent_' + entry.relativePath)
            }
            .padding({ right: 24 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('calc(100% + 16vp)')
          .margin({ right: -16 })
        }
        if (this.folderLocalEntries().length > 0) {
          Text('文件夹')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.folderLocalEntries(), (entry: UserFolderEntry) => {
                this.RootFolderEntryGridCard(entry)
              }, (entry: UserFolderEntry) => 'home_local_folder_' + entry.relativePath)
            }
            .padding({ right: 24 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('calc(100% + 16vp)')
          .margin({ right: -16 })
        }
        if (this.recentLocalEntries().length === 0 && this.folderLocalEntries().length === 0) {
          this.LocalMediaEmptyCard()
        }
      }
    }
    .width('100%')
    .margin({ top: AppSpacing.SECTION, bottom: AppSpacing.SECTION_COMPACT })
  }

  @Builder
  private LocalRecentEntryCard(entry: UserFolderEntry): void {
    MediaLandscapeCard({
      title: entry.name,
      subtitle: this.buildRootFolderEntryStatus(entry),
      artworkUrl: entry.video.coverUri,
      positionMs: entry.video.positionMs,
      durationMs: entry.video.durationMs,
      cardWidth: ResponsiveSizeClassResolver.landscapeWidth(this.screenWidthVp),
      onCardClick: () => this.openRootFolderEntry(entry)
    })
  }

  private openSource(source: MediaSourceInstance): void {
    const descriptor = ProviderCatalog.get(source.providerType)
    if (descriptor === null || descriptor.browserRoute.length === 0) return
    void router.pushUrl({ url: descriptor.browserRoute, params: descriptor.browserParams(source.id) })
  }

  @Builder
  private RootFolderEntryGridCard(entry: UserFolderEntry): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (entry.isDirectory) {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(44)
            .fontColor([$r('app.color.accent_blue')])
        } else {
          Image(entry.video.coverUri.length > 0 ? entry.video.coverUri : $r('app.media.ic_placeholder'))
            .draggable(false)
            .width('100%')
            .height(92)
            .objectFit(ImageFit.Cover)
            .opacity(entry.video.coverUri.length > 0 ? 1 : 0.82)
        }

      }
      .width('100%')
      .height(92)
      .borderRadius(12)
      .clip(true)
      .backgroundColor(entry.isDirectory ? $r('app.color.button_ghost_bg') : $r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })

      Text(entry.name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.buildRootFolderEntryStatus(entry))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(176)
    .onClick(() => this.openRootFolderEntry(entry))
  }

  @Builder
  private LocalMediaEmptyCard(): void {
    Column({ space: 8 }) {
      SymbolGlyph(this.ownFolderScanning ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.folder'))
        .fontSize(32)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.buildOwnFolderStatusText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(132)
    .borderRadius(12)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.openFolderPage())
  }

  private async reloadPageData(): Promise<void> {
    if (this.reloadInFlight) {
      this.reloadAgain = true
      return
    }
    this.reloadInFlight = true
    try {
      await this.performReloadPageData()
    } finally {
      this.reloadInFlight = false
      if (this.reloadAgain) {
        this.reloadAgain = false
        void this.reloadPageData()
      }
    }
  }

  private async performReloadPageData(): Promise<void> {
    if (!this.isActive) {
      return
    }
    const generation = ++this.reloadGeneration
    if (this.appRdbReady) {
      await this.loadLocalHistory(generation)
    }
    if (generation !== this.reloadGeneration || !this.isActive) return
    this.mediaSources = await MediaSourceStore.getAll()
    if (generation !== this.reloadGeneration || !this.isActive) return
    void this.loadHomeSnapshots(generation)
    if (this.appRdbReady) {
      await this.loadContinueWatchingHistory(generation)
    }
    if (generation === this.reloadGeneration && this.isActive) {
      this.scanOwnFolderIfNeeded(true)
    }
  }

  private async loadHomeSnapshots(generation: number): Promise<void> {
    if (this.homeSnapshotInFlight) {
      this.homeSnapshotAgain = true
      return
    }
    this.homeSnapshotInFlight = true
    try {
      await this.performLoadHomeSnapshots(generation)
    } finally {
      this.homeSnapshotInFlight = false
      const nextGeneration = this.reloadGeneration
      const shouldReload = this.homeSnapshotAgain && nextGeneration !== generation
      this.homeSnapshotAgain = false
      if (shouldReload) {
        void this.loadHomeSnapshots(nextGeneration)
      }
    }
  }

  private async performLoadHomeSnapshots(generation: number): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const snapshots = await this.homeCoordinator.load(context)
      if (generation === this.reloadGeneration && this.isActive) this.homeSnapshots = snapshots
    } catch (err) {
      if (generation === this.reloadGeneration) {
        logger.warn('加载首页来源快照失败: %{public}s', err instanceof Error ? err.message : String(err))
        this.homeSnapshots = []
      }
    }
  }

  private async openHomeItem(item: MediaItem): Promise<void> {
    try {
      if (this.isEmbyContentItem(item)) {
        await router.pushUrl({
          url: 'pages/emby/EmbyDetailPage',
          params: this.embyDetailParams(item)
        })
        return
      }
      if (item.browsable) {
        const descriptor = ProviderCatalog.get(this.providerTypeForSource(item.sourceId))
        if (descriptor === null || descriptor.browserRoute.length === 0) throw new Error('该来源暂不支持浏览')
        const params = descriptor.browserParams(item.sourceId)
        params.parentId = item.id
        await router.pushUrl({ url: descriptor.browserRoute, params: params })
      } else if (item.playable) {
        await ProviderPlaybackLauncher.open(this.getUIContext(), item)
      }
    } catch (err) {
      logger.warn('打开首页推荐失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private isPosterHomeItem(item: MediaItem): boolean {
    return item.type === MediaItemType.MOVIE || item.type === MediaItemType.SERIES ||
      item.type === MediaItemType.SEASON || item.type === MediaItemType.COLLECTION
  }

  private async openHomeSection(sourceId: string, sectionId: string, sectionTitle: string = ''): Promise<void> {
    try {
      const descriptor = ProviderCatalog.get(this.providerTypeForSource(sourceId))
      if (descriptor === null || descriptor.browserRoute.length === 0) throw new Error('该来源暂不支持浏览')
      const params = descriptor.sectionParams(sourceId, sectionId, sectionTitle)
      await router.pushUrl({ url: descriptor.browserRoute, params: params })
    } catch (err) {
      logger.warn('打开首页推荐区失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private isEmbyContentItem(item: MediaItem): boolean {
    const providerType = this.providerTypeForSource(item.sourceId)
    if (providerType !== 'emby') return false
    return item.type === MediaItemType.MOVIE || item.type === MediaItemType.SERIES ||
      item.type === MediaItemType.SEASON || item.type === MediaItemType.EPISODE ||
      item.type === MediaItemType.VIDEO || item.type === MediaItemType.COLLECTION
  }

  private embyDetailParams(item: MediaItem): Record<string, Object> {
    const params: Record<string, Object> = { 'sourceId': item.sourceId, 'itemId': item.id }
    if (item.type === MediaItemType.SEASON && item.seriesId.length > 0) {
      params['itemId'] = item.seriesId
      params['initialSeasonId'] = item.id
    } else if (item.type === MediaItemType.EPISODE && item.seriesId.length > 0) {
      params['itemId'] = item.seriesId
      params['initialSeasonId'] = item.seasonId.length > 0 ? item.seasonId : item.parentId
      params['initialEpisodeId'] = item.id
      params['initialEpisodeIndex'] = item.indexNumber
    }
    return params
  }

  private providerTypeForSource(sourceId: string): string {
    const normalized = sourceId.trim().toLowerCase()
    for (let i = 0; i < this.mediaSources.length; i++) {
      if (this.mediaSources[i].id.trim().toLowerCase() === normalized) return this.mediaSources[i].providerType
    }
    return normalized
  }

  private embyArtworkSharedTransitionId(item: MediaItem): string {
    return this.providerTypeForSource(item.sourceId) === 'emby' ?
      'emby_artwork_' + item.sourceId + '_' + item.id : ''
  }

  @Builder
  private HiddenCardsHint(): void {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.eye_slash')).fontSize(18).fontColor([$r('app.color.text_secondary')])
      Text('内容已隐藏')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(58)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .borderRadius(12)
  }

  private async toggleLocalMediaVisibility(): Promise<void> {
    const next = !this.hideLocalMedia
    this.hideLocalMedia = next
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_HIDE_LOCAL_MEDIA, next)
  }

  private async toggleContinueWatchingVisibility(): Promise<void> {
    const next = !this.hideContinueWatching
    this.hideContinueWatching = next
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_HIDE_CONTINUE_WATCHING, next)
  }

  private async loadLocalHistory(generation: number = this.reloadGeneration): Promise<void> {
    try {
      const records = await this.historyStore.getAll()
      if (generation !== this.reloadGeneration) return
      this.localHistory = records
      this.bindRootEntryHistory()
      this.ensureHistoryExitCovers()
    } catch (err) {
      if (generation !== this.reloadGeneration) return
      logger.warn('加载本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.localHistory = []
    }
  }

  private async loadContinueWatchingHistory(generation: number = this.reloadGeneration): Promise<void> {
    try {
      const merged: PlaybackHistoryViewItem[] = []
      for (let i = 0; i < this.localHistory.length; i++) {
        const localItem = this.toHistoryViewItemFromLocal(this.localHistory[i])
        if (!localItem.completed) merged.push(localItem)
      }
      const enabledSources: Record<string, boolean> = {}
      for (let i = 0; i < this.mediaSources.length; i++) {
        enabledSources[this.mediaSources[i].id] = this.mediaSources[i].enabled
      }
      const serverSourceIds: Record<string, boolean> = {}
      const context = getContext(this) as common.UIAbilityContext
      for (let i = 0; i < this.mediaSources.length; i++) {
        const source = this.mediaSources[i]
        if (source.providerType === 'local' || source.enabled !== true) continue
        try {
          const provider = await ProviderRegistry.get(source.id, context, true)
          if (provider === null || !provider.hasCapability(ProviderCapability.RESUME)) continue
          const items = await provider.getResumeItems(HOME_HISTORY_LIMIT)
          for (let j = 0; j < items.length; j++) {
            const item = items[j]
            if (item === null || typeof item !== 'object' || Array.isArray(item) ||
              item.playable !== true || item.id.trim().length === 0) continue
            const viewItem = this.toHistoryViewItemFromMedia(item)
            if (!viewItem.completed) merged.push(viewItem)
          }
          serverSourceIds[source.id] = true
        } catch (err) {
          logger.warn('读取来源续播失败，回退本地缓存: source=%{public}s error=%{public}s',
            source.id, err instanceof Error ? err.message : String(err))
        }
      }
      const unified = await this.unifiedHistoryStore.getAll()
      for (let i = 0; i < unified.length; i++) {
        const record = unified[i]
        if (record.sourceId === 'local' || enabledSources[record.sourceId] !== true) continue
        if (serverSourceIds[record.sourceId] === true) continue
        if (record.durationMs > 0 && record.positionMs / record.durationMs >= 0.995) continue
        const viewItem = this.toHistoryViewItemFromRecord(record)
        if (!viewItem.completed) merged.push(viewItem)
      }
      merged.sort((left: PlaybackHistoryViewItem, right: PlaybackHistoryViewItem) => right.lastPlayedAt - left.lastPlayedAt)
      await this.historyRepository.resolveArtwork(merged, context)
      if (generation !== this.reloadGeneration) return
      this.continueWatching = merged
    } catch (err) {
      if (generation !== this.reloadGeneration) return
      logger.warn('加载统一继续观看记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      const fallback: PlaybackHistoryViewItem[] = []
      for (let i = 0; i < this.localHistory.length; i++) {
        const item = this.toHistoryViewItemFromLocal(this.localHistory[i])
        if (!item.completed) fallback.push(item)
      }
      this.continueWatching = fallback
    }
  }

  private toHistoryViewItemFromLocal(record: LocalVideoRecord): PlaybackHistoryViewItem {
    const item = new PlaybackHistoryViewItem()
    item.sourceId = 'local'
    item.mediaId = record.fileKey.length > 0 ? record.fileKey : record.fileUri
    item.key = item.mediaId.length > 0 ? 'local:' + item.mediaId : ''
    item.title = record.fileName
    item.artworkRef = record.coverUri
    item.artworkUrl = record.coverUri
    item.positionMs = record.positionMs
    item.durationMs = record.durationMs
    item.lastPlayedAt = record.lastPlayedAt
    item.completed = this.isCompleted(item)
    return item
  }

  private toHistoryViewItemFromRecord(record: PlaybackHistoryRecord): PlaybackHistoryViewItem {
    const item = new PlaybackHistoryViewItem()
    item.sourceId = record.sourceId
    item.mediaId = record.mediaId
    item.key = item.sourceId.length > 0 && item.mediaId.length > 0 ? item.sourceId + ':' + item.mediaId : ''
    item.title = record.title.length > 0 ? record.title : record.mediaId
    item.subtitle = record.subtitle
    item.artworkRef = record.artworkRef.length > 0 ? record.artworkRef : record.artwork
    item.artworkUrl = ''
    item.positionMs = record.positionMs
    item.durationMs = record.durationMs
    item.lastPlayedAt = record.lastPlayedAt
    item.remoteRecordId = record.id
    item.completed = this.isCompleted(item)
    return item
  }

  private toHistoryViewItemFromMedia(record: MediaItem): PlaybackHistoryViewItem {
    const item = new PlaybackHistoryViewItem()
    item.sourceId = record.sourceId
    item.mediaId = record.id
    item.key = item.sourceId.length > 0 && item.mediaId.length > 0 ? item.sourceId + ':' + item.mediaId : ''
    item.title = record.title.length > 0 ? record.title : record.id
    item.subtitle = record.subtitle
    item.artworkRef = record.artworkRef.length > 0 ? record.artworkRef : record.poster
    item.artworkUrl = record.poster
    item.positionMs = record.positionMs
    item.durationMs = record.durationMs
    item.lastPlayedAt = Date.now()
    item.completed = this.isCompleted(item)
    return item
  }

  private async scanOwnFolderIfNeeded(force: boolean = false): Promise<void> {
    if (this.ownFolderScanning || (this.hasScannedOwnFolder && !force)) {
      return
    }
    this.ownFolderScanning = true
    this.ownFolderScanFailed = false
    try {
      const context = getContext(this) as common.UIAbilityContext
      let videos = await UserDownloadFolder.scanOwnVideoFiles(context)
      if (videos === null) {
        logger.warn('媒体库扫描失败，尝试重新激活应用专属目录')
        const reactivatedPath = await UserDownloadFolder.reactivateOwnFolder(context)
        if (reactivatedPath.length > 0) {
          videos = await UserDownloadFolder.scanOwnVideoFiles(context)
        }
      }
      if (videos === null) {
        this.ownFolderScanFailed = true
        return
      }
      this.ownFolderVideoCount = videos.length
      let rootEntries = await UserDownloadFolder.listOwnDirectory(context)
      if (rootEntries === null) {
        const reactivatedPath = await UserDownloadFolder.reactivateOwnFolder(context)
        if (reactivatedPath.length > 0) {
          videos = await UserDownloadFolder.scanOwnVideoFiles(context) ?? []
          rootEntries = await UserDownloadFolder.listOwnDirectory(context)
          this.ownFolderVideoCount = videos.length
        }
      }
      let directoryCount = 0
      if (rootEntries !== null) {
        for (let i = 0; i < rootEntries.length; i++) {
          if (rootEntries[i].isDirectory) {
            directoryCount++
          }
        }
        this.rootFolderEntries = this.buildLibraryEntries(rootEntries, videos)
        this.bindRootEntryHistory()
        this.ensureRootEntryCovers()
      } else {
        this.rootFolderEntries = []
      }
      this.ownFolderCount = directoryCount
      this.ownFolderScanned = true
      this.hasScannedOwnFolder = true
    } catch (err) {
      logger.warn('读取应用专属目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.ownFolderScanFailed = true
    } finally {
      this.ownFolderScanning = false
    }
  }

  private async ensureRootEntryCovers(): Promise<void> {
    if (!this.isActive) {
      return
    }
    if (this.isGeneratingRootEntryCovers) {
      this.pendingRootEntryCoverGeneration = true
      this.rootCoverGenerationToken++
      return
    }
    this.isGeneratingRootEntryCovers = true
    this.pendingRootEntryCoverGeneration = false
    const generationToken = ++this.rootCoverGenerationToken
    try {
      const entryCount = this.rootFolderEntries.length
      for (let i = 0; i < entryCount; i++) {
        if (!this.isActive || generationToken !== this.rootCoverGenerationToken ||
          i >= this.rootFolderEntries.length) {
          break
        }
        const entry = this.rootFolderEntries[i]
        if (entry.isDirectory) {
          continue
        }
        if (entry.video.fileUri.length === 0 || !await LocalFilePicker.ensureReadableUri(entry.video.fileUri)) {
          continue
        }
        const coverUri = await LocalVideoThumbnailStore.getInstance().ensureRandomThumbnail(
          entry.video.fileUri,
          entry.video.fileName,
          entry.video.fileSize
        )
        if (!this.isActive || generationToken !== this.rootCoverGenerationToken ||
          coverUri.length === 0 || i >= this.rootFolderEntries.length ||
          this.rootFolderEntries[i].video.fileUri !== entry.video.fileUri) {
          continue
        }
        if (this.rootFolderEntries[i].video.coverUri !== coverUri) {
          this.rootFolderEntries[i].video.coverUri = coverUri
          this.rootFolderEntries = this.rootFolderEntries.slice()
          this.rootFolderCoverRenderVersion++
        }
      }
    } catch (err) {
      logger.warn('生成首页媒体库视频随机帧封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingRootEntryCovers = false
      if (this.pendingRootEntryCoverGeneration && this.isActive) {
        this.pendingRootEntryCoverGeneration = false
        this.ensureRootEntryCovers()
      }
    }
  }

  /**
   * The home library is a grid view of the app media library. Keep the root
   * folders for navigation, then append videos discovered in subfolders so the
   * grid never drops them merely because they are not direct root children.
   */
  private buildLibraryEntries(rootEntries: UserFolderEntry[], videos: LocalVideoRecord[]): UserFolderEntry[] {
    // Defensive filter: even if a device returns an unexpected path shape
    // from listFileSync, never render the conversion package as media cards.
    const entries: UserFolderEntry[] = []
    for (let i = 0; i < rootEntries.length; i++) {
      entries.push(rootEntries[i])
    }
    const knownVideoUris: Map<string, boolean> = new Map()
    for (let i = 0; i < entries.length; i++) {
      if (!entries[i].isDirectory) {
        knownVideoUris.set(entries[i].video.fileUri, true)
      }
    }
    for (let i = 0; i < videos.length; i++) {
      if (knownVideoUris.has(videos[i].fileUri)) {
        continue
      }
      const entry = new UserFolderEntry()
      entry.name = videos[i].fileName
      // This is a stable grid key for a recursive video, not a navigation path.
      entry.relativePath = videos[i].fileUri
      entry.video = videos[i]
      entries.push(entry)
      knownVideoUris.set(videos[i].fileUri, true)
    }
    entries.sort((first: UserFolderEntry, second: UserFolderEntry): number => {
      if (first.isDirectory !== second.isDirectory) {
        return first.isDirectory ? -1 : 1
      }
      return first.name.localeCompare(second.name)
    })
    return entries
  }

  private recentLocalEntries(): UserFolderEntry[] {
    const entries: UserFolderEntry[] = []
    for (let i = 0; i < this.rootFolderEntries.length; i++) {
      if (!this.rootFolderEntries[i].isDirectory) entries.push(this.rootFolderEntries[i])
    }
    entries.sort((left: UserFolderEntry, right: UserFolderEntry): number => {
      const leftPlayedAt = left.video.lastPlayedAt > 0 ? left.video.lastPlayedAt : left.video.createdAt
      const rightPlayedAt = right.video.lastPlayedAt > 0 ? right.video.lastPlayedAt : right.video.createdAt
      return rightPlayedAt - leftPlayedAt
    })
    return entries.slice(0, 8)
  }

  private folderLocalEntries(): UserFolderEntry[] {
    const entries: UserFolderEntry[] = []
    for (let i = 0; i < this.rootFolderEntries.length; i++) {
      if (this.rootFolderEntries[i].isDirectory) entries.push(this.rootFolderEntries[i])
    }
    return entries
  }

  private buildRootFolderEntryStatus(entry: UserFolderEntry): string {
    if (!entry.isDirectory) {
      const item = this.toHistoryViewItemFromLocal(entry.video)
      return entry.video.durationMs > 0 ? this.watchSummary(item) : '本地视频'
    }
    const parts: string[] = []
    if (entry.childVideoCount > 0) {
      parts.push(entry.childVideoCount + ' 个视频')
    }
    if (entry.childDirectoryCount > 0) {
      parts.push(entry.childDirectoryCount + ' 个文件夹')
    }
    if (parts.length > 0) {
      return parts.join(' · ')
    }
    return entry.isM3u8Package ? 'm3u8 分片' : '空文件夹'
  }

  private openRootFolderEntry(entry: UserFolderEntry): void {
    if (entry.isDirectory) {
      if (entry.isM3u8Package) {
        void this.showM3u8FolderDialog(entry)
        return
      }
      router.pushUrl({ url: 'pages/local/FolderPage', params: { relativePath: entry.relativePath } })
      return
    }
    this.openHistoryRecord(this.toHistoryViewItemFromLocal(entry.video), this.getRootFolderVideoQueue())
  }

  /** Keep the home media library interaction aligned with FolderPage. */
  private async showM3u8FolderDialog(entry: UserFolderEntry): Promise<void> {
    if (await UserDownloadFolder.isM3u8PromptSuppressed(entry.relativePath)) {
      router.pushUrl({ url: 'pages/local/FolderPage', params: { relativePath: entry.relativePath } })
      return
    }
    this.getUIContext().showAlertDialog({
      title: '检测到 m3u8 分片',
      message: '检测到该文件夹包含 m3u8 分片，是否合成 MP4 格式？',
      buttons: [
        {
          value: '是',
          action: () => {
            router.pushUrl({
              url: 'pages/tools/M3u8ConverterPage',
              params: { relativePath: entry.relativePath }
            })
          }
        },
        {
          value: '否',
          action: () => {
            router.pushUrl({
              url: 'pages/local/FolderPage',
              params: { relativePath: entry.relativePath }
            })
          }
        },
        {
          value: '不再提醒',
          action: () => {
            void UserDownloadFolder.suppressM3u8Prompt(entry.relativePath)
            router.pushUrl({
              url: 'pages/local/FolderPage',
              params: { relativePath: entry.relativePath }
            })
          }
        }
      ]
    })
  }

  private getRootFolderVideoQueue(): LocalVideoRecord[] {
    const videos: LocalVideoRecord[] = []
    for (let i = 0; i < this.rootFolderEntries.length; i++) {
      if (!this.rootFolderEntries[i].isDirectory) {
        videos.push(this.rootFolderEntries[i].video)
      }
    }
    return videos
  }

  private bindRootEntryHistory(): void {
    for (let i = 0; i < this.rootFolderEntries.length; i++) {
      const entry = this.rootFolderEntries[i]
      if (entry.isDirectory) {
        continue
      }
      for (let j = 0; j < this.localHistory.length; j++) {
        const history = this.localHistory[j]
        if (history.fileUri === entry.video.fileUri && history.fileSize === entry.video.fileSize) {
          entry.video.durationMs = history.durationMs
          entry.video.positionMs = history.positionMs
          entry.video.lastPlayedAt = history.lastPlayedAt
          break
        }
      }
    }
    if (this.rootFolderEntries.length > 0) {
      this.rootFolderEntries = this.rootFolderEntries.slice()
    }
  }

  private async ensureHistoryExitCovers(): Promise<void> {
    if (!this.isActive || this.localHistory.length === 0) {
      return
    }
    if (this.isGeneratingCovers) {
      this.pendingHistoryCoverGeneration = true
      this.historyCoverGenerationToken++
      return
    }
    this.isGeneratingCovers = true
    this.pendingHistoryCoverGeneration = false
    const generationToken = ++this.historyCoverGenerationToken
    try {
      for (let i = 0; i < this.localHistory.length; i++) {
        if (!this.isActive || generationToken !== this.historyCoverGenerationToken) {
          break
        }
        const record = this.localHistory[i]
        if (record.coverUri.length > 0 || record.fileUri.length === 0 || record.fileKey.length === 0 ||
          !await LocalFilePicker.ensureReadableUri(record.fileUri)) {
          continue
        }
        const coverPositionMs = record.durationMs > 0
          ? Math.min(record.positionMs, Math.max(0, record.durationMs - 1))
          : record.positionMs
        const coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(record.fileUri, record.fileName, record.fileSize, coverPositionMs)
        if (!this.isActive || generationToken !== this.historyCoverGenerationToken) {
          break
        }
        if (coverUri.length > 0 && coverUri !== record.coverUri) {
          await this.historyStore.updateCoverUri(record.fileKey, coverUri)
          this.localHistory[i].coverUri = coverUri
          this.localHistory = this.localHistory.slice()
        }
      }
    } catch (err) {
      logger.warn('生成本地视频封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingCovers = false
      if (this.pendingHistoryCoverGeneration && this.isActive) {
        this.pendingHistoryCoverGeneration = false
        this.ensureHistoryExitCovers()
      }
    }
  }

  private cancelBackgroundCoverWork(): void {
    this.rootCoverGenerationToken++
    this.historyCoverGenerationToken++
    this.pendingRootEntryCoverGeneration = false
    this.pendingHistoryCoverGeneration = false
  }

  private openFolderPage(): void {
    router.pushUrl({ url: 'pages/local/FolderPage', params: { relativePath: '' } })
  }

  private openPlaybackHistoryPage(): void {
    router.pushUrl({ url: 'pages/local/ContinueWatchingPage' })
  }

  private async openVideoFile(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext
    const result = await LocalFilePicker.pickVideoFile(context)
    if (result === null) return
    const record = new LocalVideoRecord()
    record.fileUri = result.uri
    record.fileName = result.fileName
    record.fileSize = result.fileSize
    record.positionMs = 0
    await LocalPlaybackLauncher.open(this.getUIContext(), record, [record], true)
  }

  private async openHistoryRecord(item: PlaybackHistoryViewItem, queue: LocalVideoRecord[] = this.localHistory): Promise<void> {
    if (item.sourceId !== 'local') {
      try {
        await ProviderPlaybackLauncher.openById(this.getUIContext(), item.sourceId, item.mediaId,
          item.positionMs)
      } catch (err) {
        logger.warn('打开远程继续观看记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      }
      return
    }
    const localRecord = this.findLocalRecord(item.mediaId)
    if (localRecord !== null) await LocalPlaybackLauncher.open(this.getUIContext(), localRecord, queue)
  }

  private getHomeHistory(): PlaybackHistoryViewItem[] {
    const result: PlaybackHistoryViewItem[] = []
    for (let i = 0; i < this.continueWatching.length && result.length < HOME_HISTORY_LIMIT; i++) {
      result.push(this.continueWatching[i])
    }
    return result
  }

  private getHeroHistory(): PlaybackHistoryViewItem | null {
    if (this.hideContinueWatching) return null
    const records = this.getHomeHistory()
    return records.length > 0 ? records[0] : null
  }

  private emptyHeroMinHeight(): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(this.screenWidthVp)
    if (sizeClass === ResponsiveSizeClass.LARGE || sizeClass === ResponsiveSizeClass.EXPANDED) return 320
    if (sizeClass === ResponsiveSizeClass.MEDIUM) return 300
    return 280
  }

  private heroTitle(): string {
    const record = this.getHeroHistory()
    return record === null ? '' : record.title
  }

  private heroSubtitle(): string {
    const record = this.getHeroHistory()
    return record === null ? '' : (record.subtitle.length > 0 ? record.subtitle : this.watchSummary(record))
  }

  private heroArtworkUrl(): string {
    const record = this.getHeroHistory()
    return record === null ? '' : record.artworkUrl
  }

  private heroPositionMs(): number {
    const record = this.getHeroHistory()
    return record === null ? 0 : record.positionMs
  }

  private heroDurationMs(): number {
    const record = this.getHeroHistory()
    return record === null ? 0 : record.durationMs
  }

  private openHeroHistory(): void {
    const record = this.getHeroHistory()
    if (record !== null) void this.openHistoryRecord(record)
  }

  private getSecondaryHistory(): PlaybackHistoryViewItem[] {
    if (this.hideContinueWatching) return []
    const records = this.getHomeHistory()
    return records.length > 1 ? records.slice(1) : []
  }

  private watchSummary(record: PlaybackHistoryViewItem): string {
    if (this.isCompleted(record)) {
      return '已播放完'
    }
    if (record.durationMs <= 0) {
      return '观看至 ' + this.formatTime(record.positionMs)
    }
    const remainMs = Math.max(0, record.durationMs - record.positionMs)
    const minutes = Math.ceil(remainMs / 60000)
    return minutes > 0 ? '剩余 ' + minutes + ' 分钟' : '即将播放完'
  }

  private isCompleted(record: PlaybackHistoryViewItem): boolean {
    return record.completed || (record.durationMs > 0 && record.positionMs / record.durationMs >= 0.995)
  }

  private findLocalRecord(mediaId: string): LocalVideoRecord | null {
    for (let i = 0; i < this.localHistory.length; i++) {
      const record = this.localHistory[i]
      const key = record.fileKey.length > 0 ? record.fileKey : record.fileUri
      if (key === mediaId) return record
    }
    return null
  }

  private buildOwnFolderStatusText(): string {
    if (this.ownFolderScanning) {
      return '正在读取目录'
    }
    if (this.ownFolderScanFailed) {
      return '应用专属目录暂不可访问'
    }
    if (!this.ownFolderScanned) {
      return '应用专属目录'
    }
    return this.ownFolderVideoCount + ' 个视频 · ' + this.ownFolderCount + ' 个文件夹'
  }

  private buildLocalTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base = buildTitleBarOptions('媒体库', this.hdsMaterialLevel)
    base.content = {
      title: { mainTitle: '媒体库' },
      menu: {
        value: [{
          content: {
            icon: $r('sys.symbol.clock'),
            label: '播放历史',
            action: (): void => this.openPlaybackHistoryPage()
          } as HdsNavigationIconOptions
        }]
      }
    }
    return base
  }

  private updateBottomTabOffset(deltaY: number): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    if (this.scroller.currentOffset().yOffset <= 0) {
      requestBottomTabAnimation(false)
      this.bottomTabOffset = 0
      return
    }
    const maxOffset = getBottomTabHideDistance(this.bottomSafeHeight)
    const nextOffset = resolveBottomTabOffsetByDelta(deltaY, this.bottomTabOffset, maxOffset)
    if (Math.abs(nextOffset - this.bottomTabOffset) >= 0.5) {
      this.bottomTabOffset = nextOffset
      requestBottomTabAnimation(resolveBottomTabSnapTarget(nextOffset, maxOffset) > 0)
    }
  }

  private snapBottomTabOffset(): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const maxOffset = getBottomTabHideDistance(this.bottomSafeHeight)
    const targetOffset = resolveBottomTabSnapTarget(this.bottomTabOffset, maxOffset)
    if (Math.abs(targetOffset - this.bottomTabOffset) < 0.5) {
      return
    }
    requestBottomTabAnimation(targetOffset > 0)
    if (targetOffset === 0) {
      this.bottomTabOffset = 0
    }
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    return hours > 0 ? hours + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0') :
      String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
  }
}
