import { LocalPage } from './local/LocalPage'
import { SettingsPage } from './settings/SettingsPage'
import { HdsAnimationMode, HdsTabs, HdsTabsController, HdsTabsFloatingStyle } from '@kit.UIDesignKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL, buildAdaptiveMaterialEffect } from '../utils/HdsPageStyle'
import {
  BOTTOM_TAB_ANIMATION_HIDDEN_KEY,
  BOTTOM_TAB_ANIMATION_TOKEN_KEY,
  BOTTOM_TAB_AUTO_HIDE_DEFAULT
} from '../utils/BottomTabAutoHide'

@Entry
@Component
struct Index {
  @StorageLink('currentTab') currentTab: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('bottomTabAutoHide') @Watch('onBottomTabAutoHideChanged')
  bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabShowAnimation') bottomTabShowAnimation: boolean = true
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink(BOTTOM_TAB_ANIMATION_TOKEN_KEY) @Watch('onBottomTabAnimationTokenChanged')
  bottomTabAnimationToken: number = 0
  @StorageLink(BOTTOM_TAB_ANIMATION_HIDDEN_KEY) bottomTabAnimationHidden: boolean = false
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  private tabsController: HdsTabsController = new HdsTabsController()
  private bottomTabControllerHidden: boolean = false

  build() {
    Column() {
      HdsTabs({ controller: this.tabsController, index: this.currentTab }) {
        TabContent() {
          LocalPage({ isActive: this.currentTab === 0 })
        }
        .tabBar(this.tabStyle($r('sys.symbol.folder'), $r('sys.symbol.folder_fill'), '媒体库'))

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.tabStyle($r('sys.symbol.gearshape'), $r('sys.symbol.gearshape'), '设置'))
      }
      .barOverlap(true)
      .vertical(false)
      .scrollable(false)
      .barPosition(BarPosition.End)
      .barHeight(54)
      .barFloatingStyle(this.floatingStyle())
      .animationDuration(300)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentTab = index
        this.bottomTabOffset = 0
        this.applyBottomTabVisibilityAnimation(false)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private onBottomTabAutoHideChanged(): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      this.applyBottomTabVisibilityAnimation(false, true)
    }
  }

  private onBottomTabAnimationTokenChanged(): void {
    if (this.bottomTabAnimationToken === 0) {
      return
    }
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      this.applyBottomTabVisibilityAnimation(false, true)
      return
    }
    this.applyBottomTabVisibilityAnimation(this.bottomTabAnimationHidden)
  }

  private applyBottomTabVisibilityAnimation(hidden: boolean, forceShow: boolean = false): void {
    try {
      this.bottomTabAnimationHidden = hidden
      if (hidden) {
        this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)
        this.bottomTabControllerHidden = true
      } else {
        if (!forceShow && !this.bottomTabControllerHidden && !this.bottomTabShowAnimation) {
          return
        }
        this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
        this.bottomTabControllerHidden = false
      }
    } catch (_) {
      // The controller is not attached until HdsTabs has completed its first layout.
    }
  }

  private floatingStyle(): HdsTabsFloatingStyle {
    return {
      barWidth: { smallWidth: 133, mediumWidth: 152, largeWidth: 172 },
      barBottomMargin: this.bottomSafeHeight + 26,
      gradientMask: { maskColor: $r('app.color.hds_tab_gradient_mask'), maskHeight: 108 },
      thermoCtrl: true,
      systemMaterialEffect: buildAdaptiveMaterialEffect(this.hdsMaterialLevel)
    }
  }

  private tabStyle(normal: Resource, selected: Resource, title: string): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(normal),
      selected: new SymbolGlyphModifier(selected)
    }, title)
  }
}
