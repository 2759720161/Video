import { promptAction, router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
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

const logger = new Logger('PlaybackHistoryPage')
const COMPLETED_THRESHOLD = 0.995
const HISTORY_HIGHLIGHT_LIMIT = 5

class PlaybackHistoryGroup {
  title: string = ''
  records: LocalVideoRecord[] = []
}

@Entry
@Component
struct ContinueWatchingPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onHistoryChanged') historyVersion: number = 0
  @State records: LocalVideoRecord[] = []
  @State activeFilter: string = 'all'
  @State featuredIndex: number = 0
  @State isEditMode: boolean = false
  @State selectedIds: number[] = []
  @State showDeleteDialog: boolean = false
  private scroller: Scroller = new Scroller()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()

  aboutToAppear(): void {
    this.reloadHistory()
  }

  onPageShow(): void {
    this.reloadHistory()
  }

  onBackPress(): boolean {
    if (this.isEditMode) {
      this.exitEditMode()
      return true
    }
    return false
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
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 0 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')

          if (this.records.length > 0) {
            if (!this.isEditMode) {
              this.HistoryHighlights()
              this.FilterBar()
            }
            this.HistoryGroups()
          } else {
            this.EmptyState()
          }

          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildHistoryTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor($r('app.color.page_background'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (this.showDeleteDialog) {
        this.DeleteConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private FilterBar(): void {
    Row({ space: 8 }) {
      this.FilterChip('全部', 'all')
      this.FilterChip('未播完', 'unfinished')
    }
    .width('100%')
    .margin({ top: 12, bottom: 12 })
  }

  @Builder
  private HistoryHighlights(): void {
    if (this.getFeaturedRecords().length > 0) {
      Column({ space: 0 }) {
        Swiper() {
          ForEach(this.getFeaturedRecords(), (record: LocalVideoRecord) => {
            this.HistoryHighlightCard(record)
          }, (record: LocalVideoRecord) => 'history_highlight_' + record.id + '_' + record.coverUri + '_' + record.positionMs)
        }
        .width('100%')
        .height(224)
        .indicator(false)
        .autoPlay(this.getFeaturedRecords().length > 1)
        .interval(5000)
        .loop(this.getFeaturedRecords().length > 1)
        .duration(420)
        .itemSpace(12)
        .prevMargin(24)
        .nextMargin(24)
        .onChange((index: number) => this.featuredIndex = index)

        this.HistoryHighlightDetails()
      }
      .width('100%')
      .margin({ top: 20 })
    }
  }

  @Builder
  private HistoryHighlightCard(record: LocalVideoRecord): void {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
        .draggable(false)
        .width('100%')
        .height(224)
        .objectFit(ImageFit.Cover)
        .opacity(record.coverUri.length > 0 ? 1 : 0.82)

      Column() {
        Blank().layoutWeight(1)
        if (record.durationMs > 0) {
          Progress({
            value: Math.min(record.positionMs, record.durationMs),
            total: record.durationMs,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(3)
            .color($r('app.color.accent_blue'))
            .backgroundColor('#66FFFFFF')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('100%')
    .height(224)
    .borderRadius(24)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => this.openRecord(record))
  }

  @Builder
  private HistoryHighlightDetails(): void {
    if (this.getCurrentFeaturedRecord() !== undefined) {
      Column({ space: 5 }) {
        Text(this.getCurrentFeaturedRecord()!.fileName)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row() {
          Text(this.progressSummary(this.getCurrentFeaturedRecord()!))
            .fontSize(13)
            .fontColor($r('app.color.accent_blue'))
            .fontWeight(FontWeight.Medium)
          Text('·')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 7, right: 7 })
          Text(this.formatLastPlayedAt(this.getCurrentFeaturedRecord()!.lastPlayedAt))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .width('100%')
      .margin({ left: 24, right: 24, top: 12 })
    }
  }

  @Builder
  private FilterChip(title: string, value: string): void {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.activeFilter === value ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor(this.activeFilter === value ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
      .onClick(() => {
        this.activeFilter = value
        this.featuredIndex = 0
      })
  }

  @Builder
  private HistoryGroups(): void {
    Column({ space: 0 }) {
      ForEach(this.getHistoryGroups(), (group: PlaybackHistoryGroup) => {
        Column({ space: 0 }) {
          Text(group.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ top: 16, bottom: 6 })

          ForEach(group.records, (record: LocalVideoRecord) => {
            this.HistoryMediaRow(record)
          }, (record: LocalVideoRecord) => 'history_row_' + record.id + '_' + record.coverUri + '_' + record.positionMs)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (group: PlaybackHistoryGroup) => 'history_group_' + group.title + '_' + group.records.length)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private HistoryMediaRow(record: LocalVideoRecord): void {
    Column() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
            .draggable(false)
            .width(112)
            .height(63)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(record.coverUri.length > 0 ? 1 : 0.82)
          if (record.durationMs > 0) {
            Progress({
              value: Math.min(record.positionMs, record.durationMs),
              total: record.durationMs,
              type: ProgressType.Linear
            })
              .width('100%')
              .height(3)
              .color($r('app.color.accent_blue'))
              .backgroundColor('#66000000')
          }
        }
        .width(112)
        .height(63)

        Column() {
          Text(record.fileName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.progressSummary(record))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
          Text(this.formatLastPlayedAt(record.lastPlayedAt))
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .height(72)
        .alignItems(HorizontalAlign.Start)

        if (this.isEditMode) {
          SymbolGlyph(this.isSelected(record.id) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'))
            .fontSize(24)
            .fontColor([this.isSelected(record.id) ? $r('sys.color.font_emphasize') : $r('app.color.text_secondary')])
            .width(28)
            .margin({ left: 8 })
        } else {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .width(36)
            .height(44)
            .padding({ left: 8, right: 8, top: 12, bottom: 12 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => this.showRecordActions(record))
        }
      }
      .width('100%')
      .height(88)
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.handleRecordTap(record))

      Divider()
        .color($r('app.color.divider_color'))
        .margin({ left: 124 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EmptyState(): void {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(64)
          .height(64)
          .fill($r('app.color.accent_blue'))
          .opacity(0.12)
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(27)
          .fontColor([$r('app.color.accent_blue')])
      }
      .width(72)
      .height(72)
      Text('暂无播放历史')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 18 })
      Text('播放过的视频会显示在这里')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 10 })
      Button('打开视频')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.accent_blue'))
        .borderRadius(12)
        .padding({ left: 24, right: 24 })
        .margin({ top: 22 })
        .onClick(() => this.pickAndOpenVideo())
    }
    .width('100%')
    .height(400)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private async reloadHistory(): Promise<void> {
    if (!this.appRdbReady) {
      return
    }
    try {
      this.records = await this.historyStore.getAll()
      this.removeMissingSelections()
    } catch (err) {
      logger.warn('读取播放历史失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.records = []
    }
  }

  private getHistoryGroups(): PlaybackHistoryGroup[] {
    const groups: PlaybackHistoryGroup[] = []
    const titles: string[] = ['今天', '昨天', '最近 7 天', '更早']
    for (let i = 0; i < titles.length; i++) {
      const group = new PlaybackHistoryGroup()
      group.title = titles[i]
      groups.push(group)
    }
    const filtered = this.getFilteredRecords()
    const featuredIds: number[] = []
    if (!this.isEditMode) {
      const featured = this.getFeaturedRecords()
      for (let i = 0; i < featured.length; i++) {
        featuredIds.push(featured[i].id)
      }
    }
    for (let i = 0; i < filtered.length; i++) {
      if (featuredIds.indexOf(filtered[i].id) >= 0) {
        continue
      }
      groups[this.getDateGroupIndex(filtered[i].lastPlayedAt)].records.push(filtered[i])
    }
    const visible: PlaybackHistoryGroup[] = []
    for (let i = 0; i < groups.length; i++) {
      if (groups[i].records.length > 0) {
        visible.push(groups[i])
      }
    }
    return visible
  }

  private getFilteredRecords(): LocalVideoRecord[] {
    if (this.activeFilter === 'all') {
      return this.records
    }
    const filtered: LocalVideoRecord[] = []
    for (let i = 0; i < this.records.length; i++) {
      if (!this.isCompleted(this.records[i])) {
        filtered.push(this.records[i])
      }
    }
    return filtered
  }

  private getFeaturedRecords(): LocalVideoRecord[] {
    const featured: LocalVideoRecord[] = []
    const filtered = this.getFilteredRecords()
    for (let i = 0; i < filtered.length && featured.length < HISTORY_HIGHLIGHT_LIMIT; i++) {
      featured.push(filtered[i])
    }
    return featured
  }

  private getCurrentFeaturedRecord(): LocalVideoRecord | undefined {
    const featured = this.getFeaturedRecords()
    if (featured.length === 0) {
      return undefined
    }
    return featured[Math.min(this.featuredIndex, featured.length - 1)]
  }

  private getDateGroupIndex(timestamp: number): number {
    if (timestamp <= 0) {
      return 3
    }
    const date = new Date(timestamp)
    const now = new Date()
    const dateDay = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
    const nowDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const diffDays = Math.floor((nowDay - dateDay) / 86400000)
    if (diffDays <= 0) {
      return 0
    }
    if (diffDays === 1) {
      return 1
    }
    return diffDays < 7 ? 2 : 3
  }

  private progressSummary(record: LocalVideoRecord): string {
    if (this.isCompleted(record)) {
      return '已播放完'
    }
    if (record.durationMs <= 0) {
      return '观看至 ' + this.formatTime(record.positionMs)
    }
    const percent = Math.max(0, Math.min(99, Math.floor(record.positionMs * 100 / record.durationMs)))
    const remainMinutes = Math.ceil(Math.max(0, record.durationMs - record.positionMs) / 60000)
    return remainMinutes > 0 ? '已观看 ' + percent + '% · 剩余 ' + remainMinutes + ' 分钟' : '已观看 ' + percent + '%'
  }

  private isCompleted(record: LocalVideoRecord): boolean {
    return record.durationMs > 0 && record.positionMs / record.durationMs >= COMPLETED_THRESHOLD
  }

  private handleRecordTap(record: LocalVideoRecord): void {
    if (this.isEditMode) {
      this.toggleSelect(record.id)
      return
    }
    this.openRecord(record)
  }

  private showRecordActions(record: LocalVideoRecord): void {
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: record.fileName,
        buttons: [
          { text: '继续播放', color: $r('app.color.text_primary') },
          { text: '从头播放', color: $r('app.color.text_primary') },
          { text: '从播放历史移除', color: $r('app.color.status_error') }
        ]
      }, (err: BusinessError, result: promptAction.ActionMenuSuccessResponse) => {
        if (err !== undefined) {
          logger.warn('显示播放历史菜单失败: %{public}s', err.message)
          return
        }
        if (result.index === 0) {
          void this.openRecord(record)
        } else if (result.index === 1) {
          void this.openRecord(record, true)
        } else if (result.index === 2) {
          void this.confirmRemoveRecord(record)
        }
      })
    } catch (err) {
      logger.warn('显示播放历史菜单失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private confirmRemoveRecord(record: LocalVideoRecord): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '从播放历史移除？',
        message: '仅删除观看记录和进度，不会删除本地视频。',
        buttons: [
          { text: '取消', color: $r('app.color.text_primary') },
          { text: '移除', color: $r('app.color.status_error') }
        ]
      }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
        if (err !== undefined) {
          logger.warn('显示移除确认失败: %{public}s', err.message)
          return
        }
        if (result.index === 1) {
          void this.removeRecord(record)
        }
      })
    } catch (err) {
      logger.warn('显示移除确认失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async removeRecord(record: LocalVideoRecord): Promise<void> {
    if (record.id < 0) {
      return
    }
    try {
      await LocalFilePicker.revokeUriPermission(record.fileUri)
      await this.historyStore.deleteById(record.id)
      this.removeRecordFromPage(record.id)
    } catch (err) {
      logger.warn('移除播放历史失败: %{public}s', err instanceof Error ? err.message : String(err))
      await this.reloadHistory()
    }
  }

  private toggleSelect(id: number): void {
    const index = this.selectedIds.indexOf(id)
    if (index >= 0) {
      this.selectedIds = this.selectedIds.filter((value: number) => value !== id)
    } else {
      this.selectedIds = [...this.selectedIds, id]
    }
  }

  private toggleSelectAll(): void {
    if (this.selectedIds.length === this.records.length) {
      this.selectedIds = []
      return
    }
    const ids: number[] = []
    for (let i = 0; i < this.records.length; i++) {
      ids.push(this.records[i].id)
    }
    this.selectedIds = ids
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0
  }

  private exitEditMode(): void {
    this.isEditMode = false
    this.selectedIds = []
    this.showDeleteDialog = false
  }

  private removeMissingSelections(): void {
    const existing: number[] = []
    for (let i = 0; i < this.records.length; i++) {
      existing.push(this.records[i].id)
    }
    this.selectedIds = this.selectedIds.filter((id: number) => existing.indexOf(id) >= 0)
    if (this.records.length === 0) {
      this.exitEditMode()
    }
  }

  private removeRecordFromPage(id: number): void {
    this.records = this.records.filter((record: LocalVideoRecord) => record.id !== id)
    this.removeMissingSelections()
  }

  private async clearHistory(): Promise<void> {
    if (!this.appRdbReady) {
      return
    }
    try {
      await this.historyStore.clearAll()
      this.records = []
      this.exitEditMode()
    } catch (err) {
      logger.warn('清空播放历史失败: %{public}s', err instanceof Error ? err.message : String(err))
      await this.reloadHistory()
    }
  }

  private buildHistoryTitleBarOptions(): HdsNavigationTitleBarOptions {
    const title = this.isEditMode ? '已选择 ' + this.selectedIds.length + ' 项' : '播放历史'
    const base = buildTitleBarOptions(title, this.hdsMaterialLevel)
    if (this.records.length === 0) {
      return base
    }
    if (this.isEditMode) {
      const deleteIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.trash'),
        label: 'delete selected playback history',
        action: () => {
          if (this.selectedIds.length > 0) {
            this.showDeleteDialog = true
          }
        }
      }
      const selectAllIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.checkmark_square_on_square'),
        label: 'select all playback history',
        action: () => this.toggleSelectAll()
      }
      base.content = {
        title: { mainTitle: title },
        menu: { value: [{ content: deleteIcon }, { content: selectAllIcon }] }
      }
      return base
    }
    const editIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.square_and_pencil'),
      label: 'edit playback history',
      action: () => this.isEditMode = true
    }
    const clearIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.ellipsis_circle'),
      label: 'clear playback history',
      action: () => this.showHistoryActions()
    }
    base.content = {
      title: { mainTitle: '播放历史' },
      menu: { value: [{ content: editIcon }, { content: clearIcon }] }
    }
    return base
  }

  @Builder
  private DeleteConfirmDialog(): void {
    Column() {
      Column() {
        Text('删除播放历史？')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 24 })

        Text(this.selectedIds.length > 1 ?
          '确定要删除这 ' + this.selectedIds.length + ' 条播放记录吗？' : '确定要删除这条播放记录吗？')
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
            .onClick(() => this.showDeleteDialog = false)

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
            .onClick(() => this.confirmDeleteSelectedRecords())
        }
        .width('100%')
        .height(52)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 20 })
      .borderRadius(34)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20, bottom: 28 })
    .onClick(() => this.showDeleteDialog = false)
  }

  private showHistoryActions(): void {
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: '播放历史',
        buttons: [
          { text: '清空播放历史', color: $r('app.color.status_error') }
        ]
      }, (err: BusinessError, result: promptAction.ActionMenuSuccessResponse) => {
        if (err !== undefined) {
          logger.warn('显示播放历史菜单失败: %{public}s', err.message)
          return
        }
        if (result.index === 0) {
          this.confirmClearHistory()
        }
      })
    } catch (err) {
      logger.warn('显示播放历史菜单失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private confirmClearHistory(): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '清空播放历史？',
        message: '这只会清除应用保存的观看进度和封面信息，不会删除视频文件。',
        buttons: [
          { text: '取消', color: $r('app.color.text_primary') },
          { text: '清空', color: $r('app.color.status_error') }
        ]
      }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
        if (err !== undefined) {
          logger.warn('显示清空确认失败: %{public}s', err.message)
          return
        }
        if (result.index === 1) {
          void this.clearHistory()
        }
      })
    } catch (err) {
      logger.warn('显示清空确认失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async deleteSelectedRecords(): Promise<void> {
    if (this.selectedIds.length === 0) {
      return
    }
    const ids = [...this.selectedIds]
    const removed: LocalVideoRecord[] = []
    for (let i = 0; i < this.records.length; i++) {
      if (ids.indexOf(this.records[i].id) >= 0) {
        removed.push(this.records[i])
      }
    }
    try {
      for (let i = 0; i < removed.length; i++) {
        await LocalFilePicker.revokeUriPermission(removed[i].fileUri)
      }
      await this.historyStore.deleteByIds(ids)
      this.records = this.records.filter((record: LocalVideoRecord) => ids.indexOf(record.id) < 0)
      this.exitEditMode()
    } catch (err) {
      logger.warn('批量移除播放历史失败: %{public}s', err instanceof Error ? err.message : String(err))
      await this.reloadHistory()
    }
  }

  private confirmDeleteSelectedRecords(): void {
    this.showDeleteDialog = false
    void this.deleteSelectedRecords()
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

  private async openRecord(record: LocalVideoRecord, fromBeginning: boolean = false): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        if (!await LocalFilePicker.authorizeExistingUri(context, record.fileUri)) {
          return
        }
      } catch (err) {
        logger.warn('重新授权播放历史失败: %{public}s', err instanceof Error ? err.message : String(err))
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
        historyPositionMs: fromBeginning ? 0 : record.positionMs,
        historyDurationMs: record.durationMs,
        playlistJson: PlaybackQueueCodec.encode(this.records),
        queueIndex: index
      }
    })
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

  private formatTime(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const remainSeconds = seconds % 60
    return hours > 0 ? hours + ':' + String(minutes).padStart(2, '0') + ':' + String(remainSeconds).padStart(2, '0') :
      String(minutes).padStart(2, '0') + ':' + String(remainSeconds).padStart(2, '0')
  }

  private pad2(value: number): string {
    return value < 10 ? '0' + value : String(value)
  }
}
