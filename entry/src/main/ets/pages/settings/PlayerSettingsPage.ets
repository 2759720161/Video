import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { PreferencesStore } from '../../store/PreferencesStore'
import { PLAYER_AUTO_PIP_DEFAULT, PREFS_KEY_PLAYER_AUTO_PIP } from '../../utils/PlayerAutoPiP'
import { PLAYER_AUTO_NEXT_DEFAULT, PREFS_KEY_PLAYER_AUTO_NEXT } from '../../utils/PlayerAutoNext'
import {
  PLAYER_DEFAULT_SPEED,
  PLAYER_SEEK_SECONDS_DEFAULT,
  PREFS_KEY_PLAYER_DEFAULT_SPEED,
  PREFS_KEY_PLAYER_SEEK_SECONDS,
  normalizePlayerSpeed,
  normalizeSeekSeconds
} from '../../utils/PlayerPlaybackPreferences'
import { getBottomSpacerHeight, getTopSpacerHeight, buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct PlayerSettingsPage {
  @StorageLink(PREFS_KEY_PLAYER_AUTO_PIP) autoPiP: boolean = PLAYER_AUTO_PIP_DEFAULT
  @StorageLink(PREFS_KEY_PLAYER_AUTO_NEXT) autoNext: boolean = PLAYER_AUTO_NEXT_DEFAULT
  @StorageLink(PREFS_KEY_PLAYER_DEFAULT_SPEED) defaultSpeed: number = PLAYER_DEFAULT_SPEED
  @StorageLink(PREFS_KEY_PLAYER_SEEK_SECONDS) seekSeconds: number = PLAYER_SEEK_SECONDS_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  private scroller: Scroller = new Scroller()

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
        Column() {
            this.ToggleRow($r('sys.symbol.template'), '自动开启画中画', '离开播放页时自动转入画中画', this.autoPiP, (value: boolean) => this.setAutoPiP(value))
            Divider().color($r('app.color.divider_color')).margin({ left: 62 })
            this.ToggleRow($r('sys.symbol.play_fill'), '自动播放下一视频', '当前播放列表有下一项时自动继续播放', this.autoNext, (value: boolean) => this.setBoolean(PREFS_KEY_PLAYER_AUTO_NEXT, value))
            Divider().color($r('app.color.divider_color')).margin({ left: 62 })
            this.SelectRow($r('sys.symbol.play_round_rectangle'), '默认播放速度', '新视频开始播放时使用', this.speedLabel(), [{ value: '0.5×' }, { value: '0.75×' }, { value: '1.0×' }, { value: '1.25×' }, { value: '1.5×' }, { value: '2.0×' }], this.speedIndex(), (index: number) => this.setDefaultSpeed([0.5, 0.75, 1.0, 1.25, 1.5, 2.0][index]))
            Divider().color($r('app.color.divider_color')).margin({ left: 62 })
            this.SeekDurationSelectRow()
          }
          .width('100%').borderRadius(12).clip(true).backgroundColor($r('app.color.card_background'))
          .border({ width: 0.5, color: $r('app.color.card_specular_border') })
          .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }.width('100%').padding({ left: 12, right: 12 }).alignItems(HorizontalAlign.Start).constraintSize({ minHeight: '100%' })
      }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('播放器', this.hdsMaterialLevel)).bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder ToggleRow(icon: Resource, title: string, summary: string, value: boolean, onChange: (value: boolean) => void): void {
    Row() {
      SymbolGlyph(icon).fontSize(24).fontColor([$r('app.color.accent_blue')]).width(34).margin({ right: 12 })
      Column() {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(summary).fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 3 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor($r('app.color.accent_blue')).onChange(onChange)
    }.width('100%').height(64).padding({ left: 16, right: 16 })
  }

  @Builder SelectRow(icon: Resource, title: string, summary: string, selected: string, options: Array<SelectOption>, index: number, onSelect: (index: number) => void): void {
    Row() {
      SymbolGlyph(icon).fontSize(24).fontColor([$r('app.color.accent_blue')]).width(34).margin({ right: 12 })
      Column() {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(summary).fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 3 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Select(options).selected(index).value(selected).font({ size: 14, weight: FontWeight.Medium }).onSelect(onSelect)
    }.width('100%').height(64).padding({ left: 16, right: 16 })
  }

  @Builder SeekDurationSelectRow(): void {
    if (normalizeSeekSeconds(this.seekSeconds) === 10) {
      this.SelectRow($r('sys.symbol.goforward_10'), '快进与快退时长', '手势和控制按钮的跳转时长', this.seekSeconds + ' 秒', [{ value: '10 秒' }, { value: '15 秒' }, { value: '30 秒' }], this.seekIndex(), (index: number) => this.setSeekSeconds([10, 15, 30][index]))
    } else if (normalizeSeekSeconds(this.seekSeconds) === 30) {
      this.SelectRow($r('sys.symbol.goforward_30'), '快进与快退时长', '手势和控制按钮的跳转时长', this.seekSeconds + ' 秒', [{ value: '10 秒' }, { value: '15 秒' }, { value: '30 秒' }], this.seekIndex(), (index: number) => this.setSeekSeconds([10, 15, 30][index]))
    } else {
      this.SelectRow($r('sys.symbol.goforward_15'), '快进与快退时长', '手势和控制按钮的跳转时长', this.seekSeconds + ' 秒', [{ value: '10 秒' }, { value: '15 秒' }, { value: '30 秒' }], this.seekIndex(), (index: number) => this.setSeekSeconds([10, 15, 30][index]))
    }
  }

  private async setAutoPiP(value: boolean): Promise<void> {
    this.autoPiP = value
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, value)
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_PLAYER_AUTO_PIP, value)
  }

  private async setBoolean(key: string, value: boolean): Promise<void> {
    AppStorage.setOrCreate(key, value)
    await PreferencesStore.getInstance().setBoolean(key, value)
  }

  private async setDefaultSpeed(value: number): Promise<void> {
    const normalized = normalizePlayerSpeed(value)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_DEFAULT_SPEED, normalized)
    await PreferencesStore.getInstance().setNumber(PREFS_KEY_PLAYER_DEFAULT_SPEED, normalized)
  }

  private async setSeekSeconds(value: number): Promise<void> {
    const normalized = normalizeSeekSeconds(value)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_SEEK_SECONDS, normalized)
    await PreferencesStore.getInstance().setNumber(PREFS_KEY_PLAYER_SEEK_SECONDS, normalized)
  }

  private speedLabel(): string { return this.defaultSpeed.toFixed(this.defaultSpeed % 1 === 0 ? 1 : 2) + '×' }
  private speedIndex(): number { const values: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]; return values.indexOf(normalizePlayerSpeed(this.defaultSpeed)) }
  private seekIndex(): number { const values: number[] = [10, 15, 30]; return values.indexOf(normalizeSeekSeconds(this.seekSeconds)) }
}
