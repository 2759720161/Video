import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationIconOptions, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { PlaybackQueueCodec } from '../../models/PlaybackQueueItem'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LOCAL_VIDEO_HISTORY_VERSION_KEY } from '../../store/LocalVideoHistoryChangeSignal'
import { Logger } from '../../utils/Logger'
import {
  getBottomSpacerHeight,
  getTopSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

const logger = new Logger('ContinueWatchingPage')

@Entry
@Component
struct ContinueWatchingPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onHistoryChanged') historyVersion: number = 0
  @State records: LocalVideoRecord[] = []
  @State showClearHistorySheet: boolean = false
  private scroller: Scroller = new Scroller()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()

  aboutToAppear(): void {
    this.reloadHistory()
  }

  onPageShow(): void {
    this.reloadHistory()
  }

  onRdbReadyChanged(): void {
    if (this.appRdbReady) {
      this.reloadHistory()
    }
  }

  onHistoryChanged(): void {
    if (this.appRdbReady) {
      this.reloadHistory()
    }
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 8 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')

          if (this.records.length > 0) {
            ForEach(this.records, (record: LocalVideoRecord) => {
              this.HistoryCard(record)
            }, (record: LocalVideoRecord) => 'continue_' + record.id + '_' + record.fileKey + '_' + record.coverUri)
          } else {
            this.EmptyState()
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
    .titleBar(this.buildContinueWatchingTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showClearHistorySheet, this.ClearHistorySheet, {
      height: 220,
      showClose: false,
      dragBar: false
    })
  }

  @Builder
  private ClearHistorySheet(): void {
    Column() {
      Text('清空播放记录？')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 28, bottom: 16 })
      Text('这只会清除应用保存的观看进度和封面信息，不会删除视频文件。')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(22)
        .width('100%')
        .margin({ bottom: 18 })
      Row() {
        Text('取消')
          .layoutWeight(1)
          .height(52)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showClearHistorySheet = false
          })
        Divider()
          .vertical(true)
          .height(30)
          .color($r('app.color.divider_color'))
        Text('清空')
          .layoutWeight(1)
          .height(52)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.status_error'))
          .textAlign(TextAlign.Center)
          .onClick(() => this.clearHistory())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 12 })
  }

  @Builder
  private HistoryCard(record: LocalVideoRecord): void {
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
        Row() {
          Text(this.progressText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.progressPercent(record))
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
        Text('上次播放 ' + this.formatLastPlayedAt(record.lastPlayedAt))
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .height(82)
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
    .onClick(() => this.openRecord(record))
  }

  @Builder
  private EmptyState(): void {
    Column() {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(76)
        .fontColor([$r('app.color.accent_blue')])
      Text('还没有播放记录')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 18 })
      Text('播放过的视频会显示在这里')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 10 })
    }
    .width('100%')
    .height(360)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private async reloadHistory(): Promise<void> {
    if (!this.appRdbReady) {
      return
    }
    try {
      this.records = await this.historyStore.getAll()
    } catch (err) {
      logger.warn('读取继续观看失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.records = []
    }
  }

  private async clearHistory(): Promise<void> {
    this.showClearHistorySheet = false
    if (!this.appRdbReady) {
      return
    }
    try {
      await this.historyStore.clearAll()
      this.records = []
    } catch (err) {
      logger.warn('清空继续观看失败: %{public}s', err instanceof Error ? err.message : String(err))
      await this.reloadHistory()
    }
  }

  private buildContinueWatchingTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base = buildTitleBarOptions('继续观看', this.hdsMaterialLevel)
    if (this.records.length > 0) {
      const clearIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.trash'),
        label: 'clear playback history',
        action: () => {
          this.showClearHistorySheet = true
        }
      }
      base.content = {
        title: { mainTitle: '继续观看' },
        menu: { value: [{ content: clearIcon }] }
      }
    }
    return base
  }

  private async openRecord(record: LocalVideoRecord): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        if (!await LocalFilePicker.authorizeExistingUri(context, record.fileUri)) {
          return
        }
      } catch (err) {
        logger.warn('重新授权播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
        return
      }
    }
    let index = 0
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].fileUri === record.fileUri && this.records[i].fileSize === record.fileSize) {
        index = i
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
        playlistJson: PlaybackQueueCodec.encode(this.records),
        queueIndex: index
      }
    })
  }

  private progressText(record: LocalVideoRecord): string {
    return record.durationMs > 0 ? this.formatTime(record.positionMs) + ' / ' + this.formatTime(record.durationMs) :
      this.formatTime(record.positionMs)
  }

  private progressPercent(record: LocalVideoRecord): string {
    if (record.durationMs <= 0) {
      return '0%'
    }
    return Math.max(0, Math.min(99, Math.floor(record.positionMs * 100 / record.durationMs))) + '%'
  }

  private formatTime(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const remainSeconds = seconds % 60
    return hours > 0 ? hours + ':' + String(minutes).padStart(2, '0') + ':' + String(remainSeconds).padStart(2, '0') :
      String(minutes).padStart(2, '0') + ':' + String(remainSeconds).padStart(2, '0')
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

  private pad2(value: number): string {
    return value < 10 ? '0' + value : String(value)
  }
}
