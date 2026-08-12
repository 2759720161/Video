import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationIconOptions, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { PlaybackQueueCodec } from '../../models/PlaybackQueueItem'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LOCAL_VIDEO_HISTORY_VERSION_KEY } from '../../store/LocalVideoHistoryChangeSignal'
import { UserDownloadFolder, UserFolderEntry } from '../../services/UserDownloadFolder'
import { Logger } from '../../utils/Logger'
import {
  getBottomSpacerHeight,
  getTopSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

const logger = new Logger('FolderPage')

@Entry
@Component
struct FolderPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onHistoryChanged') historyVersion: number = 0
  @State entries: UserFolderEntry[] = []
  @State relativePath: string = ''
  @State searchText: string = ''
  @State sortMode: string = 'name'
  @State sortDescending: boolean = false
  @State showCreateFolderSheet: boolean = false
  @State newFolderName: string = ''
  @State newFolderError: string = ''
  @State isLoading: boolean = true
  @State isUnavailable: boolean = false
  @State folderCoverRenderVersion: number = 0
  private scroller: Scroller = new Scroller()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private isGeneratingFirstFrameCovers: boolean = false
  private pendingFirstFrameCoverGeneration: boolean = false

  aboutToAppear(): void {
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
    this.reloadDirectory()
  }

  onRdbReadyChanged(): void {
    if (this.appRdbReady) {
      this.reloadDirectory()
    }
  }

  onHistoryChanged(): void {
    if (this.appRdbReady) {
      this.reloadDirectory()
    }
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')

          if (this.relativePath.length > 0) {
            Text(this.relativePath)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 6, right: 6, bottom: 4 })
          }

          this.SearchAndSortBar()

          if (this.getVisibleEntries().length > 0) {
            ForEach(this.getVisibleEntries(), (entry: UserFolderEntry) => {
              if (entry.isDirectory) {
                this.DirectoryCard(entry)
              } else {
                this.VideoCard(entry.video)
              }
            }, (entry: UserFolderEntry) => entry.relativePath + '_' + entry.isDirectory + '_' + entry.video.coverUri +
              '_' + this.folderCoverRenderVersion)
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
  private SearchAndSortBar(): void {
    Row({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_secondary')])
        TextInput({ placeholder: '搜索当前目录...', text: this.searchText })
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_hint'))
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.searchText = value
          })
      }
      .layoutWeight(1)
      .height(44)
      .padding({ left: 14, right: 10 })
      .borderRadius(22)
      .backgroundColor($r('app.color.button_ghost_bg'))

      Button(this.sortModeLabel())
        .height(44)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.button_ghost_bg'))
        .borderRadius(22)
        .padding({ left: 14, right: 14 })
        .onClick(() => this.switchSortMode())

      Button(this.sortDescending ? '↓' : '↑')
        .width(44)
        .height(44)
        .fontSize(18)
        .fontColor($r('app.color.accent_blue'))
        .backgroundColor($r('app.color.button_ghost_bg'))
        .borderRadius(22)
        .onClick(() => {
          this.sortDescending = !this.sortDescending
        })
    }
    .width('100%')
    .margin({ bottom: 4 })

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
    .onClick(() => this.openChildFolder(entry.relativePath))
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
      SymbolGlyph(this.isLoading ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.folder'))
        .fontSize(72)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.isLoading ? '正在读取目录' : this.isUnavailable ? '目录暂不可访问' :
        isSearchEmpty ? '没有匹配的内容' : '此文件夹为空')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 18 })
      Text(this.isUnavailable ? '请点击刷新以重新激活应用专属目录' :
        isSearchEmpty ? '尝试修改搜索关键词' : '子文件夹和视频会显示在这里')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 10 })
      Button('刷新')
        .height(42)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.accent_blue'))
        .borderRadius(12)
        .padding({ left: 28, right: 28 })
        .margin({ top: 22 })
        .onClick(() => this.reloadDirectory())
    }
    .width('100%')
    .height(360)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28 })
  }

  private async reloadDirectory(): Promise<void> {
    this.isLoading = true
    this.isUnavailable = false
    try {
      const context = getContext(this) as common.UIAbilityContext
      const entries = await UserDownloadFolder.listOwnDirectory(context, this.relativePath)
      if (entries === null) {
        this.entries = []
        this.isUnavailable = true
        return
      }
      const history = this.appRdbReady ? await this.historyStore.getAll() : []
      this.bindHistory(entries, history)
      this.entries = entries
      this.ensureFirstFrameCovers()
    } catch (err) {
      this.entries = []
      this.isUnavailable = true
      logger.warn('读取文件夹页失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isLoading = false
    }
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
    base.content = {
      title: { mainTitle: this.getTitle() },
      menu: { value: [{ content: refreshFolderIcon }, { content: createFolderIcon }] }
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

  /** Generates first-frame covers for direct videos without changing history covers. */
  private async ensureFirstFrameCovers(): Promise<void> {
    if (this.isGeneratingFirstFrameCovers) {
      this.pendingFirstFrameCoverGeneration = true
      return
    }
    this.isGeneratingFirstFrameCovers = true
    this.pendingFirstFrameCoverGeneration = false
    try {
      const entryCount = this.entries.length
      for (let i = 0; i < entryCount; i++) {
        if (i >= this.entries.length) {
          break
        }
        const entry = this.entries[i]
        if (entry.isDirectory || entry.video.fileUri.length === 0) {
          continue
        }
        if (!await LocalFilePicker.ensureReadableUri(entry.video.fileUri)) {
          continue
        }
        const coverUri = await LocalVideoThumbnailStore.getInstance().ensureThumbnail(
          entry.video.fileUri,
          entry.video.fileName,
          entry.video.fileSize,
          LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS
        )
        if (coverUri.length === 0 || i >= this.entries.length ||
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
      logger.warn('生成目录视频首帧封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingFirstFrameCovers = false
      if (this.pendingFirstFrameCoverGeneration) {
        this.ensureFirstFrameCovers()
      }
    }
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
    return parts.length > 0 ? parts.join(' · ') : '空文件夹'
  }

  private switchSortMode(): void {
    if (this.sortMode === 'name') {
      this.sortMode = 'time'
    } else if (this.sortMode === 'time') {
      this.sortMode = 'size'
    } else {
      this.sortMode = 'name'
    }
  }

  private sortModeLabel(): string {
    if (this.sortMode === 'time') {
      return '时间'
    }
    if (this.sortMode === 'size') {
      return '大小'
    }
    return '名称'
  }

  private openChildFolder(relativePath: string): void {
    router.pushUrl({ url: 'pages/local/FolderPage', params: { relativePath: relativePath } })
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
