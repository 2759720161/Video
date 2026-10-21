import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { PreferencesStore } from '../../store/PreferencesStore'
import {
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  BOTTOM_TAB_SHOW_ANIMATION_DEFAULT,
  PREFS_KEY_BOTTOM_TAB_AUTO_HIDE,
  PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION
} from '../../utils/BottomTabAutoHide'
import {
  getBottomSpacerHeight, getTopSpacerHeight, buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_ADAPTIVE, HDS_MATERIAL_LEVEL_DEFAULT, HDS_MATERIAL_LEVEL_EXQUISITE,
  HDS_MATERIAL_LEVEL_GENTLE, HDS_MATERIAL_LEVEL_SMOOTH, PREFS_KEY_HDS_MATERIAL_LEVEL,
  IMMERSIVE_STYLE_DEFAULT, IMMERSIVE_STYLE_THIN, IMMERSIVE_STYLE_ULTRA_THIN,
  IMMERSIVE_STYLE_REGULAR, IMMERSIVE_STYLE_THICK, IMMERSIVE_STYLE_ULTRA_THICK,
  PREFS_KEY_IMMERSIVE_MATERIAL_STYLE, getImmersiveMaterialStyleLabel
} from '../../utils/HdsPageStyle'
import { DetailSelectMaterialModifier } from '../../utils/DetailMaterial'

@Entry
@Component
struct AppearanceSettingsPage {
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabShowAnimation') bottomTabAnimation: boolean = BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @State colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    PreferencesStore.getInstance().getNumber('colorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET).then((value: number) => {
      this.colorMode = value
    })
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          this.AppearanceCard()
          this.AnimationCard()
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }.width('100%').padding({ left: 12, right: 12 }).alignItems(HorizontalAlign.Start).constraintSize({ minHeight: '100%' })
      }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('外观动效', this.materialLevel)).bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder private AppearanceCard(): void {
    Column() {
      this.SectionHeader('外观')
      Column() {
        Row() {
          this.Icon($r('sys.symbol.moon'))
          this.Title('深色模式')
          this.ThemePicker()
        }.width('100%').height(64).padding({ left: 16, right: 16 })
        Divider().color($r('app.color.divider_color')).margin({ left: 62 })
        Row() {
          this.Icon($r('sys.symbol.wand_and_stars'))
          this.Title('沉浸光感等级')
          this.MaterialPicker()
        }.width('100%').height(64).padding({ left: 16, right: 16 })
        Divider().color($r('app.color.divider_color')).margin({ left: 62 })
        Row() {
          this.Icon($r('sys.symbol.wand_and_stars'))
          this.Title('材质厚度')
          this.MaterialThicknessPicker()
        }.width('100%').height(64).padding({ left: 16, right: 16 })
      }.width('100%').borderRadius(12).clip(true).backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') }).shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
      Text('光感等级调整页面导航栏；材质厚度调整详情弹层和播放、选择按钮的通透程度。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 4 })
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder private AnimationCard(): void {
    Column() {
      this.SectionHeader('动效')
      Column() {
        Row() {
          this.Icon($r('sys.symbol.arrow_down_right_and_arrow_up_left'))
          this.Title('滑动隐藏底栏')
          Toggle({ type: ToggleType.Switch, isOn: this.bottomTabAutoHide }).selectedColor($r('app.color.accent_blue'))
            .onChange((value: boolean) => this.setBottomTabAutoHide(value))
        }.width('100%').height(64).padding({ left: 16, right: 16 })
        Divider().color($r('app.color.divider_color')).margin({ left: 62 })
        Row() {
          this.Icon($r('sys.symbol.layer'))
          this.Title('底栏显示动画')
          Toggle({ type: ToggleType.Switch, isOn: this.bottomTabAnimation }).selectedColor($r('app.color.accent_blue'))
            .onChange((value: boolean) => this.setBottomTabAnimation(value))
        }.width('100%').height(64).padding({ left: 16, right: 16 })
      }.width('100%').borderRadius(12).clip(true).backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') }).shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder private SectionHeader(title: string): void {
    Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 4, top: 12, bottom: 8 })
  }
  @Builder private Icon(icon: Resource): void { SymbolGlyph(icon).fontSize(24).fontColor([$r('app.color.accent_blue')]).width(34).margin({ right: 12 }) }
  @Builder private Title(title: string): void {
    Column() {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }
  @Builder private ThemePicker(): void {
    Select([{ value: '跟随系统' }, { value: '浅色' }, { value: '深色' }])
      .selected(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? 1 : (this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 2 : 0))
      .value(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? '浅色' : (this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '深色' : '跟随系统'))
      .font({ size: 15, weight: FontWeight.Medium })
      .attributeModifier(new DetailSelectMaterialModifier(this.materialThickness))
      .onSelect((index: number) => this.setColorMode(index === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : (index === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)))
  }
  @Builder private MaterialPicker(): void {
    Select([{ value: '精致' }, { value: '柔和' }, { value: '平滑' }, { value: '自适应' }])
      .selected(this.getMaterialIndex()).value(this.getMaterialLabel()).font({ size: 15, weight: FontWeight.Medium })
      .attributeModifier(new DetailSelectMaterialModifier(this.materialThickness))
      .onSelect((index: number) => this.setMaterialLevel(index === 1 ? HDS_MATERIAL_LEVEL_GENTLE : (index === 2 ? HDS_MATERIAL_LEVEL_SMOOTH : (index === 3 ? HDS_MATERIAL_LEVEL_ADAPTIVE : HDS_MATERIAL_LEVEL_EXQUISITE))))
  }
  @Builder private MaterialThicknessPicker(): void {
    Select([
      { value: getImmersiveMaterialStyleLabel(IMMERSIVE_STYLE_ULTRA_THIN) },
      { value: getImmersiveMaterialStyleLabel(IMMERSIVE_STYLE_THIN) },
      { value: getImmersiveMaterialStyleLabel(IMMERSIVE_STYLE_REGULAR) },
      { value: getImmersiveMaterialStyleLabel(IMMERSIVE_STYLE_THICK) },
      { value: getImmersiveMaterialStyleLabel(IMMERSIVE_STYLE_ULTRA_THICK) }
    ])
      .selected(this.getMaterialThicknessIndex()).value(this.getMaterialThicknessLabel())
      .font({ size: 15, weight: FontWeight.Medium })
      .attributeModifier(new DetailSelectMaterialModifier(this.materialThickness))
      .onSelect((index: number) => this.setMaterialThickness(
        index === 0 ? IMMERSIVE_STYLE_ULTRA_THIN : index === 1 ? IMMERSIVE_STYLE_THIN :
          index === 2 ? IMMERSIVE_STYLE_REGULAR : index === 3 ? IMMERSIVE_STYLE_THICK :
            IMMERSIVE_STYLE_ULTRA_THICK))
  }

  private async setColorMode(mode: number): Promise<void> {
    this.colorMode = mode
    try { const context = getContext(this) as common.UIAbilityContext; context.getApplicationContext().setColorMode(mode); await PreferencesStore.getInstance().setNumber('colorMode', mode) } catch (_) {}
  }
  private async setBottomTabAutoHide(value: boolean): Promise<void> {
    this.bottomTabAutoHide = value
    AppStorage.setOrCreate('bottomTabAutoHide', value)
    if (!value) {
      AppStorage.setOrCreate('bottomTabOffset', 0)
    }
    await PreferencesStore.getInstance().setBoolean(PREFS_KEY_BOTTOM_TAB_AUTO_HIDE, value)
  }
  private async setBottomTabAnimation(value: boolean): Promise<void> { this.bottomTabAnimation = value; AppStorage.setOrCreate('bottomTabShowAnimation', value); await PreferencesStore.getInstance().setBoolean(PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION, value) }
  private async setMaterialLevel(value: string): Promise<void> { this.materialLevel = value; AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, value); await PreferencesStore.getInstance().setString(PREFS_KEY_HDS_MATERIAL_LEVEL, value) }
  private async setMaterialThickness(value: string): Promise<void> { this.materialThickness = value; AppStorage.setOrCreate(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE, value); await PreferencesStore.getInstance().setString(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE, value) }
  private getMaterialIndex(): number { return this.materialLevel === HDS_MATERIAL_LEVEL_GENTLE ? 1 : (this.materialLevel === HDS_MATERIAL_LEVEL_SMOOTH ? 2 : (this.materialLevel === HDS_MATERIAL_LEVEL_ADAPTIVE ? 3 : 0)) }
  private getMaterialLabel(): string { return this.getMaterialIndex() === 1 ? '柔和' : (this.getMaterialIndex() === 2 ? '平滑' : (this.getMaterialIndex() === 3 ? '自适应' : '精致')) }
  private getMaterialThicknessIndex(): number {
    if (this.materialThickness === IMMERSIVE_STYLE_ULTRA_THIN) return 0
    if (this.materialThickness === IMMERSIVE_STYLE_THIN) return 1
    if (this.materialThickness === IMMERSIVE_STYLE_THICK) return 3
    if (this.materialThickness === IMMERSIVE_STYLE_ULTRA_THICK) return 4
    return 2
  }
  private getMaterialThicknessLabel(): string {
    return getImmersiveMaterialStyleLabel(this.materialThickness)
  }
}
