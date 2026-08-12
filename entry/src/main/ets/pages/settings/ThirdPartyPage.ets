import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { getBottomSpacerHeight, getTopSpacerHeight, buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct ThirdPartyPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  private scroller: Scroller = new Scroller()

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          this.ServiceCard()
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }.width('100%').padding({ left: 12, right: 12 }).alignItems(HorizontalAlign.Start).constraintSize({ minHeight: '100%' })
      }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('三方库与服务', this.hdsMaterialLevel)).bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder private ServiceCard(): void {
    Column() {
      this.Item('AVPlayer', 'HarmonyOS Media Kit，本地视频播放')
      Divider().color($r('app.color.divider_color')).margin({ left: 16 })
      this.Item('文件选择器', 'HarmonyOS Core File Kit，本地媒体文件选择')
      Divider().color($r('app.color.divider_color')).margin({ left: 16 })
      this.Item('关系型数据库', 'HarmonyOS ArkData，本地播放记录存储')
      Divider().color($r('app.color.divider_color')).margin({ left: 16 })
      this.Item('应用市场服务', 'HarmonyOS AppGallery Kit，应用评分与评论')
    }
    .width('100%').borderRadius(12).clip(true).backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
  }

  @Builder private Item(title: string, summary: string): void {
    Column() {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(summary).fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 3 })
    }.width('100%').height(70).padding({ left: 16, right: 16 }).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
  }
}
