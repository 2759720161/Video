import { common } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  IconStyleMode
} from '@kit.UIDesignKit'
import { M3u8ConverterService, M3u8ConversionUpdate } from '../../services/M3u8ConverterService'
import { M3u8FolderChoice, UserDownloadFolder } from '../../services/UserDownloadFolder'
import { LocalMediaLibraryChangeSignal } from '../../store/LocalMediaLibraryChangeSignal'
import {
  getBottomSpacerHeight,
  getTopSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

@Entry
@Component
struct M3u8ConverterPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State playlistPath: string = ''
  @State playlistName: string = ''
  @State packageFolderPath: string = ''
  @State segmentCount: number = 0
  @State isScanning: boolean = false
  @State isLoadingFolderChoices: boolean = false
  @State showFolderPicker: boolean = false
  @State folderChoices: M3u8FolderChoice[] = []
  @State selectedFolderLabel: string = ''
  @State progress: number = 0
  @State status: string = '正在扫描应用专属目录…'
  @State isConverting: boolean = false
  @State finished: boolean = false
  private pageAlive: boolean = true
  private scroller: Scroller = new Scroller()
  private folderPickerScroller: Scroller = new Scroller()
  private packageRelativePath: string = ''

  aboutToAppear(): void {
    this.pageAlive = true
    const rawParams = router.getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      const relativePath = params['relativePath']
      if (typeof relativePath === 'string') {
        this.packageRelativePath = relativePath
        this.selectedFolderLabel = relativePath.length > 0 ? relativePath : '应用专属目录'
      }
    }
    if (this.selectedFolderLabel.length > 0) {
      void this.scanLocalPackage()
    } else {
      this.status = '请选择应用专属目录中的 m3u8 文件夹'
    }
  }

  aboutToDisappear(): void {
    this.pageAlive = false
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          Column({ space: 16 }) {
            this.SourceCard()
            this.OutputCard()
          }
          .width('100%')
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight))
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(this.titleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showFolderPicker, this.FolderPickerContent(), {
      height: SheetSize.MEDIUM,
      showClose: false,
      dragBar: false,
      onWillDismiss: (dismissSheetAction: DismissSheetAction) => {
        if (dismissSheetAction.reason === DismissReason.SLIDE_DOWN) {
          return
        }
        dismissSheetAction.dismiss()
      },
      onWillSpringBackWhenDismiss: (springBackAction: SpringBackAction) => {
        springBackAction.springBack()
      }
    })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[$r('app.color.home_bg_top'), 0], [$r('app.color.page_background'), 0.22],
        [$r('app.color.page_background'), 1]]
    })
  }

  @Builder
  private SourceCard(): void {
    Column({ space: 12 }) {
      Text('转换来源')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('请选择应用专属目录中的资源文件夹，应用会自动识别其中的 m3u8 播放列表。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.selectedFolderLabel.length > 0) {
        Text('已选择：' + this.selectedFolderLabel)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.playlistName.length > 0) {
        Text('播放列表：' + this.playlistName)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('已发现 ' + String(this.segmentCount) + ' 个视频分片')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else {
        Text(this.status)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      Button(this.isScanning ? '正在扫描…' : this.selectedFolderLabel.length > 0 ? '更换应用内文件夹' : '选择应用内文件夹')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor($r('app.color.accent_blue'))
        .backgroundColor($r('app.color.button_ghost_bg'))
        .borderRadius(12)
        .enabled(!this.isScanning && !this.isConverting)
        .onClick(() => this.openFolderPicker())
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  private FolderPickerContent(): void {
    HdsNavigation() {
      Scroll(this.folderPickerScroller) {
        Column() {
          if (this.isLoadingFolderChoices) {
            Column() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(32)
                .fontColor([$r('app.color.accent_blue')])
              Text('正在读取应用专属目录…')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 12 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.folderChoices.length === 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(48)
                .fontColor([$r('app.color.accent_blue')])
              Text('未发现 m3u8 文件夹')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 12 })
              Text('请将包含 .m3u8 和 .ts 分片的完整文件夹放入应用专属目录')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 24, right: 24 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Column({ space: 8 }) {
              ForEach(this.folderChoices, (choice: M3u8FolderChoice) => {
                this.FolderChoiceRow(choice)
              }, (choice: M3u8FolderChoice) => 'm3u8_choice_' + choice.relativePath)
            }
            .width('100%')
            .padding({ top: 8, bottom: 16 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .clip(false)
      .scrollable(ScrollDirection.Vertical)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_ONLY,
        scrollBackward: NestedScrollMode.SELF_ONLY
      })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar({
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: '选择 m3u8 文件夹',
          subTitle: '仅显示检测到 m3u8 播放列表的文件夹'
        },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.xmark'),
              type: IconStyleMode.SMALL,
              action: () => {
                this.showFolderPicker = false
              }
            }
          }]
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .bindToScrollable([this.folderPickerScroller])
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private FolderChoiceRow(choice: M3u8FolderChoice): void {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.folder_fill'))
        .fontSize(28)
        .fontColor([$r('app.color.accent_blue')])
      Column({ space: 4 }) {
        Text(choice.folderName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(choice.relativePath.length > 0 ? choice.relativePath : '应用专属目录')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(choice.playlistName + ' · ' + String(choice.segmentCount) + ' 个视频分片')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .onClick(() => this.selectFolder(choice))
  }

  @Builder
  private OutputCard(): void {
    Column({ space: 12 }) {
      Text('输出设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('视频将保存到 m3u8 所在文件夹，文件名与文件夹名称相同。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.isConverting || this.finished) {
        Progress({ value: this.progress, total: 1, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color($r('app.color.accent_blue'))
          .backgroundColor($r('app.color.button_ghost_bg'))
      }
      Text(this.status)
        .fontSize(14)
        .fontColor(this.finished ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
        .width('100%')
      Button(this.isConverting ? '正在转换…' : this.finished ? '再次转换' : '开始转换')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.accent_blue'))
        .borderRadius(14)
        .enabled(!this.isConverting && !this.isScanning && this.playlistPath.length > 0)
        .onClick(() => this.startConversion())
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const options = buildTitleBarOptions('m3u8 转 MP4', this.hdsMaterialLevel)
    options.content = { title: { mainTitle: 'm3u8 转 MP4' } }
    return options
  }

  private async scanLocalPackage(): Promise<void> {
    if (this.isScanning || this.isConverting) {
      return
    }
    this.isScanning = true
    this.playlistPath = ''
    this.playlistName = ''
    this.packageFolderPath = ''
    this.segmentCount = 0
    this.finished = false
    this.status = '正在扫描已选择的 m3u8 文件夹…'
    try {
      const packageInfo = await M3u8ConverterService.getInstance().findLocalPackage(
        getContext(this) as common.UIAbilityContext, this.packageRelativePath, true)
      if (packageInfo === null) {
        this.status = '未找到 m3u8 播放列表，请将完整资源文件夹放入应用专属目录'
        return
      }
      this.playlistPath = packageInfo.playlistPath
      this.playlistName = packageInfo.playlistName
      this.packageFolderPath = packageInfo.folderPath
      this.segmentCount = packageInfo.segmentCount
      this.status = packageInfo.segmentCount > 0 ? '已找到本地 HLS 资源，可以开始转换' :
        '已找到播放列表，但没有发现 .ts 视频分片'
    } catch (err) {
      this.status = err instanceof Error ? err.message : String(err)
    } finally {
      this.isScanning = false
    }
  }

  private openFolderPicker(): void {
    if (this.isScanning || this.isConverting) {
      return
    }
    this.showFolderPicker = true
    void this.loadFolderChoices()
  }

  private async loadFolderChoices(): Promise<void> {
    if (this.isLoadingFolderChoices) {
      return
    }
    this.isLoadingFolderChoices = true
    try {
      const choices = await UserDownloadFolder.listM3u8FolderChoices(
        getContext(this) as common.UIAbilityContext)
      this.folderChoices = choices === null ? [] : choices
    } catch (err) {
      this.folderChoices = []
      this.status = '读取应用专属文件夹失败'
    } finally {
      this.isLoadingFolderChoices = false
    }
  }

  private selectFolder(choice: M3u8FolderChoice): void {
    this.showFolderPicker = false
    this.packageRelativePath = choice.relativePath
    this.selectedFolderLabel = choice.relativePath.length > 0 ? choice.relativePath : '应用专属目录'
    void this.scanLocalPackage()
  }

  private async startConversion(): Promise<void> {
    if (this.isConverting) {
      return
    }
    const source = this.playlistPath.trim()
    if (source.length === 0) {
      this.status = '未找到可转换的 m3u8 播放列表'
      return
    }
    this.isConverting = true
    this.finished = false
    this.progress = 0
    this.status = '正在准备转换…'
    try {
      const outputPath = await M3u8ConverterService.getInstance().start(
        getContext(this) as common.UIAbilityContext,
        source,
        this.packageFolderPath,
        (update: M3u8ConversionUpdate) => this.onConversionUpdate(update)
      )
      if (this.pageAlive) {
        this.status = '正在转换，完成后会自动保存到对应文件夹'
      }
      void outputPath
    } catch (err) {
      this.isConverting = false
      this.status = err instanceof Error ? err.message : String(err)
    }
  }

  private onConversionUpdate(update: M3u8ConversionUpdate): void {
    if (update.finished && update.success) {
      // The native converter publishes the final MP4 before this callback.
      // Notify folder pages even if this page is no longer visible.
      LocalMediaLibraryChangeSignal.notifyChanged()
    }
    if (!this.pageAlive) {
      return
    }
    this.progress = update.progress
    if (!update.finished) {
      this.status = '正在转换… ' + String(Math.round(update.progress * 100)) + '%'
      return
    }
    this.isConverting = false
    this.finished = update.success
    this.status = update.success ? '转换完成，MP4 已保存到对应文件夹' : update.message
  }
}
