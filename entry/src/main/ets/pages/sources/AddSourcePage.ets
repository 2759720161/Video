import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { router } from '@kit.ArkUI'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct AddSourcePage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT

  build() {
    HdsNavigation() {
      Column({ space: 12 }) {
        this.SourceCard('Emby', '连接 Emby 媒体服务器，浏览并播放远程媒体。', $r('sys.symbol.play_round_rectangle'), () => {
          router.pushUrl({ url: 'pages/sources/EmbySourceEditPage' })
        }, true)
        this.SourceCard('WebDAV', '连接支持 WebDAV 的 NAS、服务器或网盘。', $r('sys.symbol.folder'), () => {
          router.pushUrl({ url: 'pages/sources/WebDavSourceEditPage' })
        }, true)
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('添加媒体源', this.hdsMaterialLevel))
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private SourceCard(title: string, subtitle: string, icon: Resource, action: () => void, enabled: boolean): void {
    Row({ space: 14 }) {
      SymbolGlyph(icon).fontSize(28).fontColor([$r('app.color.accent_blue')])
      Column({ space: 4 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(subtitle).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(enabled ? '添加' : '即将支持').fontSize(13).fontColor(enabled ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
    }
    .width('100%').padding(16).borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .opacity(enabled ? 1 : 0.6)
    .onClick(() => { if (enabled) action() })
  }
}
