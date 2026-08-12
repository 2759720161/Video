import { promptAction, router } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { commentManager } from '@kit.AppGalleryKit'
import { common } from '@kit.AbilityKit'
import { APP_VERSION } from '../../constants/AppVersion'
import {
  getBottomSpacerHeight,
  getTopSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

@Component
export struct SettingsPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  private scroller: Scroller = new Scroller()

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          this.SettingsSection()
          this.AboutSection()
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%').hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12 })
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('设置', this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder private SettingsSection(): void {
    Column() {
      this.SectionHeader('播放器')
      Column() {
        this.RouteItem($r('sys.symbol.play_round_rectangle'), '播放', '全屏、画中画与播放行为', 'pages/settings/PlayerSettingsPage')
        this.Divider()
        this.RouteItem($r('sys.symbol.doc_text'), '字幕', '显示、字号、位置与时间偏移', 'pages/settings/SubtitleSettingsPage')
        this.Divider()
        this.RouteItem($r('sys.symbol.moon'), '外观动效', '主题、沉浸光感与底栏动效', 'pages/settings/AppearanceSettingsPage')
      }
      .width('100%').borderRadius(12).clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder private AboutSection(): void {
    Column() {
      this.SectionHeader('关于')
      Column() {
        this.InfoItem($r('sys.symbol.info_circle'), '版本信息', `当前版本 ${APP_VERSION}`)
        this.Divider()
        this.RouteItem($r('sys.symbol.info_circle'), '三方库与服务', '查看本应用使用的系统能力与服务', 'pages/settings/ThirdPartyPage')
        this.Divider()
        this.ActionItem($r('sys.symbol.star_fill'), '给个好评', '在应用市场评分与评论', () => this.openReview())
      }
      .width('100%').borderRadius(12).clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder private SectionHeader(title: string): void {
    Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
      .width('100%').padding({ left: 4, top: 12, bottom: 8 })
  }

  @Builder private Divider(): void {
    Divider().color($r('app.color.divider_color')).margin({ left: 62 })
  }

  @Builder private RouteItem(icon: Resource, title: string, desc: string, url: string): void {
    this.ActionItem(icon, title, desc, () => {
      router.pushUrl({ url: url })
    })
  }

  @Builder private InfoItem(icon: Resource, title: string, desc: string): void {
    Row() {
      this.SettingIcon(icon)
      this.SettingTitle(title, desc)
    }.width('100%').height(72).padding({ left: 16, right: 16 })
  }

  @Builder private ActionItem(icon: Resource, title: string, desc: string, action: () => void): void {
    Row() {
      this.SettingIcon(icon)
      this.SettingTitle(title, desc)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%').height(72).padding({ left: 16, right: 16 }).borderRadius(12)
    .onClick(action)
    .stateStyles({ pressed: { .backgroundColor($r('app.color.category_menu_item_selected')) }, normal: { .backgroundColor(Color.Transparent) } })
  }

  @Builder private SettingIcon(icon: Resource): void {
    SymbolGlyph(icon).fontSize(24).fontColor([$r('app.color.accent_blue')]).width(34).margin({ right: 12 })
  }

  @Builder private SettingTitle(title: string, desc: string): void {
    Column() {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(1)
      Text(desc).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 3 })
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  private async openReview(): Promise<void> {
    try {
      await commentManager.showCommentDialog(getContext(this) as common.UIAbilityContext)
    } catch (_) {
      promptAction.showToast({ message: '当前设备未提供应用市场评分服务' })
    }
  }
}
