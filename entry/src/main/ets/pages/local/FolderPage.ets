import { ComponentContent, LengthMetrics, router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import {
  HdsNavigation,
  HdsNavigationIconOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController
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
  getBottomSpacerHeight,
  getTopSpacerHeight,
  buildAdaptiveMaterialEffect,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

const logger = new Logger('FolderPage')
const FOLDER_SEARCH_BAR_HEIGHT: number = 44
const FOLDER_SEARCH_HORIZONTAL_PADDING: number = 12
const FOLDER_SEARCH_BOTTOM_BAR_HEIGHT: number = 64

class FolderSortMenuParams {
  nameLabel: string = ''
  timeLabel: string = ''
  sizeLabel: string = ''
  onSelect: (mode: string) => void = (_mode: string): void => {}
}

@Builder
function FolderSortMenu(params: FolderSortMenuParams): void {
  Menu() {
    MenuItem({ content: params.nameLabel })
      .onClick(() => params.onSelect('name'))
    MenuItem({ content: params.timeLabel })
      .onClick(() => params.onSelect('time'))
    MenuItem({ content: params.sizeLabel })
      .onClick(() => params.onSelect('size'))
  }
  .menuItemDivider({ strokeWidth: LengthMetrics.px(1), color: $r('sys.color.comp_divider') })
}

@Entry
@Component
struct FolderPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') appInForeground: boolean = true
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onHistoryChanged') historyVersion: number = 0
  @StorageLink(LOCAL_MEDIA_LIBRARY_VERSION_KEY) @Watch('onMediaLibraryChanged') mediaLibraryVersion: number = 0
  @State entries: UserFolderEntry[] = []
  @State relativePath: string = ''
  @State searchText: string = ''
  @State searchGlowOpacity: number = 0
  @State searchGlowScale: number = 0.82
  @State searchGlowOffsetX: number = 0
  @State searchGlowOffsetY: number = 0
  @State sortMode: string = 'name'
  @State sortDescending: boolean = false
  @State showCreateFolderSheet: boolean = false
  @State newFolderName: string = ''
  @State newFolderError: string = ''
  @State isLoading: boolean = true
  @State isUnavailable: boolean = false
  @State isCurrentM3u8Package: boolean = false
  @State folderCoverRenderVersion: number = 0
  private scroller: Scroller = new Scroller()
  private searchBarTabsController: HdsTabsController = new HdsTabsController()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private sortMenuTargetId: string = 'folder_sort_menu'
  private isGeneratingFirstFrameCovers: boolean = false
  private pendingFirstFrameCoverGeneration: boolean = false
  private coverGenerationToken: number = 0
  private isPageVisible: boolean = false
  private directoryReloadInProgress: boolean = false

  aboutToAppear(): void {
    this.isPageVisible = true
    const rawParams = router.getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      const path = params['relativePath']
      if (typeof path === 'string') {
        this.relativePath = path
      }
    }
    this.reloadDirectory()
  }

  onPageShow(): void {
    this.isPageVisible = true
    this.reloadDirectory()
  }

  onPageHide(): void {
    this.cancelBackgroundCoverWork()
  }

  aboutToDisappear(): void {
    this.cancelBackgroundCoverWork()
  }

  onRdbReadyChanged(): void {
    if (this.appRdbReady && this.isPageVisible) {
      this.reloadDirectory()
    }
  }

  onHistoryChanged(): void {
    if (this.appRdbReady && this.isPageVisible) {
      this.reloadDirectory()
    }
  }

  onMediaLibraryChanged(): void {
    if (this.isPageVisible) {
      this.reloadDirectory()
    }
  }

  onAppForegroundChanged(): void {
    if (this.appInForeground && this.isPageVisible) {
      this.reloadDirectory()
    }
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          Blank().height(this.getFolderSearchTopSpacerHeight()).width('100%')

          if (this.relativePath.length > 0) {
            Text(this.relativePath)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 6, right: 6, bottom: 4 })
          }

          if (this.getVisibleEntries().length > 0) {
            if (this.relativePath.length === 0 && this.getVisibleVideos().length > 0) {
              this.VideoCoverCarousel()
            }
            if (this.getEntriesBelowCarousel().length > 0) {
              this.FolderEntryCards()
            }
          } else {
            this.EmptyState(this.entries.length > 0)
          }

          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(this.buildFolderTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showCreateFolderSheet, this.CreateFolderSheet, {
      height: 260,
      showClose: false,
      dragBar: true
    })
  }

  @Builder
  private SearchBar(): void {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsSearchField()) {
        this.HdsSearchFieldMaterial()
      } else {
        this.FallbackSearchFieldMaterial()
      }
      this.SearchInputContent()
    }
    .width('100%')
    .height(FOLDER_SEARCH_BAR_HEIGHT)
    .clip(false)
  }

  @Builder
  private SearchBottomBar(): void {
    Row() {
      this.SearchBar()
    }
    .width('100%')
    .height(FOLDER_SEARCH_BOTTOM_BAR_HEIGHT)
    .padding({
      left: FOLDER_SEARCH_HORIZONTAL_PADDING,
      right: FOLDER_SEARCH_HORIZONTAL_PADDING,
      top: 10,
      bottom: 10
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private HdsSearchFieldMaterial(): void {
    HdsTabs({ controller: this.searchBarTabsController }) {
      TabContent()
        .clip(false)
        .backgroundColor(Color.Transparent)
    }
    .width(this.getSearchBarWidth())
    .height(FOLDER_SEARCH_BAR_HEIGHT)
    .clip(false)
    .barWidth(this.getSearchBarWidth())
    .barHeight(FOLDER_SEARCH_BAR_HEIGHT)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .backgroundColor(Color.Transparent)
    .vertical(false)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.getSearchBarWidth(),
        mediumWidth: this.getSearchBarWidth(),
        largeWidth: this.getSearchBarWidth()
      },
      gradientMask: {
        maskColor: Color.Transparent
      },
      barBottomMargin: 0,
      barSideMargin: 0,
      systemMaterialEffect: buildAdaptiveMaterialEffect(this.hdsMaterialLevel),
      miniBar: {
        miniBarBuilder: (): void => {
          this.SearchMaterialMiniBar()
        },
        miniBarStyle: 1
      },
      lightColor: Color.Transparent
    })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private SearchMaterialMiniBar(): void {
    Row()
      .width(this.getSearchBarWidth())
      .height(FOLDER_SEARCH_BAR_HEIGHT)
      .backgroundColor(Color.Transparent)
      .borderRadius(FOLDER_SEARCH_BAR_HEIGHT / 2)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private FallbackSearchFieldMaterial(): void {
    Row()
      .width('100%')
      .height(FOLDER_SEARCH_BAR_HEIGHT)
      .backgroundColor($r('app.color.button_ghost_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_subtle') })
      .borderRadius(FOLDER_SEARCH_BAR_HEIGHT / 2)
  }

  @Builder
  private SearchInputContent(): void {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(this.getSearchGlowBoxSize())
        .height(this.getSearchGlowBoxSize())
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: this.getSearchGlowGradientColors()
        })
        .opacity(this.clampOpacity(this.searchGlowOpacity))
        .scale({ x: this.searchGlowScale, y: this.searchGlowScale })
        .offset({ x: this.searchGlowOffsetX, y: this.searchGlowOffsetY })
        .blendMode(BlendMode.SCREEN)
        .hitTestBehavior(HitTestMode.None)

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .margin({ left: 14, right: 2 })
        TextInput({ placeholder: '搜索当前目录...', text: this.searchText })
          .layoutWeight(1)
          .height(FOLDER_SEARCH_BAR_HEIGHT)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_hint'))
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 0, right: 0 })
          .onChange((value: string) => {
            this.searchText = value
          })
        if (this.searchText.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(38)
          .height(FOLDER_SEARCH_BAR_HEIGHT)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.searchText = ''
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
      .borderRadius(FOLDER_SEARCH_BAR_HEIGHT / 2)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .borderRadius(FOLDER_SEARCH_BAR_HEIGHT / 2)
    .clip(false)
    .onTouch((event: TouchEvent) => {
      this.handleSearchGlowTouch(event)
    })
  }

  @Builder
  private CreateFolderSheet(): void {
    Column() {
      Text('新建文件夹')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 18, bottom: 16 })
      TextInput({ placeholder: '输入文件夹名称', text: this.newFolderName })
        .width('100%')
        .height(46)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_hint'))
        .backgroundColor($r('app.color.button_ghost_bg'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.newFolderName = value
          this.newFolderError = ''
        })
      if (this.newFolderError.length > 0) {
        Text(this.newFolderError)
          .fontSize(12)
          .fontColor($r('app.color.status_error'))
          .margin({ top: 8 })
          .width('100%')
      }
      Row() {
        Text('取消')
          .layoutWeight(1)
          .height(52)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showCreateFolderSheet = false
          })
        Divider()
          .vertical(true)
          .height(30)
          .color($r('app.color.divider_color'))
        Text('创建')
          .layoutWeight(1)
          .height(52)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent_blue'))
          .textAlign(TextAlign.Center)
          .onClick(() => this.createFolder())
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 12 })
  }

  @Builder
  private DirectoryCard(entry: UserFolderEntry): void {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.folder_fill'))
          .fontSize(32)
          .fontColor([$r('app.color.accent_blue')])
      }
      .width(82)
      .height(58)
      .backgroundColor($r('app.color.button_ghost_bg'))
      .borderRadius(10)

      Column() {
        Text(entry.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.folderSummary(entry))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(82)
    .padding({ left: 12, right: 10 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(VerticalAlign.Center)
    .onClick(() => void this.handleDirectoryClick(entry))
  }

  @Builder
  private VideoCoverCarousel(): void {
    Column({ space: 0 }) {
      Swiper() {
        ForEach(this.getVisibleVideos(), (record: LocalVideoRecord) => {
          Stack({ alignContent: Alignment.BottomStart }) {
            Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
              .draggable(false)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .opacity(record.coverUri.length > 0 ? 1 : 0.82)

            Column() {
              Blank().layoutWeight(1)
              Text(record.fileName)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .lineHeight(27)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textShadow({ radius: 3, color: '#99000000', offsetX: 0, offsetY: 1 })
                .width('100%')
            }
            .width('100%')
            .height(104)
            .padding({ left: 20, right: 20, top: 28, bottom: 16 })
            .alignItems(HorizontalAlign.Start)
            .linearGradient({
              direction: GradientDirection.Top,
              colors: [['#C9000000', 0], ['#73000000', 0.56], ['#00000000', 1]]
            })
          }
          .width('100%')
          .height(224)
          .borderRadius(24)
          .clip(true)
          .onClick(() => this.openVideo(record))
        }, (record: LocalVideoRecord) => 'folder_cover_' + record.fileUri + '_' + record.fileSize + '_' +
          record.coverUri + '_' + this.folderCoverRenderVersion)
      }
      .width('100%')
      .height(224)
      .indicator(false)
      .autoPlay(this.getVisibleVideos().length > 1)
      .interval(5000)
      .loop(this.getVisibleVideos().length > 1)
      .duration(420)
      .itemSpace(12)
      .prevMargin(24)
      .nextMargin(24)
    }
    .width('calc(100% + 24vp)')
    .margin({ left: -12, right: -12, top: 4, bottom: 12 })
  }

  @Builder
  private FolderEntryCards(): void {
    Flex({
      wrap: FlexWrap.Wrap,
      space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(16) }
    }) {
      ForEach(this.getEntriesBelowCarousel(), (entry: UserFolderEntry) => {
        this.FolderEntryGridCard(entry)
      }, (entry: UserFolderEntry) => 'folder_entry_card_' + entry.relativePath + '_' + entry.isDirectory + '_' +
        entry.video.coverUri + '_' + this.folderCoverRenderVersion)
    }
    .width('100%')
    .margin({ top: 8, bottom: 12 })
  }

  @Builder
  private FolderEntryGridCard(entry: UserFolderEntry): void {
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
      Text(this.folderEntryCardStatus(entry))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('calc(50% - 6vp)')
    .onClick(() => {
      if (entry.isDirectory) {
        void this.handleDirectoryClick(entry)
      } else {
        this.openVideo(entry.video)
      }
    })
  }

  @Builder
  private VideoCard(record: LocalVideoRecord): void {
    Row({ space: 12 }) {
      Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
        .draggable(false)
        .width(82)
        .height(58)
        .objectFit(ImageFit.Cover)
        .borderRadius(10)
        .opacity(record.coverUri.length > 0 ? 1 : 0.82)

      Column() {
        Text(record.fileName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Blank().layoutWeight(1)
        Row() {
          Text(this.formatFileSize(record.fileSize))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          Text(record.durationMs > 0 ? this.formatTime(record.durationMs) : '本地视频')
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(58)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(106)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openVideo(record))
  }

  @Builder
  private EmptyState(isSearchEmpty: boolean): void {
    Column() {
      SymbolGlyph(this.isLoading ? $r('sys.symbol.arrow_clockwise') :
        this.isAwaitingM3u8Mp4(isSearchEmpty) ? $r('sys.symbol.play_round_rectangle') : $r('sys.symbol.folder'))
        .fontSize(72)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.emptyStateTitle(isSearchEmpty))
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 18 })
      Text(this.emptyStateMessage(isSearchEmpty))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
      Button(this.isAwaitingM3u8Mp4(isSearchEmpty) ? '开始合成' : '刷新')
        .height(42)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.accent_blue'))
        .borderRadius(12)
        .padding({ left: 28, right: 28 })
        .margin({ top: 22 })
        .onClick(() => {
          if (this.isAwaitingM3u8Mp4(isSearchEmpty)) {
            this.openCurrentM3u8Converter()
            return
          }
          this.reloadDirectory()
        })
    }
    .width('100%')
    .height(360)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28 })
  }

  private async reloadDirectory(): Promise<void> {
    if (!this.isPageVisible || this.directoryReloadInProgress) {
      return
    }
    this.directoryReloadInProgress = true
    this.isLoading = true
    this.isUnavailable = false
    this.isCurrentM3u8Package = false
    try {
      const context = getContext(this) as common.UIAbilityContext
      let entries = await UserDownloadFolder.listOwnDirectory(context, this.relativePath)
      if (entries === null) {
        logger.warn('刷新目录读取失败，尝试重新激活应用专属目录')
        const reactivatedPath = await UserDownloadFolder.reactivateOwnFolder(context)
        if (reactivatedPath.length > 0) {
          entries = await UserDownloadFolder.listOwnDirectory(context, this.relativePath)
        }
      }
      if (entries === null) {
        this.entries = []
        if (this.relativePath.length > 0) {
          logger.warn('当前子目录已失效，返回上一级目录: %{public}s', this.relativePath)
          router.back()
          return
        }
        this.isUnavailable = true
        return
      }
      this.isCurrentM3u8Package = await UserDownloadFolder.isM3u8PackageDirectory(context, this.relativePath)
      const history = this.appRdbReady ? await this.historyStore.getAll() : []
      this.bindHistory(entries, history)
      this.entries = entries
      this.ensureRandomFrameCovers()
    } catch (err) {
      this.entries = []
      this.isUnavailable = true
      this.isCurrentM3u8Package = false
      logger.warn('读取文件夹页失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isLoading = false
      this.directoryReloadInProgress = false
    }
  }

  private isAwaitingM3u8Mp4(isSearchEmpty: boolean): boolean {
    return !this.isLoading && !this.isUnavailable && !isSearchEmpty && this.isCurrentM3u8Package
  }

  private emptyStateTitle(isSearchEmpty: boolean): string {
    if (this.isLoading) {
      return '正在读取目录'
    }
    if (this.isUnavailable) {
      return '目录暂不可访问'
    }
    if (isSearchEmpty) {
      return '没有匹配的内容'
    }
    return this.isCurrentM3u8Package ? '尚未合成 MP4' : '此文件夹为空'
  }

  private emptyStateMessage(isSearchEmpty: boolean): string {
    if (this.isUnavailable) {
      return '请点击刷新以重新激活应用专属目录'
    }
    if (isSearchEmpty) {
      return '尝试修改搜索关键词'
    }
    if (this.isCurrentM3u8Package) {
      return '该文件夹包含 m3u8 播放列表和视频分片，合成后的 MP4 视频会显示在这里'
    }
    return '子文件夹和视频会显示在这里'
  }

  private openCurrentM3u8Converter(): void {
    router.pushUrl({
      url: 'pages/tools/M3u8ConverterPage',
      params: { relativePath: this.relativePath }
    })
  }

  private async createFolder(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const error = await UserDownloadFolder.createOwnDirectory(context, this.relativePath, this.newFolderName)
      if (error.length > 0) {
        this.newFolderError = error
        return
      }
      this.showCreateFolderSheet = false
      this.newFolderName = ''
      await this.reloadDirectory()
    } catch (err) {
      logger.warn('新建文件夹操作异常: %{public}s', err instanceof Error ? err.message : String(err))
      this.newFolderError = '创建失败，请稍后重试'
    }
  }

  private showCreateFolder(): void {
    this.newFolderName = ''
    this.newFolderError = ''
    this.showCreateFolderSheet = true
  }

  private shouldUseHdsSearchField(): boolean {
    return deviceInfo.distributionOSApiVersion >= 60100
  }

  private getSearchBarWidth(): number {
    const rawWidth = this.screenWidthVp - FOLDER_SEARCH_HORIZONTAL_PADDING * 2
    return Math.max(220, rawWidth)
  }

  private getFolderSearchTopSpacerHeight(): number {
    return getTopSpacerHeight(this.topSafeHeight) + FOLDER_SEARCH_BOTTOM_BAR_HEIGHT
  }

  private getSearchGlowBoxSize(): number {
    return Math.max(FOLDER_SEARCH_BAR_HEIGHT * 3.8, 160)
  }

  private getSearchGlowGradientColors(): [ResourceColor, number][] {
    return [
      ['#FFFFFFFF', 0.0],
      ['#E6FFFFFF', 0.20],
      ['#80FFFFFF', 0.42],
      ['#26FFFFFF', 0.64],
      ['#08FFFFFF', 0.84],
      ['#00FFFFFF', 0.96],
      ['#00FFFFFF', 1.0]
    ]
  }

  private clampOpacity(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private updateSearchGlowPosition(touch: TouchObject): void {
    this.searchGlowOffsetX = touch.x - this.getSearchBarWidth() / 2
    this.searchGlowOffsetY = touch.y - FOLDER_SEARCH_BAR_HEIGHT / 2
  }

  private handleSearchGlowTouch(event: TouchEvent): void {
    if (!event.touches || event.touches.length === 0) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
          this.searchGlowScale = 1.18
          this.searchGlowOpacity = 0
        })
      }
      return
    }

    const touch = event.touches[0]
    if (event.type === TouchType.Down) {
      this.updateSearchGlowPosition(touch)
      this.searchGlowScale = 0.82
      this.searchGlowOpacity = 0.04
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.searchGlowScale = 1.06
        this.searchGlowOpacity = 0.46
      })
    } else if (event.type === TouchType.Move) {
      this.updateSearchGlowPosition(touch)
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.updateSearchGlowPosition(touch)
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.searchGlowScale = 1.2
        this.searchGlowOpacity = 0
      })
    }
  }

  private buildFolderTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base = buildTitleBarOptions(this.getTitle(), this.hdsMaterialLevel)
    const createFolderIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.folder_badge_plus'),
      label: 'new folder',
      action: () => this.showCreateFolder()
    }
    const refreshFolderIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.arrow_counterclockwise'),
      label: 'refresh folder',
      action: () => this.reloadDirectory()
    }
    const sortMenuIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.more'),
      label: 'sort options',
      componentId: this.sortMenuTargetId,
      action: () => this.showSortMenu()
    }
    base.content = {
      title: { mainTitle: this.getTitle() },
      menu: { value: [{ content: refreshFolderIcon }, { content: createFolderIcon }, { content: sortMenuIcon }] },
      bottomBuilder: {
        builder: (): void => {
          this.SearchBottomBar()
        }
      }
    }
    return base
  }

  private bindHistory(entries: UserFolderEntry[], history: LocalVideoRecord[]): void {
    const historyMap: Map<string, LocalVideoRecord> = new Map()
    for (let i = 0; i < history.length; i++) {
      historyMap.set(this.fileKey(history[i]), history[i])
    }
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].isDirectory) {
        continue
      }
      const matched = historyMap.get(this.fileKey(entries[i].video))
      if (matched !== undefined) {
        // Folder thumbnails must not inherit the history exit-frame cover.
        // Keep only metadata needed to resume playback; the view generates its
        // own first-frame cover in a separate cache entry.
        entries[i].video.durationMs = matched.durationMs
        entries[i].video.positionMs = matched.positionMs
        entries[i].video.lastPlayedAt = matched.lastPlayedAt
      }
    }
  }

  /** Generates stable random-frame covers for direct videos without changing history covers. */
  private async ensureRandomFrameCovers(): Promise<void> {
    if (!this.isPageVisible) {
      return
    }
    if (this.isGeneratingFirstFrameCovers) {
      this.pendingFirstFrameCoverGeneration = true
      this.coverGenerationToken++
      return
    }
    this.isGeneratingFirstFrameCovers = true
    this.pendingFirstFrameCoverGeneration = false
    const generationToken = ++this.coverGenerationToken
    try {
      const entryCount = this.entries.length
      for (let i = 0; i < entryCount; i++) {
        if (!this.isPageVisible || generationToken !== this.coverGenerationToken || i >= this.entries.length) {
          break
        }
        const entry = this.entries[i]
        if (entry.isDirectory || entry.video.fileUri.length === 0) {
          continue
        }
        if (!await LocalFilePicker.ensureReadableUri(entry.video.fileUri)) {
          continue
        }
        const coverUri = await LocalVideoThumbnailStore.getInstance().ensureRandomThumbnail(
          entry.video.fileUri,
          entry.video.fileName,
          entry.video.fileSize
        )
        if (!this.isPageVisible || generationToken !== this.coverGenerationToken ||
          coverUri.length === 0 || i >= this.entries.length ||
          this.entries[i].video.fileUri !== entry.video.fileUri) {
          continue
        }
        if (this.entries[i].video.coverUri !== coverUri) {
          this.entries[i].video.coverUri = coverUri
          this.entries = this.entries.slice()
          this.folderCoverRenderVersion++
        }
      }
    } catch (err) {
      logger.warn('生成目录视频随机帧封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingFirstFrameCovers = false
      if (this.pendingFirstFrameCoverGeneration && this.isPageVisible) {
        this.pendingFirstFrameCoverGeneration = false
        this.ensureRandomFrameCovers()
      }
    }
  }

  private cancelBackgroundCoverWork(): void {
    this.isPageVisible = false
    this.coverGenerationToken++
    this.pendingFirstFrameCoverGeneration = false
  }

  private getVisibleEntries(): UserFolderEntry[] {
    const keyword = this.searchText.trim().toLowerCase()
    const filtered: UserFolderEntry[] = []
    for (let i = 0; i < this.entries.length; i++) {
      if (keyword.length === 0 || this.entries[i].name.toLowerCase().indexOf(keyword) >= 0) {
        filtered.push(this.entries[i])
      }
    }
    filtered.sort((first: UserFolderEntry, second: UserFolderEntry): number => {
      if (first.isDirectory !== second.isDirectory) {
        return first.isDirectory ? -1 : 1
      }
      let result: number = 0
      if (this.sortMode === 'time') {
        result = first.modifiedTime - second.modifiedTime
      } else if (this.sortMode === 'size') {
        result = this.getEntrySize(first) - this.getEntrySize(second)
      } else {
        result = first.name.localeCompare(second.name)
      }
      return this.sortDescending ? -result : result
    })
    return filtered
  }

  private getVisibleVideos(): LocalVideoRecord[] {
    const visible: UserFolderEntry[] = this.getVisibleEntries()
    const videos: LocalVideoRecord[] = []
    for (let i = 0; i < visible.length; i++) {
      if (!visible[i].isDirectory) {
        videos.push(visible[i].video)
      }
    }
    return videos
  }

  /** Keeps carousel videos out of the grid so each media item is rendered only once. */
  private getEntriesBelowCarousel(): UserFolderEntry[] {
    const visible: UserFolderEntry[] = this.getVisibleEntries()
    // Only the app-owned root directory has a carousel. Child directories keep
    // their complete folder/video grid, so videos remain directly visible.
    if (this.relativePath.length > 0) {
      return visible
    }
    const carouselVideos: LocalVideoRecord[] = this.getVisibleVideos()
    const carouselVideoKeys: Map<string, boolean> = new Map()
    const result: UserFolderEntry[] = []
    for (let i = 0; i < carouselVideos.length; i++) {
      carouselVideoKeys.set(this.fileKey(carouselVideos[i]), true)
    }
    for (let i = 0; i < visible.length; i++) {
      if (visible[i].isDirectory || !carouselVideoKeys.has(this.fileKey(visible[i].video))) {
        result.push(visible[i])
      }
    }
    return result
  }

  private folderEntryCardStatus(entry: UserFolderEntry): string {
    if (entry.isDirectory) {
      return this.folderSummary(entry)
    }
    const duration = entry.video.durationMs > 0 ? this.formatTime(entry.video.durationMs) : '本地视频'
    return this.formatFileSize(entry.video.fileSize) + ' · ' + duration
  }

  private getEntrySize(entry: UserFolderEntry): number {
    return entry.isDirectory ? 0 : entry.video.fileSize
  }

  private folderSummary(entry: UserFolderEntry): string {
    const parts: string[] = []
    if (entry.childDirectoryCount > 0) {
      parts.push(entry.childDirectoryCount + ' 个文件夹')
    }
    if (entry.childVideoCount > 0) {
      parts.push(entry.childVideoCount + ' 个视频')
    }
    if (parts.length > 0) {
      return parts.join(' · ')
    }
    return entry.isM3u8Package ? 'm3u8 分片' : '空文件夹'
  }

  private showSortMenu(): void {
    const params = new FolderSortMenuParams()
    params.nameLabel = this.sortMenuLabel('name')
    params.timeLabel = this.sortMenuLabel('time')
    params.sizeLabel = this.sortMenuLabel('size')
    params.onSelect = (mode: string): void => this.selectSortMode(mode)
    try {
      const uiContext = this.getUIContext()
      const content = new ComponentContent<FolderSortMenuParams>(uiContext, wrapBuilder(FolderSortMenu), params)
      uiContext.getPromptAction().openMenu(content, { id: this.sortMenuTargetId }, {
        placement: Placement.BottomRight,
        enableArrow: false
      })
    } catch (err) {
      logger.warn('显示排序菜单失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private selectSortMode(mode: string): void {
    if (this.sortMode === mode) {
      this.sortDescending = !this.sortDescending
      return
    }
    this.sortMode = mode
    this.sortDescending = false
  }

  private sortMenuLabel(mode: string): string {
    const title = mode === 'time' ? '时间' : mode === 'size' ? '大小' : '名称'
    if (this.sortMode !== mode) {
      return title
    }
    return title + (this.sortDescending ? ' ↓' : ' ↑')
  }

  private openChildFolder(relativePath: string): void {
    router.pushUrl({ url: 'pages/local/FolderPage', params: { relativePath: relativePath } })
  }

  private async handleDirectoryClick(entry: UserFolderEntry): Promise<void> {
    if (!entry.isM3u8Package) {
      this.openChildFolder(entry.relativePath)
      return
    }
    if (await UserDownloadFolder.isM3u8PromptSuppressed(entry.relativePath)) {
      this.openChildFolder(entry.relativePath)
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
          action: () => this.openChildFolder(entry.relativePath)
        },
        {
          value: '不再提醒',
          action: () => {
            void UserDownloadFolder.suppressM3u8Prompt(entry.relativePath)
            this.openChildFolder(entry.relativePath)
          }
        }
      ]
    })
  }

  private async openVideo(record: LocalVideoRecord): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      return
    }
    const latest = this.appRdbReady ? await this.resolveLatestRecord(record) : record
    const queue = this.getDirectVideoQueue()
    let index = 0
    for (let i = 0; i < queue.length; i++) {
      if (queue[i].fileUri === latest.fileUri && queue[i].fileSize === latest.fileSize) {
        index = i
        break
      }
    }
    router.pushUrl({
      url: 'pages/player/LocalPlayerPage',
      params: {
        videoUri: latest.fileUri,
        videoFileName: latest.fileName,
        videoFileSize: latest.fileSize,
        historyPositionMs: latest.positionMs,
        historyDurationMs: latest.durationMs,
        playlistJson: PlaybackQueueCodec.encode(queue),
        queueIndex: index
      }
    })
  }

  private getDirectVideoQueue(): LocalVideoRecord[] {
    const queue: LocalVideoRecord[] = []
    for (let i = 0; i < this.entries.length; i++) {
      if (!this.entries[i].isDirectory) {
        queue.push(this.entries[i].video)
      }
    }
    return queue
  }

  private async resolveLatestRecord(record: LocalVideoRecord): Promise<LocalVideoRecord> {
    const matched = await this.historyStore.getByFileKey(this.fileKey(record))
    return matched === null ? record : matched
  }

  private getTitle(): string {
    if (this.relativePath.length === 0) {
      return '文件夹'
    }
    const slashIndex = this.relativePath.lastIndexOf('/')
    return slashIndex >= 0 ? this.relativePath.substring(slashIndex + 1) : this.relativePath
  }

  private fileKey(record: LocalVideoRecord): string {
    return record.fileKey.length > 0 ? record.fileKey :
      record.fileUri + '|' + record.fileSize + '|' + record.fileName
  }

  private formatFileSize(size: number): string {
    if (size <= 0) {
      return '未知大小'
    }
    const mb = size / 1024 / 1024
    return mb < 1024 ? mb.toFixed(mb >= 100 ? 0 : 1) + ' MB' :
      (mb / 1024).toFixed(mb >= 102400 ? 0 : 1) + ' GB'
  }

  private formatTime(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const remainSeconds = seconds % 60
    return hours > 0 ? hours + ':' + String(minutes).padStart(2, '0') + ':' + String(remainSeconds).padStart(2, '0') :
      String(minutes).padStart(2, '0') + ':' + String(remainSeconds).padStart(2, '0')
  }
}
