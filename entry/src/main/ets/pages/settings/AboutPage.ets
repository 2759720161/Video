import { promptAction } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { commentManager } from '@kit.AppGalleryKit'
import { common } from '@kit.AbilityKit'
import { APP_VERSION } from '../../constants/AppVersion'
import { getBottomSpacerHeight, getTopSpacerHeight, buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct AboutPage {
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
            this.Item($r('sys.symbol.info_circle'), '版本信息', `当前版本 ${APP_VERSION}`)
            Divider().color($r('app.color.divider_color')).margin({ left: 62 })
            this.Item($r('sys.symbol.doc_text'), '三方库与服务', 'HarmonyOS AVPlayer、文件选择器、关系型数据库与应用市场服务')
            Divider().color($r('app.color.divider_color')).margin({ left: 62 })
            this.Item($r('sys.symbol.star_fill'), '给个好评', '在应用市场评分与评论', () => this.openReview(), true)
          }
          .width('100%').borderRadius(12).clip(true).backgroundColor($r('app.color.card_background'))
          .border({ width: 0.5, color: $r('app.color.card_specular_border') })
          .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }.width('100%').padding({ left: 12, right: 12 }).alignItems(HorizontalAlign.Start).constraintSize({ minHeight: '100%' })
      }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('关于', this.hdsMaterialLevel)).bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder Item(icon: Resource, title: string, summary: string, action: () => void = () => {}, clickable: boolean = false): void {
    Row() {
      SymbolGlyph(icon).fontSize(24).fontColor([$r('app.color.accent_blue')]).width(34).margin({ right: 12 })
      Column() {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(summary).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 3 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (clickable) { SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('sys.color.icon_secondary')]) }
    }.width('100%').height(72).padding({ left: 16, right: 16 }).onClick(action)
  }

  private async openReview(): Promise<void> {
    try {
      await commentManager.showCommentDialog(getContext(this) as common.UIAbilityContext)
    } catch (_) {
      promptAction.showToast({ message: '当前设备未提供应用市场评分服务' })
    }
  }
}
