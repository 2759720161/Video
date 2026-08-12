import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import {
  DanmakuStyleSettings,
  DANMAKU_PREFS_KEY_BORDER,
  DANMAKU_PREFS_KEY_BORDER_SIZE,
  DANMAKU_PREFS_KEY_COLOR,
  DANMAKU_PREFS_KEY_FONT_SIZE,
  DANMAKU_PREFS_KEY_FONT_WEIGHT,
  DANMAKU_PREFS_KEY_OPACITY,
  DANMAKU_PREFS_KEY_SCROLL_DURATION,
  DANMAKU_PREFS_KEY_LINE_HEIGHT,
  DANMAKU_PREFS_KEY_DISPLAY_AREA,
  DANMAKU_PREFS_KEY_HIDE_SCROLL,
  DANMAKU_PREFS_KEY_HIDE_TOP,
  DANMAKU_PREFS_KEY_HIDE_BOTTOM,
  DANMAKU_PREFS_KEY_HIDE_COLOR,
  DANMAKU_PREFS_KEY_BILIBILI_SOURCE,
  DANMAKU_PREFS_KEY_GAMER_SOURCE,
  DANMAKU_PREFS_KEY_DANDAN_SOURCE,
  DANMAKU_PREFS_KEY_FOLLOW_SPEED,
  DANMAKU_PREFS_KEY_DEDUPLICATION,
  DANMAKU_PREFS_KEY_MAX_LENGTH,
  DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED,
  DANMAKU_PREFS_KEY_BLOCK_KEYWORDS,
  DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED,
  DANMAKU_PREFS_KEY_BLOCK_REGEX,
  DANMAKU_PREFS_KEY_TIME_OFFSET,
  DANMAKU_PREFS_KEY_MASSIVE_MODE
} from '../../core/danmaku/DanmakuStyleSettings'

const logger = new Logger('DanmakuSettingsCtrl')

export class DanmakuSettingsController {
  async loadSettings(): Promise<DanmakuStyleSettings> {
    try {
      return await DanmakuStyleSettings.load()
    } catch (_err) {
      logger.warn('loadSettings failed, using defaults')
      return DanmakuStyleSettings.getDefault()
    }
  }

  async updateBooleanSetting(key: string, value: boolean): Promise<boolean> {
    try {
      await PreferencesStore.getInstance().setBoolean(key, value)
      const saved = await PreferencesStore.getInstance().getBoolean(key, !value)
      if (saved !== value) {
        logger.warn('updateBooleanSetting verify failed for key=%{public}s, expected=%{public}s, saved=%{public}s',
          key, String(value), String(saved))
        return false
      }
      logger.info('updateBooleanSetting saved: key=%{public}s, value=%{public}s', key, String(saved))
      return true
    } catch (_err) {
      logger.warn('updateBooleanSetting failed for key=%{public}s', key)
      return false
    }
  }

  async updateNumberSetting(key: string, value: number, min: number, max: number, precision: number): Promise<boolean> {
    try {
      const clamped = Math.max(min, Math.min(max, value))
      const precise = precision >= 1 ? Math.round(clamped * precision) / precision : Math.floor(clamped)
      await PreferencesStore.getInstance().setNumber(key, precise)
      const saved = await PreferencesStore.getInstance().getNumber(key, precise)
      return Math.abs(saved - precise) < 0.001
    } catch (_err) {
      logger.warn('updateNumberSetting failed for key=%{public}s', key)
      return false
    }
  }

  async updateStringSetting(key: string, value: string): Promise<boolean> {
    try {
      const truncated = DanmakuStyleSettings.clampText(value)
      await PreferencesStore.getInstance().setString(key, truncated)
      const saved = await PreferencesStore.getInstance().getString(key, '')
      return saved === truncated
    } catch (_err) {
      logger.warn('updateStringSetting failed for key=%{public}s', key)
      return false
    }
  }

  async resetToDefault(): Promise<boolean> {
    try {
      await DanmakuStyleSettings.reset()
      return true
    } catch (_err) {
      logger.warn('resetToDefault failed')
      return false
    }
  }

  validateRegex(text: string): boolean {
    const trimmed = text.trim()
    if (trimmed.length === 0) {
      return true
    }
    try {
      new RegExp(trimmed)
      return true
    } catch (_err) {
      return false
    }
  }

  canToggleSource(targetKey: string, biliBili: boolean, gamer: boolean, danDan: boolean): boolean {
    let enabledCount = 0
    if (biliBili) enabledCount++
    if (gamer) enabledCount++
    if (danDan) enabledCount++
    if (enabledCount <= 1) {
      if (targetKey === DANMAKU_PREFS_KEY_BILIBILI_SOURCE && biliBili) return false
      if (targetKey === DANMAKU_PREFS_KEY_GAMER_SOURCE && gamer) return false
      if (targetKey === DANMAKU_PREFS_KEY_DANDAN_SOURCE && danDan) return false
    }
    return true
  }
}

@Component
struct DanmakuSwitchRow {
  @Link value: boolean
  title: string = ''
  switchEnabled: boolean = true
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .enabled(this.switchEnabled)
        .onChange((isOn: boolean) => {
          this.value = isOn
          this.onToggle(isOn)
        })
      .opacity(this.switchEnabled ? 1.0 : 0.45)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .opacity(this.switchEnabled ? 1.0 : 0.55)
  }
}

@Component
export struct DanmakuSettingsPanelContent {
  @Prop @Watch('onDanmakuEnabledChanged') isDanmakuEnabled: boolean = true
  @Prop isFullScreen: boolean = false
  @Prop @Watch('onSettingsVersionChanged') settingsVersion: number = 0
  @Prop showSourceFilter: boolean = true
  onSetDanmakuEnabled: (enabled: boolean) => void = () => {}
  onPanelClose: () => void = () => {}
  onPauseAutoHide: () => void = () => {}
  onResumeAutoHide: () => void = () => {}

  private controller: DanmakuSettingsController = new DanmakuSettingsController()

  @State panelDanmakuEnabled: boolean = true
  @State displayArea: number = 1.0
  @State scrollDurationSec: number = 8
  @State lineHeight: number = 1.2
  @State followSpeed: boolean = true
  @State deduplication: boolean = false
  @State hideScroll: boolean = false
  @State hideTop: boolean = false
  @State hideBottom: boolean = false
  @State hideColor: boolean = false
  @State danmakuBorder: boolean = true
  @State danmakuBorderSize: number = 1.5
  @State danmakuUseSourceColor: boolean = true
  @State danmakuFontSize: number = 25
  @State danmakuFontWeight: number = 4
  @State danmakuOpacity: number = 1.0
  @State maxLength: number = 100
  @State biliBiliSource: boolean = true
  @State gamerSource: boolean = true
  @State danDanSource: boolean = true
  @State blockKeywordsEnabled: boolean = true
  @State blockKeywordsText: string = ''
  @State blockRegexEnabled: boolean = true
  @State blockRegexText: string = ''
  @State danmakuTimeOffset: number = 0
  @State massiveMode: boolean = false
  @State isRegexValid: boolean = true
  @State isResetting: boolean = false


  aboutToAppear(): void {
    this.panelDanmakuEnabled = this.isDanmakuEnabled
    this.loadAllSettings()
  }

  aboutToDisappear(): void {
  }

  private onDanmakuEnabledChanged(): void {
    this.panelDanmakuEnabled = this.isDanmakuEnabled
  }

  private onSettingsVersionChanged(): void {
    this.loadAllSettings()
  }

  private async loadAllSettings(): Promise<void> {
    const settings = await this.controller.loadSettings()
    this.displayArea = settings.displayArea
    this.scrollDurationSec = settings.scrollDurationSec
    this.lineHeight = settings.lineHeight
    this.followSpeed = settings.followSpeed
    this.deduplication = settings.deduplication
    this.hideScroll = settings.hideScroll
    this.hideTop = settings.hideTop
    this.hideBottom = settings.hideBottom
    this.hideColor = settings.hideColor
    this.danmakuBorder = settings.border
    this.danmakuBorderSize = settings.borderSize
    this.danmakuUseSourceColor = settings.useSourceColor
    this.danmakuFontSize = settings.fontSize
    this.danmakuFontWeight = settings.fontWeight
    this.danmakuOpacity = settings.opacity
    this.maxLength = settings.maxLength
    this.biliBiliSource = settings.biliBiliSource
    this.gamerSource = settings.gamerSource
    this.danDanSource = settings.danDanSource
    this.blockKeywordsEnabled = settings.blockKeywordsEnabled
    this.blockKeywordsText = settings.blockKeywordsText
    this.blockRegexEnabled = settings.blockRegexEnabled
    this.blockRegexText = settings.blockRegexText
    this.danmakuTimeOffset = settings.danmakuTimeOffset
    this.massiveMode = settings.massiveMode
    this.isRegexValid = this.controller.validateRegex(this.blockRegexText)
    logger.info('弹幕设置面板加载: color=%{public}s, hideColor=%{public}s, hideScroll=%{public}s, hideTop=%{public}s, hideBottom=%{public}s',
      String(this.danmakuUseSourceColor), String(this.hideColor), String(this.hideScroll), String(this.hideTop),
      String(this.hideBottom))
  }

  build() {
    Column() {
      Row() {
        Text('弹幕设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onPanelClose()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column() {
          this.DanmakuStatusSection()
          this.DisplayBasicSection()
          this.DisplayAdvancedSection()
          this.StyleSection()
          if (this.showSourceFilter) {
            this.SourceFilterSection()
          }
          this.FilterSection()
          Column().height(40)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private DanmakuStatusSection(): void {
    Column() {
      this.SectionTitle('弹幕')
      Column() {
        DanmakuSwitchRow({
          title: '弹幕总开关',
          value: $panelDanmakuEnabled,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.onSetDanmakuEnabled(value)
          }
        })
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private DisplayBasicSection(): void {
    Column() {
      this.SectionTitle('弹幕显示 · 基础')
      Column() {
        this.SliderRow('显示区域', 'displayArea', 0.25, 1, 0.25, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.displayArea = value
            } else {
              this.displayArea = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_DISPLAY_AREA, value, 0.25, 1, 4)
            }
          })
        this.ItemDivider()
        this.SliderRow('滚动时长', 'scrollDurationSec', 4, 12, 0.5, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.scrollDurationSec = value
            } else {
              this.scrollDurationSec = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_SCROLL_DURATION, value, 4, 12, 2)
            }
          })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '跟随视频倍速',
          value: $followSpeed,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_FOLLOW_SPEED, value, !value, (value: boolean) => {
              this.followSpeed = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '弹幕去重',
          value: $deduplication,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_DEDUPLICATION, value, !value, (value: boolean) => {
              this.deduplication = value
            })
          }
        })
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private DisplayAdvancedSection(): void {
    Column() {
      this.SectionTitle('弹幕显示 · 高级')
      Column() {
        this.SliderRow('弹幕行高', 'lineHeight', 1.0, 2.5, 0.1, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.lineHeight = value
            } else {
              this.lineHeight = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_LINE_HEIGHT, value, 1.0, 2.5, 10)
            }
          })
        this.ItemDivider()
        this.SliderRow('时间轴偏移', 'danmakuTimeOffset', -60, 60, 0.25, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.danmakuTimeOffset = value
            } else {
              this.danmakuTimeOffset = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_TIME_OFFSET, value, -60, 60, 4)
            }
          })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '海量弹幕',
          value: $massiveMode,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_MASSIVE_MODE, value, !value, (value: boolean) => {
              this.massiveMode = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '隐藏滚动弹幕',
          value: $hideScroll,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_HIDE_SCROLL, value, !value, (value: boolean) => {
              this.hideScroll = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '隐藏顶部弹幕',
          value: $hideTop,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_HIDE_TOP, value, !value, (value: boolean) => {
              this.hideTop = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '隐藏底部弹幕',
          value: $hideBottom,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_HIDE_BOTTOM, value, !value, (value: boolean) => {
              this.hideBottom = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '隐藏彩色弹幕',
          value: $hideColor,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_HIDE_COLOR, value, !value, (value: boolean) => {
              this.hideColor = value
            })
          }
        })
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private StyleSection(): void {
    Column() {
      Row() {
        Text('弹幕样式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Text('恢复默认')
          .fontSize(12)
          .fontColor($r('app.color.accent_blue'))
          .onClick(() => {
            this.onResetToDefault()
          })
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 18, bottom: 6 })

      Column() {
        DanmakuSwitchRow({
          title: '弹幕描边',
          value: $danmakuBorder,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_BORDER, value, !value, (value: boolean) => {
              this.danmakuBorder = value
            })
          }
        })
        this.ItemDivider()
        this.SliderRow('描边粗细', 'danmakuBorderSize', 0.1, 3, 0.1, this.danmakuBorder,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.danmakuBorderSize = value
            } else {
              this.danmakuBorderSize = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_BORDER_SIZE, value, 0.1, 3, 10)
            }
          })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '弹幕颜色',
          value: $danmakuUseSourceColor,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_COLOR, value, !value, (value: boolean) => {
              this.danmakuUseSourceColor = value
            })
          }
        })
        this.ItemDivider()
        this.SliderRow('字体大小', 'danmakuFontSize', 10, 48, 1, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.danmakuFontSize = value
            } else {
              this.danmakuFontSize = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_FONT_SIZE, value, 10, 48, 1)
            }
          })
        this.ItemDivider()
        this.SliderRow('字体字重', 'danmakuFontWeight', 1, 9, 1, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.danmakuFontWeight = value
            } else {
              this.danmakuFontWeight = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_FONT_WEIGHT, value, 1, 9, 1)
            }
          })
        this.ItemDivider()
        this.SliderRow('不透明度', 'danmakuOpacity', 0.1, 1, 0.05, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.danmakuOpacity = value
            } else {
              this.danmakuOpacity = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_OPACITY, value, 0.1, 1, 20)
            }
          })
        this.ItemDivider()
        this.SliderRow('最大长度', 'maxLength', 20, 200, 10, true,
          (value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Moving) {
              this.maxLength = value
            } else {
              this.maxLength = value
              this.controller.updateNumberSetting(DANMAKU_PREFS_KEY_MAX_LENGTH, value, 20, 200, 1)
            }
          })
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private SourceFilterSection(): void {
    Column() {
      this.SectionTitle('来源过滤')
      Column() {
        DanmakuSwitchRow({
          title: 'BiliBili',
          value: $biliBiliSource,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            if (!value && !this.controller.canToggleSource(DANMAKU_PREFS_KEY_BILIBILI_SOURCE,
              !value, this.gamerSource, this.danDanSource)) {
              this.biliBiliSource = !value
              return
            }
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_BILIBILI_SOURCE, value, !value, (value: boolean) => {
              this.biliBiliSource = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: 'Gamer',
          value: $gamerSource,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            if (!value && !this.controller.canToggleSource(DANMAKU_PREFS_KEY_GAMER_SOURCE,
              this.biliBiliSource, !value, this.danDanSource)) {
              this.gamerSource = !value
              return
            }
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_GAMER_SOURCE, value, !value, (value: boolean) => {
              this.gamerSource = value
            })
          }
        })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '弹弹Play',
          value: $danDanSource,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            if (!value && !this.controller.canToggleSource(DANMAKU_PREFS_KEY_DANDAN_SOURCE,
              this.biliBiliSource, this.gamerSource, !value)) {
              this.danDanSource = !value
              return
            }
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_DANDAN_SOURCE, value, !value, (value: boolean) => {
              this.danDanSource = value
            })
          }
        })
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private FilterSection(): void {
    Column() {
      this.SectionTitle('弹幕屏蔽')
      Column() {
        DanmakuSwitchRow({
          title: '屏蔽词',
          value: $blockKeywordsEnabled,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED, value, !value,
              (value: boolean) => {
                this.blockKeywordsEnabled = value
              })
          }
        })
        TextInput({ placeholder: '用空格、逗号或分号分隔', text: this.blockKeywordsText })
          .height(40)
          .fontSize(13)
          .enabled(this.blockKeywordsEnabled)
          .opacity(this.blockKeywordsEnabled ? 1.0 : 0.4)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .margin({ left: 16, right: 16, bottom: 8 })
          .onChange((value: string) => {
            this.blockKeywordsText = value
            this.controller.updateStringSetting(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS, value)
          })
        this.ItemDivider()
        DanmakuSwitchRow({
          title: '正则屏蔽',
          value: $blockRegexEnabled,
          switchEnabled: true,
          onToggle: (value: boolean) => {
            this.saveBooleanSetting(DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED, value, !value,
              (value: boolean) => {
                this.blockRegexEnabled = value
              })
          }
        })
        TextInput({ placeholder: '输入一个正则表达式', text: this.blockRegexText })
          .height(40)
          .fontSize(13)
          .enabled(this.blockRegexEnabled)
          .opacity(this.blockRegexEnabled ? 1.0 : 0.4)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .margin({ left: 16, right: 16, bottom: 4 })
          .onChange((value: string) => {
            this.blockRegexText = value
            this.isRegexValid = this.controller.validateRegex(value)
            this.controller.updateStringSetting(DANMAKU_PREFS_KEY_BLOCK_REGEX, value)
          })

        if (this.blockRegexEnabled && this.blockRegexText.length > 0 && !this.isRegexValid) {
          Text('正则表达式无效，将在播放时忽略')
            .fontSize(12)
            .fontColor($r('app.color.status_warning'))
            .width('100%')
            .padding({ left: 16, bottom: 8 })
        }
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private ItemDivider(): void {
    Row() {
      Blank()
        .width(16)
      Divider()
        .layoutWeight(1)
        .color($r('app.color.divider_color'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .padding({ right: 16 })
  }

  @Builder
  private SectionTitle(title: string): void {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })
  }

  @Builder
  private SliderRow(title: string, stateKey: string, min: number, max: number,
    step: number, enabled: boolean, onChanged: (value: number, mode: SliderChangeMode) => void): void {
    Row() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(enabled ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .layoutWeight(1)

      Text(this.getSliderValueText(stateKey))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(enabled ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(12)
        .backgroundColor(enabled ? $r('app.color.episode_item_selected_bg') : $r('app.color.button_ghost_bg'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 0 })

    Slider({ value: this.getSliderValue(stateKey), min: min, max: max, step: step })
      .width('100%')
      .height(24)
      .padding({ left: 16, right: 16 })
      .enabled(enabled)
      .opacity(enabled ? 1.0 : 0.35)
      .trackColor($r('app.color.divider_color'))
      .selectedColor($r('app.color.accent_blue'))
      .onChange((sliderValue: number, mode: SliderChangeMode) => {
        this.setSliderValue(stateKey, sliderValue)
        onChanged(sliderValue, mode)
      })
  }

  private getSliderValue(stateKey: string): number {
    if (stateKey === 'displayArea') return this.displayArea
    if (stateKey === 'scrollDurationSec') return this.scrollDurationSec
    if (stateKey === 'lineHeight') return this.lineHeight
    if (stateKey === 'danmakuBorderSize') return this.danmakuBorderSize
    if (stateKey === 'danmakuFontSize') return this.danmakuFontSize
    if (stateKey === 'danmakuFontWeight') return this.danmakuFontWeight
    if (stateKey === 'danmakuOpacity') return this.danmakuOpacity
    if (stateKey === 'maxLength') return this.maxLength
    if (stateKey === 'danmakuTimeOffset') return this.danmakuTimeOffset
    return 0
  }

  private setSliderValue(stateKey: string, value: number): void {
    if (stateKey === 'displayArea') this.displayArea = value
    if (stateKey === 'scrollDurationSec') this.scrollDurationSec = value
    if (stateKey === 'lineHeight') this.lineHeight = value
    if (stateKey === 'danmakuBorderSize') this.danmakuBorderSize = value
    if (stateKey === 'danmakuFontSize') this.danmakuFontSize = value
    if (stateKey === 'danmakuFontWeight') this.danmakuFontWeight = value
    if (stateKey === 'danmakuOpacity') this.danmakuOpacity = value
    if (stateKey === 'maxLength') this.maxLength = value
    if (stateKey === 'danmakuTimeOffset') this.danmakuTimeOffset = value
  }

  private getSliderValueText(stateKey: string): string {
    if (stateKey === 'displayArea') return `${Math.round(this.displayArea * 100)}%`
    if (stateKey === 'scrollDurationSec') return `${this.scrollDurationSec.toFixed(1)} 秒`
    if (stateKey === 'lineHeight') return this.lineHeight.toFixed(1)
    if (stateKey === 'danmakuBorderSize') return this.danmakuBorderSize.toFixed(1)
    if (stateKey === 'danmakuFontSize') return `${Math.floor(this.danmakuFontSize)}`
    if (stateKey === 'danmakuFontWeight') return `${Math.floor(this.danmakuFontWeight)}`
    if (stateKey === 'danmakuOpacity') return `${Math.round(this.danmakuOpacity * 100)}%`
    if (stateKey === 'maxLength') return `${Math.floor(this.maxLength)}`
    if (stateKey === 'danmakuTimeOffset') {
      if (this.danmakuTimeOffset === 0) return '无偏移'
      if (this.danmakuTimeOffset > 0) return `延后${this.danmakuTimeOffset.toFixed(2)}秒`
      return `提前${Math.abs(this.danmakuTimeOffset).toFixed(2)}秒`
    }
    return ''
  }

  private async onResetToDefault(): Promise<void> {
    this.isResetting = true
    const success = await this.controller.resetToDefault()
    if (success) {
      await this.loadAllSettings()
    }
    this.isResetting = false
  }

  private saveBooleanSetting(key: string, value: boolean, rollbackValue: boolean,
    applyValue: (value: boolean) => void): void {
    this.controller.updateBooleanSetting(key, value).then((ok: boolean) => {
      if (!ok) {
        applyValue(rollbackValue)
      }
    })
  }
}
