import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { PlaybackQueueCodec } from '../../models/PlaybackQueueItem'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
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
import { EMBY_SOURCE_VERSION_KEY, EmbyServerStore } from '../../store/EmbyServerStore'
import { EmbyServerConfig } from '../../models/EmbyModels'

const logger = new Logger('LocalPage')
const HOME_HISTORY_LIMIT = 6

@Component
export struct LocalPage {
  @Prop @Watch('onActiveChanged') isActive: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onLocalHistoryVersionChanged') localHistoryVersion: number = 0
  @StorageLink(LOCAL_MEDIA_LIBRARY_VERSION_KEY) @Watch('onMediaLibraryChanged') mediaLibraryVersion: number = 0
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') appInForeground: boolean = true
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink(PREFS_KEY_HIDE_LOCAL_MEDIA) hideLocalMedia: boolean = HIDE_MEDIA_CARDS_DEFAULT
  @StorageLink(PREFS_KEY_HIDE_CONTINUE_WATCHING) hideContinueWatching: boolean = HIDE_MEDIA_CARDS_DEFAULT
  @StorageLink(EMBY_SOURCE_VERSION_KEY) @Watch('onEmbySourceChanged') embySourceVersion: number = 0
  @State localHistory: LocalVideoRecord[] = []
  @State ownFolderVideoCount: number = 0
  @State ownFolderCount: number = 0
  @State rootFolderEntries: UserFolderEntry[] = []
  @State rootFolderCoverRenderVersion: number = 0
  @State ownFolderScanned: boolean = false
  @State ownFolderScanning: boolean = false
  @State ownFolderScanFailed: boolean = false
  @State private embyConfig: EmbyServerConfig | null = null
  private scroller: Scroller = new Scroller()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
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
      this.loadLocalHistory()
    }
  }

  onLocalHistoryVersionChanged(): void {
    if (this.appRdbReady && this.isActive) {
      this.loadLocalHistory()
    }
  }

  onMediaLibraryChanged(): void {
    if (this.isActive) {
      this.reloadPageData()
    }
  }

  onEmbySourceChanged(): void {
    if (this.isActive) {
      this.loadEmbyConfig()
    }
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
          .padding({ left: 16, right: 16 })
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
      this.EmbyMediaSection()
      this.LocalMediaSection()

      if (this.localHistory.length > 0 || this.hideContinueWatching) {
        this.ContinueWatchingSection()
      } else {
        this.HomeEmptyState()
      }
    }
    .width('100%')
  }

  @Builder
  private EmbyMediaSection(): void {
    Column({ space: 12 }) {
      Row() {
        Text('Emby')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.embyConfig === null ? '未连接' : this.embyConfig!.serverName)
          .fontSize(13)
          .fontColor(this.embyConfig === null ? $r('app.color.text_secondary') : $r('app.color.status_success'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ right: 8 })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(52)
            .height(52)
            .fill($r('app.color.accent_blue'))
            .opacity(0.12)
          SymbolGlyph($r('sys.symbol.play_round_rectangle_fill'))
            .fontSize(28)
            .fontColor([$r('app.color.accent_blue')])
        }
        .width(56)
        .height(56)

        Column({ space: 4 }) {
          Text(this.embyConfig === null ? '连接 Emby 服务器' : '浏览远程媒体库')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.embyConfig === null ? '登录后可浏览海报、继续播放并同步进度' :
            this.embyConfig!.userName + ' · ' + this.embyConfig!.baseUrl)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .borderRadius(14)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .margin({ top: 24, bottom: 4 })
    .onClick(() => this.openEmby())
  }

  @Builder
  private ContinueWatchingSection(): void {
    Column() {
      Row() {
        Text('继续观看')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.hideContinueWatching ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
          .margin({ right: 12 })
          .onClick(() => this.toggleContinueWatchingVisibility())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
          .padding({ left: 12, top: 10, right: 0, bottom: 10 })
          .onClick(() => this.openPlaybackHistoryPage())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.hideContinueWatching) {
        this.HiddenCardsHint()
      } else if (this.getHomeHistory().length === 1) {
        Row() {
          ForEach(this.getHomeHistory(), (record: LocalVideoRecord) => {
            this.ContinueWatchingCard(record)
          }, (record: LocalVideoRecord) => 'home_continue_' + record.id + '_' + record.coverUri + '_' + record.positionMs)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      } else {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.getHomeHistory(), (record: LocalVideoRecord) => {
              this.ContinueWatchingCard(record)
            }, (record: LocalVideoRecord) => 'home_continue_' + record.id + '_' + record.coverUri + '_' + record.positionMs)
          }
          .padding({ right: 24 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('calc(100% + 16vp)')
        .margin({ right: -16 })
      }
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  private ContinueWatchingCard(record: LocalVideoRecord): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width(176)
          .height(99)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .opacity(record.coverUri.length > 0 ? 1 : 0.82)

        if (record.durationMs > 0) {
          Progress({
            value: Math.min(record.positionMs, record.durationMs),
            total: record.durationMs,
            type: ProgressType.Linear
          })
            .width(152)
            .height(3)
            .color($r('app.color.accent_blue'))
            .backgroundColor('#66000000')
            .margin({ left: 12, bottom: 8 })
        }
      }
      .width(176)
      .height(99)

      Text(record.fileName)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(176)
        .height(40)
      Text(this.watchSummary(record))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(176)
    }
    .width(176)
    .onClick(() => this.openHistoryRecord(record, this.localHistory))
  }

  @Builder
  private HomeEmptyState(): void {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(64)
          .height(64)
          .fill($r('app.color.accent_blue'))
          .opacity(0.12)
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(28)
          .fontColor([$r('app.color.accent_blue')])
      }
      .width(72)
      .height(72)

      Text('还没有播放内容')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text('将视频放入应用专属目录后即可播放，进度会自动保存')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 40, bottom: 36, left: 24, right: 24 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 18 })
  }

  @Builder
  private LocalMediaSection(): void {
    Column({ space: 12 }) {
      Row() {
        Text('本地媒体')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.hideLocalMedia ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
          .margin({ right: 12 })
          .onClick(() => this.toggleLocalMediaVisibility())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
          .padding({ left: 12, top: 10, right: 0, bottom: 10 })
          .onClick(() => this.openFolderPage())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.hideLocalMedia) {
        this.HiddenCardsHint()
      } else if (this.rootFolderEntries.length > 0) {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.rootFolderEntries, (entry: UserFolderEntry) => {
              this.RootFolderEntryGridCard(entry)
            }, (entry: UserFolderEntry) => entry.relativePath + '_' + entry.video.coverUri + '_' +
              this.rootFolderCoverRenderVersion)
          }
          .padding({ right: 24 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('calc(100% + 16vp)')
        .margin({ right: -16 })
      } else {
        this.LocalMediaEmptyCard()
      }

    }
    .width('100%')
    .margin({ top: this.localHistory.length > 0 ? 28 : 24, bottom: 24 })
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
    if (!this.isActive) {
      return
    }
    if (this.appRdbReady) {
      await this.loadLocalHistory()
    }
    await this.loadEmbyConfig()
    if (this.isActive) {
      this.scanOwnFolderIfNeeded(true)
    }
  }

  private async loadEmbyConfig(): Promise<void> {
    this.embyConfig = await EmbyServerStore.load()
  }

  private openEmby(): void {
    router.pushUrl({
      url: this.embyConfig === null ? 'pages/settings/EmbySettingsPage' : 'pages/emby/EmbyLibraryPage'
    })
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

  private async loadLocalHistory(): Promise<void> {
    try {
      this.localHistory = await this.historyStore.getAll()
      this.bindRootEntryHistory()
      this.ensureHistoryExitCovers()
    } catch (err) {
      logger.warn('加载本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.localHistory = []
    }
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

  private buildRootFolderEntryStatus(entry: UserFolderEntry): string {
    if (!entry.isDirectory) {
      return entry.video.durationMs > 0 ? this.watchSummary(entry.video) : '本地视频'
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
    this.openHistoryRecord(entry.video, this.getRootFolderVideoQueue())
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

  private async openHistoryRecord(record: LocalVideoRecord, queue: LocalVideoRecord[]): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        if (!await LocalFilePicker.authorizeExistingUri(context, record.fileUri)) {
          return
        }
      } catch (err) {
        logger.warn('历史视频授权失败: %{public}s', err instanceof Error ? err.message : String(err))
        return
      }
    }
    let queueIndex = 0
    for (let i = 0; i < queue.length; i++) {
      if (queue[i].fileUri === record.fileUri && queue[i].fileSize === record.fileSize) {
        queueIndex = i
        break
      }
    }
    router.pushUrl({
      url: 'pages/player/LocalPlayerPage',
      params: {
        videoUri: record.fileUri,
        videoFileName: record.fileName,
        videoFileSize: record.fileSize,
        historyPositionMs: record.positionMs,
        historyDurationMs: record.durationMs,
        playlistJson: PlaybackQueueCodec.encode(queue),
        queueIndex: queueIndex
      }
    })
  }

  private getHomeHistory(): LocalVideoRecord[] {
    const result: LocalVideoRecord[] = []
    for (let i = 0; i < this.localHistory.length && result.length < HOME_HISTORY_LIMIT; i++) {
      result.push(this.localHistory[i])
    }
    return result
  }

  private watchSummary(record: LocalVideoRecord): string {
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

  private isCompleted(record: LocalVideoRecord): boolean {
    return record.durationMs > 0 && record.positionMs / record.durationMs >= 0.995
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
      title: { mainTitle: '媒体库' }
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
