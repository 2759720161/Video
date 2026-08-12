import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { PreferencesStore } from '../../store/PreferencesStore'
import {
  PREFS_KEY_SUBTITLE_ENABLED,
  PREFS_KEY_SUBTITLE_FONT_BOLD,
  PREFS_KEY_SUBTITLE_FONT_COLOR,
  PREFS_KEY_SUBTITLE_FONT_SIZE,
  PREFS_KEY_SUBTITLE_OUTLINE_ENABLED,
  PREFS_KEY_SUBTITLE_RECENT_COLORS,
  PREFS_KEY_SUBTITLE_TIME_OFFSET_MS,
  SUBTITLE_ENABLED_DEFAULT,
  SUBTITLE_FONT_BOLD_DEFAULT,
  SUBTITLE_FONT_COLOR_DEFAULT,
  SUBTITLE_FONT_SIZE_DEFAULT,
  SUBTITLE_OUTLINE_ENABLED_DEFAULT,
  SUBTITLE_TIME_OFFSET_MS_DEFAULT,
  normalizeSubtitleFontSize,
  normalizeSubtitleTimeOffsetMs
} from '../../utils/SubtitlePreferences'
import { getBottomSpacerHeight, getTopSpacerHeight, buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

const MAX_RECENT_COLORS: number = 10

@Entry
@Component
struct SubtitleSettingsPage {
  @StorageLink(PREFS_KEY_SUBTITLE_ENABLED) subtitleEnabled: boolean = SUBTITLE_ENABLED_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_FONT_SIZE) subtitleFontSize: number = SUBTITLE_FONT_SIZE_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_FONT_BOLD) subtitleFontBold: boolean = SUBTITLE_FONT_BOLD_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_FONT_COLOR) subtitleFontColor: string = SUBTITLE_FONT_COLOR_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_RECENT_COLORS) subtitleRecentColors: string = '[]'
  @StorageLink(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED) subtitleOutlineEnabled: boolean = SUBTITLE_OUTLINE_ENABLED_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS) subtitleTimeOffsetMs: number = SUBTITLE_TIME_OFFSET_MS_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State colorHue: number = 0
  @State colorSaturation: number = 0
  @State colorValue: number = 1
  @State colorHexInput: string = '#FFFFFF'
  @State recentColors: string[] = []
  private scroller: Scroller = new Scroller()
  private readonly COLOR_PANEL_WIDTH: number = 228
  private readonly COLOR_PANEL_HEIGHT: number = 132
  private readonly VALUE_BAR_WIDTH: number = 24
  private readonly COLOR_INDICATOR_SIZE: number = 16
  private hsCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D()
  private valueCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D()
  private hsDragStartX: number = 0
  private hsDragStartY: number = 0
  private valueDragStartY: number = 0

  aboutToAppear(): void {
    this.syncPickerFromColor(this.subtitleFontColor)
    this.recentColors = this.parseRecentColors(this.subtitleRecentColors)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 0 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          this.PreviewCard()
          Text('字幕样式仅对外挂 SRT / WebVTT 文字字幕生效')
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8, top: 14, bottom: 2 })
          this.MainSubtitleStyleCard()
          this.PlaybackOptionCard()
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
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
    .titleBar(buildTitleBarOptions('字幕设置', this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private PreviewCard(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#192B3445', 0], ['#0D007DFF', 1]]
        })

      Column({ space: 10 }) {
        Text('这是一段字幕预览')
          .fontSize(this.subtitleFontSize + 8)
          .fontWeight(this.subtitleFontBold ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.subtitleFontColor)
          .textShadow(this.subtitleOutlineEnabled ? { radius: 2, color: '#E6000000', offsetX: 1, offsetY: 1 } : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(156)
    .borderRadius(22)
    .clip(true)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 14, color: $r('app.color.shadow_surface'), offsetY: 5 })
  }

  @Builder
  private MainSubtitleStyleCard(): void {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text('字幕样式')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('重置')
          .height(36)
          .fontSize(14)
          .fontColor($r('app.color.status_error'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .borderRadius(18)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.resetMainSubtitleStyle()
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 16 })

      Divider().color($r('app.color.divider_color')).margin({ left: 18, right: 18 })
      this.FontSizeControl()
      Divider().color($r('app.color.divider_color')).margin({ left: 18, right: 18 })
      this.StyleToggleRow('加粗', this.subtitleFontBold, (value: boolean) => this.setFontBold(value))
      Divider().color($r('app.color.divider_color')).margin({ left: 18, right: 18 })
      this.StyleToggleRow('文字描边', this.subtitleOutlineEnabled, (value: boolean) => this.setBoolean(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, value))
      Divider().color($r('app.color.divider_color')).margin({ left: 18, right: 18 })
      this.FontColorControl()
    }
    .width('100%')
    .borderRadius(22)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
    .margin({ top: 16 })
  }

  @Builder
  private FontSizeControl(): void {
    Column({ space: 8 }) {
      Row() {
        Text('字体大小')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.subtitleFontSize + ' sp')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_blue'))
      }
      .width('100%')

      Slider({ value: this.subtitleFontSize, min: 16, max: 24, step: 2 })
        .width('100%')
        .height(28)
        .selectedColor($r('app.color.accent_blue'))
        .trackColor($r('app.color.button_ghost_bg'))
        .onChange((value: number) => {
          this.setFontSize(value)
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 16 })
  }

  @Builder
  private StyleToggleRow(title: string, value: boolean, onChange: (value: boolean) => void): void {
    Row() {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor($r('app.color.accent_blue'))
        .onChange(onChange)
    }
    .width('100%')
    .height(62)
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private FontColorControl(): void {
    Column({ space: 12 }) {
      Text('字体颜色')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      this.ColorPickerPanel()

      TextInput({ text: this.colorHexInput, placeholder: '#FFFFFF' })
        .width('100%')
        .height(38)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.button_ghost_bg'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          const normalized = value.toUpperCase()
          // Canvas 选色会同步更新输入框；该回写不应再次按“手动输入”解析，
          // 否则亮度为 0 的黑色会丢失原有色相与饱和度。
          if (normalized === this.colorHexInput) return
          this.colorHexInput = normalized
          if (this.isRgbHex(this.colorHexInput)) {
            this.syncPickerFromColor(this.colorHexInput)
            this.applyPickerColor(true)
          }
        })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.recentColors, (color: string) => {
            this.ColorChip(color)
          }, (color: string) => color)
        }
        .padding({ right: 2 })
      }
      .width('100%')
      .height(38)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 20 })
  }

  @Builder
  private ColorPickerPanel(): void {
    Row({ space: 12 }) {
      Stack() {
        Canvas(this.hsCanvasContext)
          .width(this.COLOR_PANEL_WIDTH)
          .height(this.COLOR_PANEL_HEIGHT)
          .onReady(() => {
            this.drawHsPalette()
          })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              TapGesture().onAction((event: GestureEvent) => {
                this.updateHueSaturation(event, true)
              }),
              PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
                .onActionStart((event: GestureEvent) => {
                  this.beginHueSaturationDrag(event)
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.updateHueSaturationDrag(event)
                })
                .onActionEnd(() => {
                  this.persistPickerColor(this.currentPickerStorageColor())
                })
            )
          )

        Row()
          .width(this.COLOR_INDICATOR_SIZE)
          .height(this.COLOR_INDICATOR_SIZE)
          .border({ width: 2, color: Color.White })
          .borderRadius(this.COLOR_INDICATOR_SIZE / 2)
          .shadow({ radius: 3, color: Color.Black, offsetX: 0, offsetY: 0 })
          .position({
            x: this.hueIndicatorLeft(),
            y: this.saturationIndicatorTop()
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(this.COLOR_PANEL_WIDTH)
      .height(this.COLOR_PANEL_HEIGHT)
      .borderRadius(14)
      .clip(true)

      Stack() {
        Canvas(this.valueCanvasContext)
          .width(this.VALUE_BAR_WIDTH)
          .height(this.COLOR_PANEL_HEIGHT)
          .onReady(() => {
            this.drawValuePalette()
          })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              TapGesture().onAction((event: GestureEvent) => {
                this.updateValue(event, true)
              }),
              PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 1 })
                .onActionStart((event: GestureEvent) => {
                  this.beginValueDrag(event)
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.updateValueDrag(event)
                })
                .onActionEnd(() => {
                  this.persistPickerColor(this.currentPickerStorageColor())
                })
            )
          )
      }
      .width(this.VALUE_BAR_WIDTH)
      .height(this.COLOR_PANEL_HEIGHT)
      .borderRadius(12)
      .clip(true)

      Column()
        .width(28)
        .height(this.COLOR_PANEL_HEIGHT)
        .borderRadius(10)
        .backgroundColor(this.subtitleFontColor)
        .border({ width: 1, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ColorChip(color: string): void {
    Row({ space: 7 }) {
      Circle()
        .width(18)
        .height(18)
        .fill(color)
      Text(this.colorLabel(color))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .height(36)
    .padding({ left: 10, right: 10 })
    .borderRadius(18)
    .backgroundColor(color === this.subtitleFontColor ? $r('app.color.category_menu_item_selected') : $r('app.color.page_background'))
    .onClick(() => {
      this.setFontColor(color)
    })
  }

  @Builder
  private PlaybackOptionCard(): void {
    Column() {
      this.StyleToggleRow('显示外挂字幕', this.subtitleEnabled, (value: boolean) => this.setBoolean(PREFS_KEY_SUBTITLE_ENABLED, value))
      Divider().color($r('app.color.divider_color')).margin({ left: 18, right: 18 })
      Row() {
        Text('字幕时间偏移')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Select([{ value: '提前 1.0 秒' }, { value: '提前 0.5 秒' }, { value: '同步' }, { value: '延后 0.5 秒' }, { value: '延后 1.0 秒' }])
          .selected(this.timeOffsetIndex())
          .value(this.timeOffsetLabel())
          .font({ size: 14, weight: FontWeight.Medium })
          .onSelect((index: number) => {
            this.setTimeOffset([-1000, -500, 0, 500, 1000][index])
          })
      }
      .width('100%')
      .height(62)
      .padding({ left: 18, right: 18 })
    }
    .width('100%')
    .borderRadius(22)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
    .margin({ top: 12 })
  }

  private async setBoolean(key: string, value: boolean): Promise<void> {
    AppStorage.setOrCreate(key, value)
    await PreferencesStore.getInstance().setBoolean(key, value)
  }

  private async setFontSize(value: number): Promise<void> {
    const normalized = normalizeSubtitleFontSize(value)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_SIZE, normalized)
    await PreferencesStore.getInstance().setNumber(PREFS_KEY_SUBTITLE_FONT_SIZE, normalized)
  }

  private async setFontBold(value: boolean): Promise<void> {
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_BOLD, value)
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_FONT_BOLD, value)
  }

  private async setFontColor(value: string): Promise<void> {
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_COLOR, value)
    this.syncPickerFromColor(value)
    await PreferencesStore.getInstance().setString(PREFS_KEY_SUBTITLE_FONT_COLOR, value)
    await this.recordRecentColor(value)
  }

  private async resetMainSubtitleStyle(): Promise<void> {
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_SIZE, SUBTITLE_FONT_SIZE_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_BOLD, SUBTITLE_FONT_BOLD_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_COLOR, SUBTITLE_FONT_COLOR_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, SUBTITLE_OUTLINE_ENABLED_DEFAULT)
    await PreferencesStore.getInstance().setNumber(PREFS_KEY_SUBTITLE_FONT_SIZE, SUBTITLE_FONT_SIZE_DEFAULT)
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_FONT_BOLD, SUBTITLE_FONT_BOLD_DEFAULT)
    await PreferencesStore.getInstance().setString(PREFS_KEY_SUBTITLE_FONT_COLOR, SUBTITLE_FONT_COLOR_DEFAULT)
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, SUBTITLE_OUTLINE_ENABLED_DEFAULT)
    this.syncPickerFromColor(SUBTITLE_FONT_COLOR_DEFAULT)
  }

  private async setTimeOffset(value: number): Promise<void> {
    const normalized = normalizeSubtitleTimeOffsetMs(value)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, normalized)
    await PreferencesStore.getInstance().setNumber(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, normalized)
  }

  private timeOffsetIndex(): number {
    return [-1000, -500, 0, 500, 1000].indexOf(normalizeSubtitleTimeOffsetMs(this.subtitleTimeOffsetMs))
  }

  private timeOffsetLabel(): string {
    if (this.subtitleTimeOffsetMs === 0) return '同步'
    const seconds = (Math.abs(this.subtitleTimeOffsetMs) / 1000).toFixed(1)
    return this.subtitleTimeOffsetMs > 0 ? '延后 ' + seconds + ' 秒' : '提前 ' + seconds + ' 秒'
  }

  private updateHueSaturation(event: GestureEvent, persist: boolean): void {
    if (!event.fingerList || event.fingerList.length === 0) return
    const finger = event.fingerList[0]
    const x = Math.max(0, Math.min(this.COLOR_PANEL_WIDTH - 1, Math.round(finger.localX)))
    const y = Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - 1, Math.round(finger.localY)))
    this.updateHueSaturationAt(x, y, persist)
  }

  private beginHueSaturationDrag(event: GestureEvent): void {
    if (!event.fingerList || event.fingerList.length === 0) return
    const finger = event.fingerList[0]
    this.hsDragStartX = Math.max(0, Math.min(this.COLOR_PANEL_WIDTH - 1, Math.round(finger.localX)))
    this.hsDragStartY = Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - 1, Math.round(finger.localY)))
    this.updateHueSaturationAt(this.hsDragStartX, this.hsDragStartY, false)
  }

  private updateHueSaturationDrag(event: GestureEvent): void {
    // PanGesture 的 offset 坐标以按下点为基准；在手指滑出 Canvas 后仍然稳定。
    // 不再读取此时会被裁剪为 0 的 localX，避免色相跳回最左侧。
    const x = Math.max(0, Math.min(this.COLOR_PANEL_WIDTH - 1, Math.round(this.hsDragStartX + event.offsetX)))
    const y = Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - 1, Math.round(this.hsDragStartY + event.offsetY)))
    this.updateHueSaturationAt(x, y, false)
  }

  private updateHueSaturationAt(x: number, y: number, persist: boolean): void {
    this.colorHue = Math.min(359.999, (x / (this.COLOR_PANEL_WIDTH - 1)) * 360)
    this.colorSaturation = Math.max(0, Math.min(1, 1 - y / (this.COLOR_PANEL_HEIGHT - 1)))
    this.applyPickerColor(persist)
  }

  private updateValue(event: GestureEvent, persist: boolean): void {
    if (!event.fingerList || event.fingerList.length === 0) return
    const finger = event.fingerList[0]
    const y = Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - 1, Math.round(finger.localY)))
    this.updateValueAt(y, persist)
  }

  private beginValueDrag(event: GestureEvent): void {
    if (!event.fingerList || event.fingerList.length === 0) return
    this.valueDragStartY = Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - 1, Math.round(event.fingerList[0].localY)))
    this.updateValueAt(this.valueDragStartY, false)
  }

  private updateValueDrag(event: GestureEvent): void {
    const y = Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - 1, Math.round(this.valueDragStartY + event.offsetY)))
    this.updateValueAt(y, false)
  }

  private updateValueAt(y: number, persist: boolean): void {
    this.colorValue = Math.max(0, Math.min(1, 1 - y / (this.COLOR_PANEL_HEIGHT - 1)))
    this.applyPickerColor(persist)
  }

  private applyPickerColor(persist: boolean): void {
    const rgbHex = this.hsvToRgbHex(this.colorHue, this.colorSaturation, this.colorValue)
    const storageColor = this.currentPickerStorageColor()
    this.colorHexInput = rgbHex
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_COLOR, storageColor)
    this.drawHsPalette()
    this.drawValuePalette()
    if (persist) {
      this.persistPickerColor(storageColor)
    }
  }

  private async persistPickerColor(color: string): Promise<void> {
    await PreferencesStore.getInstance().setString(PREFS_KEY_SUBTITLE_FONT_COLOR, color)
    await this.recordRecentColor(color)
  }

  private syncPickerFromColor(value: string): void {
    const rgbHex = this.toRgbHex(value)
    const hsv = this.rgbHexToHsv(rgbHex)
    this.colorHue = hsv[0]
    this.colorSaturation = hsv[1]
    this.colorValue = hsv[2]
    this.colorHexInput = rgbHex
    this.drawHsPalette()
    this.drawValuePalette()
  }

  private drawHsPalette(): void {
    const context = this.hsCanvasContext
    const width = this.COLOR_PANEL_WIDTH
    const height = this.COLOR_PANEL_HEIGHT
    context.clearRect(0, 0, width, height)
    const hue = context.createLinearGradient(0, 0, width, 0)
    hue.addColorStop(0, '#FF0000')
    hue.addColorStop(0.17, '#FFFF00')
    hue.addColorStop(0.33, '#00FF00')
    hue.addColorStop(0.5, '#00FFFF')
    hue.addColorStop(0.67, '#0000FF')
    hue.addColorStop(0.83, '#FF00FF')
    hue.addColorStop(1, '#FF0000')
    context.fillStyle = hue
    context.fillRect(0, 0, width, height)
    const white = context.createLinearGradient(0, 0, 0, height)
    white.addColorStop(0, 'rgba(255,255,255,0)')
    white.addColorStop(1, 'rgba(255,255,255,1)')
    context.fillStyle = white
    context.fillRect(0, 0, width, height)
    if (this.colorValue < 1) {
      context.fillStyle = 'rgba(0,0,0,' + (1 - this.colorValue) + ')'
      context.fillRect(0, 0, width, height)
    }
  }

  private drawValuePalette(): void {
    const context = this.valueCanvasContext
    const width = this.VALUE_BAR_WIDTH
    const height = this.COLOR_PANEL_HEIGHT
    context.clearRect(0, 0, width, height)
    const gradient = context.createLinearGradient(0, 0, 0, height)
    gradient.addColorStop(0, this.hsvToRgbHex(this.colorHue, this.colorSaturation, 1))
    gradient.addColorStop(1, '#000000')
    context.fillStyle = gradient
    context.fillRect(0, 0, width, height)
  }

  private hueIndicatorLeft(): number {
    const half = this.COLOR_INDICATOR_SIZE / 2
    return Math.max(0, Math.min(this.COLOR_PANEL_WIDTH - this.COLOR_INDICATOR_SIZE, Math.round((this.colorHue / 360) * (this.COLOR_PANEL_WIDTH - 1) - half)))
  }

  private saturationIndicatorTop(): number {
    const half = this.COLOR_INDICATOR_SIZE / 2
    return Math.max(0, Math.min(this.COLOR_PANEL_HEIGHT - this.COLOR_INDICATOR_SIZE, Math.round((1 - this.colorSaturation) * (this.COLOR_PANEL_HEIGHT - 1) - half)))
  }

  private isRgbHex(value: string): boolean {
    return /^#[0-9A-F]{6}$/.test(value)
  }

  private toRgbHex(value: string): string {
    const uppercase = value.toUpperCase()
    if (/^#[0-9A-F]{8}$/.test(uppercase)) return '#' + uppercase.substring(3)
    if (this.isRgbHex(uppercase)) return uppercase
    return '#FFFFFF'
  }

  private rgbHexToHsv(hex: string): [number, number, number] {
    const red = parseInt(hex.substring(1, 3), 16) / 255
    const green = parseInt(hex.substring(3, 5), 16) / 255
    const blue = parseInt(hex.substring(5, 7), 16) / 255
    const max = Math.max(red, green, blue)
    const min = Math.min(red, green, blue)
    const delta = max - min
    if (max === 0) {
      return [this.colorHue, this.colorSaturation, 0]
    }
    let hue = 0
    if (delta !== 0) {
      if (max === red) hue = 60 * (((green - blue) / delta + 6) % 6)
      else if (max === green) hue = 60 * ((blue - red) / delta + 2)
      else hue = 60 * ((red - green) / delta + 4)
    } else {
      hue = this.colorHue
    }
    return [hue, delta / max, max]
  }

  private hsvToRgbHex(hue: number, saturation: number, value: number): string {
    const chroma = value * saturation
    const sector = hue / 60
    const x = chroma * (1 - Math.abs(sector % 2 - 1))
    let red = 0
    let green = 0
    let blue = 0
    if (sector < 1) { red = chroma; green = x }
    else if (sector < 2) { red = x; green = chroma }
    else if (sector < 3) { green = chroma; blue = x }
    else if (sector < 4) { green = x; blue = chroma }
    else if (sector < 5) { red = x; blue = chroma }
    else { red = chroma; blue = x }
    const match = value - chroma
    return '#' + this.toHex((red + match) * 255) + this.toHex((green + match) * 255) + this.toHex((blue + match) * 255)
  }

  private currentPickerStorageColor(): string {
    const rgbHex = this.hsvToRgbHex(this.colorHue, this.colorSaturation, this.colorValue)
    return '#FF' + rgbHex.substring(1)
  }

  private async recordRecentColor(color: string): Promise<void> {
    const normalized = this.normalizeStorageColor(color)
    const next: string[] = [normalized]
    for (let index = 0; index < this.recentColors.length && next.length < MAX_RECENT_COLORS; index++) {
      const existing = this.normalizeStorageColor(this.recentColors[index])
      if (existing !== normalized && next.indexOf(existing) < 0) {
        next.push(existing)
      }
    }
    this.recentColors = next
    const serialized = JSON.stringify(next)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_RECENT_COLORS, serialized)
    await PreferencesStore.getInstance().setString(PREFS_KEY_SUBTITLE_RECENT_COLORS, serialized)
  }

  private parseRecentColors(value: string): string[] {
    try {
      const parsed = JSON.parse(value) as string[]
      const colors: string[] = []
      for (let index = 0; index < parsed.length && colors.length < MAX_RECENT_COLORS; index++) {
        const color = this.normalizeStorageColor(parsed[index])
        if (colors.indexOf(color) < 0) colors.push(color)
      }
      return colors
    } catch (_error) {
      return []
    }
  }

  private normalizeStorageColor(value: string): string {
    const rgb = this.toRgbHex(value)
    return '#FF' + rgb.substring(1)
  }

  private colorLabel(value: string): string {
    return value.length === 9 ? '#' + value.substring(3) : value
  }

  private toHex(value: number): string {
    const hex = Math.round(Math.max(0, Math.min(255, value))).toString(16).toUpperCase()
    return hex.length === 1 ? '0' + hex : hex
  }
}
