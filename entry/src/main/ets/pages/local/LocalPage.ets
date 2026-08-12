import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitle,
  TitleBarContentOptions
} from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { PlaybackQueueCodec } from '../../models/PlaybackQueueItem'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LOCAL_VIDEO_HISTORY_VERSION_KEY } from '../../store/LocalVideoHistoryChangeSignal'
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

const logger = new Logger('LocalPage')
@Component
export struct LocalPage {
  @Prop @Watch('onActiveChanged') isActive: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onLocalHistoryVersionChanged') localHistoryVersion: number = 0
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @State localHistory: LocalVideoRecord[] = []
  @State ownFolderVideos: LocalVideoRecord[] = []
  @State ownFolderEntries: UserFolderEntry[] = []
  @State currentOwnFolderPath: string = ''
  @State ownFolderScanned: boolean = false
  @State ownFolderScanFailed: boolean = false
  @State ownFolderScanning: boolean = false
  @State ownFolderCoverRenderVersion: number = 0
  @State selectedLocalTabIndex: number = 0
  @State showDeleteConfirm: boolean = false
  @State pendingDeleteId: number = -1
  @State pendingDeleteFileName: string = ''
  @State isEditMode: boolean = false
  @State selectedIds: number[] = []
  @State showBatchDeleteDialog: boolean = false
  private scroller: Scroller = new Scroller()
  private localVideoHistoryStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private hasScannedOwnDownloadFolder: boolean = false
  private isGeneratingCovers: boolean = false
  private isGeneratingOwnFolderCovers: boolean = false
  private pendingOwnFolderCoverGeneration: boolean = false
  private pendingOwnFolderRescan: boolean = false

  aboutToAppear(): void {
    if (this.appRdbReady) {
      this.loadLocalHistory()
    } else {
      logger.info('本地播放记录等待RDB初始化')
    }
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded()
    }
  }

  onBackPress(): boolean {
    if (this.isEditMode) {
      this.exitEditMode()
      return true
    }
    return false
  }

  onPageShow(): void {
    if (this.appRdbReady) {
      this.loadLocalHistory()
    } else {
      logger.info('本地播放记录等待RDB初始化')
    }
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded(true)
    }
  }

  onRdbReadyChanged(): void {
    logger.info('Local page RDB ready changed: %{public}s', String(this.appRdbReady))
    if (!this.appRdbReady) {
      return
    }
    this.refreshLocalHistoryBindings()
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded(true)
    }
  }

  onLocalHistoryVersionChanged(): void {
    if (this.appRdbReady) {
      this.refreshLocalHistoryBindings()
    }
  }

  onActiveChanged(): void {
    logger.info('Local page active changed: %{public}s', String(this.isActive))
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded(true)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')

            this.LibraryEntrySection()

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .clip(false)
        .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
          this.updateBottomTabOffset(yOffset)
        })
        .onScrollStop(() => {
          this.snapBottomTabOffset()
        })
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
      .bindSheet($$this.showDeleteConfirm, this.DeleteConfirmSheet, {
        height: 230,
        showClose: false,
        dragBar: false
      })
      .bindSheet($$this.showBatchDeleteDialog, this.BatchDeleteSheet, {
        height: 220,
        showClose: false,
        dragBar: false
      })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.home_bg_top'), 0],
        [$r('app.color.page_background'), 0.35],
        [$r('app.color.page_background'), 1]
      ]
    })
  }

  private updateBottomTabOffset(deltaY: number): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const currentOffset = this.scroller.currentOffset()
    if (currentOffset.yOffset <= 0) {
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
    const shouldHide = targetOffset > 0
    requestBottomTabAnimation(shouldHide)
    if (!shouldHide) {
      this.bottomTabOffset = 0
    }
  }

  @Builder
  private LocalHeroSection(): void {
    Column() {
      if (this.localHistory.length > 0) {
        Row() {
          Column() {
            Text('继续播放')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(this.localHistory[0].fileName)
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
            Text(this.buildProgressText(this.localHistory[0]) + ' · ' + this.buildProgressPercentText(this.localHistory[0]))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Stack() {
            if (this.localHistory[0].coverUri.length > 0) {
              Image(this.localHistory[0].coverUri)
                .draggable(false)
                .width(96)
                .height(60)
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
              Rect()
                .width(96)
                .height(60)
                .radius(10)
                .fill('#33000000')
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(24)
                .fontColor([$r('app.color.text_on_primary')])
            } else {
              Circle()
                .width(54)
                .height(54)
                .fill($r('app.color.accent_blue'))
                .opacity(0.18)
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(26)
                .fontColor([$r('app.color.accent_blue')])
            }
          }
          .width(96)
          .height(60)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.localHistory[0].durationMs > 0) {
          Progress({
            value: Math.min(this.localHistory[0].positionMs, this.localHistory[0].durationMs),
            total: this.localHistory[0].durationMs,
            type: ProgressType.Linear
          })
            .height(4)
            .color($r('app.color.accent_blue'))
            .backgroundColor($r('app.color.button_ghost_bg'))
            .margin({ top: 16 })
        }

        Button('继续播放')
          .width('100%')
          .height(40)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(12)
          .margin({ top: 16 })
          .onClick(() => {
            this.openHistoryRecord(this.localHistory[0], this.localHistory)
          })
      } else {
        Stack() {
          Circle()
            .width(64)
            .height(64)
            .fill($r('app.color.accent_blue'))
            .opacity(0.14)
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(36)
            .fontColor([$r('app.color.accent_blue')])
        }
        .width(72)
        .height(72)
        .margin({ bottom: 12 })

        Text('本地播放')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('选择本地视频播放，自动保存观看进度和封面')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(20)
          .margin({ top: 8, bottom: 16 })

      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 22, bottom: 22 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.localHistory.length > 0) {
        this.openHistoryRecord(this.localHistory[0], this.localHistory)
      }
    })
  }

  @Builder
  private OwnFolderSection(): void {
    Column() {
      this.OwnFolderPathBar()
      if (this.ownFolderEntries.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.ownFolderEntries, (entry: UserFolderEntry) => {
            if (entry.isDirectory) {
              this.OwnFolderDirectoryCard(entry)
            } else {
              this.OwnFolderVideoCard(entry.video, this.getCurrentDirectoryVideos())
            }
          }, (entry: UserFolderEntry) => 'own_entry_' + entry.relativePath + '_' + entry.isDirectory + '_' +
            entry.video.coverUri + '_' + this.ownFolderCoverRenderVersion)
        }
        .width('100%')
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.folder_badge_plus'))
            .fontSize(92)
            .fontColor([$r('app.color.accent_blue')])
            .margin({ bottom: 22 })

          Text(this.buildOwnFolderEmptyTitle())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          Text(this.buildOwnFolderEmptySubtitle())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .lineHeight(24)
            .margin({ top: 18 })

          Button('刷新专属目录')
            .height(42)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(12)
            .margin({ top: 22 })
            .padding({ left: 24, right: 24 })
            .onClick(() => this.rescanOwnDownloadFolder())

          Button('打开视频')
            .height(38)
            .fontSize(14)
            .fontColor($r('app.color.accent_blue'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.accent_blue') })
            .borderRadius(12)
            .margin({ top: 10 })
            .padding({ left: 24, right: 24 })
            .onClick(() => this.pickAndOpenVideo())
        }
        .width('100%')
        .height(420)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 28, right: 28 })
      }
    }
    .width('100%')
  }

  @Builder
  private OwnFolderVideoCard(record: LocalVideoRecord, queue: LocalVideoRecord[]): void {
    Row({ space: 12 }) {
      Stack() {
        Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width(82)
          .height(58)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .opacity(record.coverUri.length > 0 ? 1 : 0.82)
      }
      .width(82)
      .height(58)

      Column() {
        Text(record.fileName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Blank()
          .layoutWeight(1)
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
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(58)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
        .margin({ top: 21 })
    }
    .width('100%')
    .height(106)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.openOwnFolderVideo(record, queue)
    })
  }

  @Builder
  private RecentSection(): void {
    Column() {
      if (this.localHistory.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(92)
            .fontColor([$r('app.color.accent_blue')])
            .margin({ bottom: 22 })

          Text('还没有播放记录')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          Text('播放过的视频会显示在这里')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .lineHeight(24)
            .margin({ top: 18 })
          Text('本地视频的播放进度和封面\n会在播放后自动保存')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .textAlign(TextAlign.Center)
            .lineHeight(21)
            .margin({ top: 14 })
          Button('打开视频')
            .height(42)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(12)
            .margin({ top: 22 })
            .padding({ left: 24, right: 24 })
            .onClick(() => this.pickAndOpenVideo())
        }
        .width('100%')
        .height(420)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 28, right: 28 })
      } else {
        Column({ space: 8 }) {
          ForEach(this.localHistory, (record: LocalVideoRecord) => {
            this.HistoryCard(record, this.localHistory)
          }, (record: LocalVideoRecord) => 'local_history_' + record.id + '_' + record.fileKey)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private HistoryCard(record: LocalVideoRecord, queue: LocalVideoRecord[]): void {
    Row({ space: 12 }) {
      Stack() {
        if (record.coverUri.length > 0) {
          Image(record.coverUri)
            .draggable(false)
            .width(82)
            .height(58)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
        } else {
          Image($r('app.media.ic_placeholder'))
            .draggable(false)
            .width(82)
            .height(58)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(0.82)
        }
      }
      .width(82)
      .height(58)

      Column() {
        Row() {
           Text(record.fileName)
            .layoutWeight(1)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (!this.isEditMode) {
            SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
              .fontSize(18)
              .fontColor([$r('sys.color.icon_secondary')])
              .padding({ left: 8, right: 4, top: 4, bottom: 4 })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.askDeleteRecord(record)
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row() {
          Text(this.buildProgressText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.buildProgressPercentText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 4 })

        if (record.durationMs > 0) {
          Progress({
            value: Math.min(record.positionMs, record.durationMs),
            total: record.durationMs,
            type: ProgressType.Linear
          })
            .height(3)
            .color($r('app.color.accent_blue'))
            .backgroundColor($r('app.color.button_ghost_bg'))
            .margin({ top: 8 })
        }

        Row() {
          Text('上次播放 ' + this.formatLastPlayedAt(record.lastPlayedAt))
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Clip })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .height(82)
      .alignItems(HorizontalAlign.Start)

      if (this.isEditMode) {
        SymbolGlyph(this.selectedIds.indexOf(record.id) >= 0 ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'))
          .fontSize(24)
          .fontColor([this.selectedIds.indexOf(record.id) >= 0 ? $r('sys.color.font_emphasize') : $r('app.color.text_secondary')])
          .margin({ left: 8 })
          .onClick(() => {
            this.toggleSelect(record.id)
          })
      }
    }
    .width('100%')
    .height(106)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      if (this.isEditMode) {
        this.toggleSelect(record.id)
      } else {
              this.openHistoryRecord(record, queue)
      }
    })
  }

  @Builder
  private TagPill(text: string, highlighted: boolean): void {
    Text(text)
      .fontSize(11)
      .fontColor(highlighted ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(8)
      .backgroundColor(highlighted ? $r('app.color.button_ghost_bg') : Color.Transparent)
  }

  @Builder
  private DeleteConfirmSheet(): void {
    Column() {
      Text('删除这条播放记录？')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 28, bottom: 20 })
      Text(this.pendingDeleteFileName.length > 0 ? this.pendingDeleteFileName : '不会删除本地视频文件。')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(26)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ bottom: 26 })

      Row() {
        Text('取消')
          .layoutWeight(1)
          .height(52)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showDeleteConfirm = false
            this.pendingDeleteId = -1
            this.pendingDeleteFileName = ''
          })

        Divider()
          .vertical(true)
          .height(34)
          .color($r('app.color.divider_color'))
          .margin({ left: 4, right: 4 })

        Text('删除')
          .layoutWeight(1)
          .height(52)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.status_error'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            const id = this.pendingDeleteId
            this.showDeleteConfirm = false
            this.pendingDeleteId = -1
            this.pendingDeleteFileName = ''
            this.deleteHistoryRecord(id)
          })
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 14 })
  }

  @Builder
  private BatchDeleteSheet(): void {
    Column() {
      Text('删除' + String(this.selectedIds.length) + '条播放记录？')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 28, bottom: 20 })
      Text('这不会删除本地视频文件。')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(26)
        .width('100%')
        .margin({ bottom: 26 })

      Row() {
        Text('取消')
          .layoutWeight(1)
          .height(52)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showBatchDeleteDialog = false
          })

        Divider()
          .vertical(true)
          .height(34)
          .color($r('app.color.divider_color'))
          .margin({ left: 4, right: 4 })

        Text('删除')
          .layoutWeight(1)
          .height(52)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.status_error'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.confirmBatchDelete()
          })
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 14 })
  }

  private async pickAndOpenVideo(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const result = await LocalFilePicker.pickVideoFile(context)
      if (result === null) {
        return
      }
      router.pushUrl({
        url: 'pages/player/LocalPlayerPage',
        params: {
          videoUri: result.uri,
          videoFileName: result.fileName,
          videoFileSize: result.fileSize,
          historyPositionMs: 0,
          playlistJson: JSON.stringify([{ uri: result.uri, name: result.fileName, size: result.fileSize, positionMs: 0 }]),
          queueIndex: 0
        }
      })
    } catch (err) {
      logger.warn('打开本地视频失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  @Builder
  private LibraryEntrySection(): void {
    Column({ space: 12 }) {
      this.LocalHeroSection()

      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(28)
            .fontColor([$r('app.color.accent_blue')])
        }
        .width(52)
        .height(52)
        .borderRadius(16)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Column() {
          Text('文件夹')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('应用专属目录 · ' + this.buildOwnFolderStatusText())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(17)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      .width('100%')
      .height(86)
      .padding({ left: 16, right: 14 })
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.openFolderPage())

      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(27)
            .fontColor([$r('app.color.accent_blue')])
        }
        .width(52)
        .height(52)
        .borderRadius(16)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Column() {
          Text('继续观看')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.localHistory.length > 0 ? this.localHistory[0].fileName : '暂无播放记录')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(17)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      .width('100%')
      .height(86)
      .padding({ left: 16, right: 14 })
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.openContinueWatchingPage())
    }
    .width('100%')
  }

  private openFolderPage(): void {
    router.pushUrl({
      url: 'pages/local/FolderPage',
      params: { relativePath: '' }
    })
  }

  private openContinueWatchingPage(): void {
    router.pushUrl({
      url: 'pages/local/ContinueWatchingPage'
    })
  }

  @Builder
  private OwnFolderPathBar(): void {
    Row({ space: 8 }) {
      if (this.currentOwnFolderPath.length > 0) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.accent_blue')])
          .width(32)
          .height(32)
          .onClick(() => this.openParentOwnFolder())
      }
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(20)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.getCurrentOwnFolderTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.ownFolderScanning ? '读取中' : String(this.ownFolderEntries.length) + ' 项')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(42)
    .padding({ left: 6, right: 6 })
  }

  @Builder
  private OwnFolderDirectoryCard(entry: UserFolderEntry): void {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.folder_fill'))
          .fontSize(32)
          .fontColor([$r('app.color.accent_blue')])
      }
      .width(82)
      .height(58)
      .backgroundColor($r('app.color.button_ghost_bg'))
      .borderRadius(10)
      .alignContent(Alignment.Center)
      Column() {
        Text(entry.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text('文件夹')
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
    .onClick(() => this.openOwnFolder(entry.relativePath))
  }

  private async openOwnFolderVideo(record: LocalVideoRecord, queue: LocalVideoRecord[]): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      logger.warn('本地目录视频不可读: %{public}s', record.fileName)
      return
    }
    const latestRecord = await this.resolveLatestOwnFolderRecord(record)
    this.pushVideoPlayer(latestRecord, queue)
  }

  private async openHistoryRecord(record: LocalVideoRecord, queue: LocalVideoRecord[]): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        const authorized = await LocalFilePicker.authorizeExistingUri(context, record.fileUri)
        if (!authorized) {
          logger.warn('历史视频授权失败: %{public}s', record.fileName)
          return
        }
      } catch (err) {
        logger.warn('历史视频授权异常: %{public}s', err instanceof Error ? err.message : String(err))
        return
      }
    }
    this.pushVideoPlayer(record, queue)
  }

  private pushVideoPlayer(record: LocalVideoRecord, queue: LocalVideoRecord[]): void {
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

  private async loadLocalHistory(): Promise<void> {
    if (!this.appRdbReady) {
      logger.info('跳过加载本地播放记录，RDB尚未初始化')
      return
    }
    try {
      this.localHistory = await this.localVideoHistoryStore.getAll()
      this.ensureHistoryExitCovers()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('加载本地播放记录失败: %{public}s', msg)
      if (msg.indexOf('RdbStore not initialized') < 0) {
        this.localHistory = []
      }
    }
  }

  private async refreshLocalHistoryBindings(): Promise<void> {
    await this.loadLocalHistory()
    if (this.ownFolderVideos.length > 0) {
      this.ownFolderVideos = this.mergeOwnFolderHistoryBindings(this.ownFolderVideos, this.localHistory)
      this.ensureOwnFolderCovers()
    }
  }

  /**
   * History keeps the frame at the last saved exit position. This also repairs
   * records created before exit-frame capture was introduced, without ever
   * writing a folder's first-frame thumbnail into the history database.
   */
  private async ensureHistoryExitCovers(): Promise<void> {
    if (this.isGeneratingCovers || this.localHistory.length === 0) {
      return
    }
    this.isGeneratingCovers = true
    try {
      const maxGenerateCount = this.localHistory.length
      for (let i = 0; i < maxGenerateCount; i++) {
        const record = this.localHistory[i]
        if (record.fileUri.length === 0 || record.fileKey.length === 0) {
          continue
        }
        if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
          logger.warn('跳过本地视频封面生成，文件暂不可读: %{public}s', record.fileName)
          continue
        }
        logger.info('开始生成本地视频封面: %{public}s', record.fileName)
        const coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(record.fileUri, record.fileName, record.fileSize, record.positionMs)
        if (coverUri.length > 0 && coverUri !== record.coverUri) {
          await this.localVideoHistoryStore.updateCoverUri(record.fileKey, coverUri)
          this.localHistory[i].coverUri = coverUri
          this.localHistory = this.localHistory.slice()
          logger.info('本地视频封面已更新: %{public}s', record.fileName)
        }
      }
    } catch (err) {
      logger.warn('生成本地视频封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingCovers = false
    }
  }

  private async scanOwnDownloadFolderIfNeeded(force: boolean = false): Promise<void> {
    if (this.hasScannedOwnDownloadFolder && !force) {
      return
    }
    if (this.ownFolderScanning) {
      this.pendingOwnFolderRescan = this.pendingOwnFolderRescan || force
      return
    }
    this.ownFolderScanning = true
    this.ownFolderScanFailed = false
    try {
      logger.info('开始读取用户Download包名目录')
      const context = getContext(this) as common.UIAbilityContext
      const records = await UserDownloadFolder.scanOwnVideoFiles(context)
      if (records === null) {
        this.ownFolderScanFailed = true
        this.ownFolderScanned = true
        logger.warn('读取用户Download包名目录失败，目录暂不可访问')
        return
      }
      this.hasScannedOwnDownloadFolder = true
      const historyRecords = await this.loadLocalHistoryForMerge()
      this.ownFolderVideos = this.mergeOwnFolderHistoryBindings(records, historyRecords)
      this.ownFolderScanned = true
      this.ownFolderScanFailed = false
      logger.info('读取用户Download包名目录完成: %{public}d', records.length)
      await this.reloadCurrentOwnFolder()
      this.ensureOwnFolderCovers()
    } catch (err) {
      this.ownFolderScanFailed = true
      this.ownFolderScanned = true
      logger.warn('读取用户Download包名目录失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.ownFolderScanning = false
      if (this.pendingOwnFolderRescan) {
        this.pendingOwnFolderRescan = false
        this.scanOwnDownloadFolderIfNeeded(true)
      }
    }
  }

  private rescanOwnDownloadFolder(): void {
    this.hasScannedOwnDownloadFolder = false
    this.scanOwnDownloadFolderIfNeeded()
  }

  private async reloadCurrentOwnFolder(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const entries = await UserDownloadFolder.listOwnDirectory(context, this.currentOwnFolderPath)
      if (entries === null) {
        this.ownFolderEntries = []
        return
      }
      const historyRecords = await this.loadLocalHistoryForMerge()
      const directVideos: LocalVideoRecord[] = []
      for (let i = 0; i < entries.length; i++) {
        if (!entries[i].isDirectory) {
          directVideos.push(entries[i].video)
        }
      }
      const mergedVideos = this.mergeOwnFolderHistoryBindings(directVideos, historyRecords)
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].isDirectory) {
          continue
        }
        for (let j = 0; j < mergedVideos.length; j++) {
          if (mergedVideos[j].fileUri === entries[i].video.fileUri && mergedVideos[j].fileSize === entries[i].video.fileSize) {
            entries[i].video = mergedVideos[j]
            break
          }
        }
      }
      this.ownFolderEntries = entries
    } catch (err) {
      logger.warn('刷新应用专属目录视图失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.ownFolderEntries = []
    }
  }

  private openOwnFolder(relativePath: string): void {
    this.currentOwnFolderPath = relativePath
    this.reloadCurrentOwnFolder()
  }

  private openParentOwnFolder(): void {
    const slashIndex = this.currentOwnFolderPath.lastIndexOf('/')
    this.currentOwnFolderPath = slashIndex >= 0 ? this.currentOwnFolderPath.substring(0, slashIndex) : ''
    this.reloadCurrentOwnFolder()
  }

  private getCurrentOwnFolderTitle(): string {
    if (this.currentOwnFolderPath.length === 0) {
      return '应用专属目录'
    }
    const slashIndex = this.currentOwnFolderPath.lastIndexOf('/')
    return slashIndex >= 0 ? this.currentOwnFolderPath.substring(slashIndex + 1) : this.currentOwnFolderPath
  }

  private getCurrentDirectoryVideos(): LocalVideoRecord[] {
    const records: LocalVideoRecord[] = []
    for (let i = 0; i < this.ownFolderEntries.length; i++) {
      if (!this.ownFolderEntries[i].isDirectory) {
        records.push(this.ownFolderEntries[i].video)
      }
    }
    return records
  }

  private async ensureOwnFolderCovers(): Promise<void> {
    if (this.isGeneratingOwnFolderCovers || this.ownFolderVideos.length === 0) {
      if (this.isGeneratingOwnFolderCovers) {
        this.pendingOwnFolderCoverGeneration = true
      }
      return
    }
    this.isGeneratingOwnFolderCovers = true
    this.pendingOwnFolderCoverGeneration = false
    try {
      const maxGenerateCount = this.ownFolderVideos.length
      for (let i = 0; i < maxGenerateCount; i++) {
        if (i >= this.ownFolderVideos.length) {
          break
        }
        const record = this.ownFolderVideos[i]
        if (record.fileUri.length === 0) {
          continue
        }
        if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
          logger.warn('跳过本地目录视频封面生成，文件暂不可读: %{public}s', record.fileName)
          continue
        }
        logger.info('开始生成本地目录视频封面: %{public}s', record.fileName)
        const coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(record.fileUri, record.fileName, record.fileSize,
            LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS)
        if (coverUri.length === 0) {
          continue
        }
        const currentIndex = this.findOwnFolderVideoIndex(record.fileUri, record.fileSize)
        if (currentIndex < 0) {
          continue
        }
        this.ownFolderVideos[currentIndex].coverUri = coverUri
        this.ownFolderVideos = this.ownFolderVideos.slice()
        this.ownFolderCoverRenderVersion++
        logger.info('本地目录视频首帧封面已更新: %{public}s', record.fileName)
      }
    } catch (err) {
      logger.warn('生成本地目录视频封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingOwnFolderCovers = false
      if (this.pendingOwnFolderCoverGeneration) {
        this.ensureOwnFolderCovers()
      }
    }
  }

  private findOwnFolderVideoIndex(fileUri: string, fileSize: number): number {
    for (let i = 0; i < this.ownFolderVideos.length; i++) {
      const record = this.ownFolderVideos[i]
      if (record.fileUri === fileUri && record.fileSize === fileSize) {
        return i
      }
    }
    return -1
  }

  private async loadLocalHistoryForMerge(): Promise<LocalVideoRecord[]> {
    if (!this.appRdbReady) {
      logger.info('本地目录暂不合并历史，RDB尚未初始化')
      return []
    }
    try {
      return await this.localVideoHistoryStore.getAll()
    } catch (err) {
      logger.warn('读取本地历史用于目录合并失败: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  private mergeOwnFolderHistoryBindings(records: LocalVideoRecord[], historyRecords: LocalVideoRecord[]): LocalVideoRecord[] {
    const historyMap: Map<string, LocalVideoRecord> = new Map()
    for (let i = 0; i < historyRecords.length; i++) {
      historyMap.set(this.buildLocalFileKey(historyRecords[i]), historyRecords[i])
    }
    for (let j = 0; j < records.length; j++) {
      const historyRecord = historyMap.get(this.buildLocalFileKey(records[j]))
      if (historyRecord === undefined) {
        continue
      }
      records[j].fileKey = historyRecord.fileKey
      records[j].coverUri = historyRecord.coverUri
      records[j].durationMs = historyRecord.durationMs
      records[j].positionMs = historyRecord.positionMs
    }
    return records
  }

  private async resolveLatestOwnFolderRecord(record: LocalVideoRecord): Promise<LocalVideoRecord> {
    const historyRecord = await this.localVideoHistoryStore.getByFileKey(this.buildLocalFileKey(record))
    if (historyRecord === null) {
      return record
    }
    const merged = new LocalVideoRecord()
    merged.fileKey = historyRecord.fileKey
    merged.fileUri = record.fileUri
    merged.fileName = record.fileName
    merged.fileSize = record.fileSize
    merged.coverUri = historyRecord.coverUri
    merged.durationMs = historyRecord.durationMs
    merged.positionMs = historyRecord.positionMs
    merged.lastPlayedAt = historyRecord.lastPlayedAt
    logger.info('打开本地目录视频使用最新历史: name=%{public}s position=%{public}d',
      merged.fileName, merged.positionMs)
    return merged
  }

  private buildLocalFileKey(record: LocalVideoRecord): string {
    if (record.fileKey.length > 0) {
      return record.fileKey
    }
    return record.fileUri + '|' + record.fileSize + '|' + record.fileName
  }

  private async deleteHistoryRecord(id: number): Promise<void> {
    if (id < 0) {
      return
    }
    try {
      const record = this.findHistoryRecordById(id)
      if (record !== null) {
        await LocalFilePicker.revokeUriPermission(record.fileUri)
      }
      await this.localVideoHistoryStore.deleteById(id)
      await this.loadLocalHistory()
    } catch (err) {
      logger.warn('删除本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private askDeleteRecord(record: LocalVideoRecord): void {
    this.pendingDeleteId = record.id
    this.pendingDeleteFileName = record.fileName
    this.showDeleteConfirm = true
  }

  private toggleSelect(id: number): void {
    const idx: number = this.selectedIds.indexOf(id)
    if (idx >= 0) {
      const newIds: number[] = []
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (this.selectedIds[i] !== id) {
          newIds.push(this.selectedIds[i])
        }
      }
      this.selectedIds = newIds
    } else {
      this.selectedIds = [...this.selectedIds, id]
    }
  }

  private handleSelectAllOrExit(): void {
    if (this.selectedIds.length === this.localHistory.length) {
      this.selectedIds = []
      return
    }
    const allIds: number[] = []
    for (let i = 0; i < this.localHistory.length; i++) {
      allIds.push(this.localHistory[i].id)
    }
    this.selectedIds = allIds
  }

  private exitEditMode(): void {
    this.isEditMode = false
    this.selectedIds = []
  }

  private async confirmBatchDelete(): Promise<void> {
    this.showBatchDeleteDialog = false
    const idsToDelete: number[] = [...this.selectedIds]
    if (idsToDelete.length === 0) {
      return
    }
    const shouldExit: boolean = idsToDelete.length >= this.localHistory.length
    const removedRecords: LocalVideoRecord[] = []
    for (let i = 0; i < idsToDelete.length; i++) {
      const record = this.findHistoryRecordById(idsToDelete[i])
      if (record !== null) {
        removedRecords.push(record)
      }
    }
    const nextHistory: LocalVideoRecord[] = []
    for (let i = 0; i < this.localHistory.length; i++) {
      if (idsToDelete.indexOf(this.localHistory[i].id) < 0) {
        nextHistory.push(this.localHistory[i])
      }
    }
    this.localHistory = nextHistory
    this.selectedIds = []
    if (shouldExit) {
      this.exitEditMode()
    }
    try {
      for (let i = 0; i < removedRecords.length; i++) {
        await LocalFilePicker.revokeUriPermission(removedRecords[i].fileUri)
      }
      await this.localVideoHistoryStore.deleteByIds(idsToDelete)
    } catch (err) {
      logger.warn('批量删除本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      await this.loadLocalHistory()
    }
  }

  private findHistoryRecordById(id: number): LocalVideoRecord | null {
    for (let i = 0; i < this.localHistory.length; i++) {
      if (this.localHistory[i].id === id) {
        return this.localHistory[i]
      }
    }
    return null
  }

  private buildRefreshLocalDirectoryIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.arrow_counterclockwise'),
      label: 'refresh app folder',
      action: () => {
        this.rescanOwnDownloadFolder()
      }
    }
  }

  private buildOpenVideoIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.folder_badge_plus'),
      label: 'open local video',
      action: () => this.pickAndOpenVideo()
    }
  }

  private buildLocalTitle(): HdsNavigationTitle {
    if (this.isEditMode) {
      return {
        mainTitle: '已选择' + String(this.selectedIds.length) + '项',
        subTitle: ''
      }
    }
    return {
        mainTitle: '媒体库'
    }
  }

  private buildLocalMenu(): HdsNavigationMenuContentOptions {
    if (this.selectedLocalTabIndex === 1 && this.localHistory.length > 0) {
      if (this.isEditMode) {
        const cancelIcon: HdsNavigationIconOptions = {
          icon: $r('sys.symbol.xmark'),
          label: 'cancel',
          action: () => {
            this.exitEditMode()
          }
        }
        const trashIcon: HdsNavigationIconOptions = {
          icon: $r('sys.symbol.trash'),
          label: 'delete',
          action: () => {
            if (this.selectedIds.length > 0) {
              this.showBatchDeleteDialog = true
            }
          }
        }
        const selectAllIcon: HdsNavigationIconOptions = {
          icon: $r('sys.symbol.checkmark_square_on_square'),
          label: 'selectAll',
          action: () => {
            this.handleSelectAllOrExit()
          }
        }
        return {
          value: [{ content: cancelIcon }, { content: trashIcon }, { content: selectAllIcon }]
        }
      }
      const editIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.square_and_pencil'),
        label: 'edit',
        action: () => {
          this.isEditMode = true
        }
      }
      return {
        value: [{ content: this.buildOpenVideoIcon() }, { content: editIcon }, { content: this.buildRefreshLocalDirectoryIcon() }]
      }
    }
    return {
      value: [{ content: this.buildOpenVideoIcon() }, { content: this.buildRefreshLocalDirectoryIcon() }]
    }
  }

  private buildLocalTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildLocalTitle(),
      menu: this.buildLocalMenu()
    }
  }

  private buildLocalTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('媒体库', this.hdsMaterialLevel)
    base.content = this.buildLocalTitleBarContent()
    return base
  }

  private buildProgressText(record: LocalVideoRecord): string {
    if (record.durationMs <= 0) {
      return this.formatTime(record.positionMs)
    }
    return this.formatTime(record.positionMs) + ' / ' + this.formatTime(record.durationMs)
  }

  private buildProgressPercentText(record: LocalVideoRecord): string {
    if (record.durationMs <= 0) {
      return '0%'
    }
    const percent = Math.max(0, Math.min(99, Math.floor(record.positionMs * 100 / record.durationMs)))
    return percent + '%'
  }

  private buildOwnFolderStatusText(): string {
    if (this.ownFolderScanning) {
      return '读取中'
    }
    if (this.ownFolderScanFailed) {
      return '暂不可访问'
    }
    if (!this.ownFolderScanned) {
      return '未读取'
    }
    return this.ownFolderVideos.length + ' 个视频'
  }

  private buildOwnFolderEmptyTitle(): string {
    if (this.ownFolderScanning) {
      return '正在读取'
    }
    if (this.ownFolderScanFailed) {
      return '目录暂不可访问'
    }
    return '本地目录空空如也'
  }

  private buildOwnFolderEmptySubtitle(): string {
    if (this.ownFolderScanning) {
      return '正在读取本地目录'
    }
    if (this.ownFolderScanFailed) {
      return '请确认系统已授权或通过刷新重新激活目录'
    }
    return '请将视频文件放入应用专属下载目录及其子文件夹\n然后返回本页自动同步\n您也可以点击右上角按钮进行刷新'
  }

  private formatFileSize(size: number): string {
    if (size <= 0) {
      return '未知大小'
    }
    const mb = size / 1024 / 1024
    if (mb < 1024) {
      return mb.toFixed(mb >= 100 ? 0 : 1) + ' MB'
    }
    const gb = mb / 1024
    return gb.toFixed(gb >= 100 ? 0 : 1) + ' GB'
  }

  private formatLastPlayedAt(timestamp: number): string {
    if (timestamp <= 0) {
      return '--'
    }
    const date = new Date(timestamp)
    const now = new Date()
    const dateDay = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
    const nowDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const diffDays = Math.floor((nowDay - dateDay) / 86400000)
    const time = this.pad2(date.getHours()) + ':' + this.pad2(date.getMinutes())
    if (diffDays === 0) {
      return '今天 ' + time
    }
    if (diffDays === 1) {
      return '昨天 ' + time
    }
    return this.pad2(date.getMonth() + 1) + '-' + this.pad2(date.getDate())
  }

  private formatOffset(ms: number): string {
    if (ms === 0) {
      return '0s'
    }
    const sign = ms > 0 ? '+' : ''
    const absMs = Math.abs(ms)
    if (absMs >= 1000) {
      const seconds = absMs / 1000
      return sign + (seconds % 1 === 0 ? seconds.toFixed(0) : seconds.toFixed(1)) + 's'
    }
    return sign + absMs + 'ms'
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    if (hours > 0) {
      return hours + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
    }
    return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
  }

  private pad2(value: number): string {
    return value < 10 ? '0' + value : String(value)
  }
}
