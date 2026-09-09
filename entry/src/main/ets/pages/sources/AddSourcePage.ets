import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { router } from '@kit.ArkUI'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { ProviderDescriptor } from '../../providers/base/ProviderDescriptor'

class ProviderCategoryGroup {
  category: string = ''
  providers: ProviderDescriptor[] = []
}

@Entry
@Component
struct AddSourcePage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  private providers: ProviderDescriptor[] = ProviderCatalog.getAddableProviders()

  build() {
    HdsNavigation() {
      Column({ space: 12 }) {
        ForEach(this.providerGroups(), (group: ProviderCategoryGroup) => {
          Column({ space: 8 }) {
            Text(group.category).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 8, bottom: 2 })
            ForEach(group.providers, (descriptor: ProviderDescriptor) => {
              this.SourceCard(descriptor)
            }, (descriptor: ProviderDescriptor) => 'add_provider_' + descriptor.type)
          }.width('100%')
        }, (group: ProviderCategoryGroup) => 'add_category_' + group.category)
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

  private providerGroups(): ProviderCategoryGroup[] {
    const groups: ProviderCategoryGroup[] = []
    for (let i = 0; i < this.providers.length; i++) {
      const descriptor = this.providers[i]
      const category = descriptor.category.length > 0 ? descriptor.category : '其他来源'
      let group: ProviderCategoryGroup | null = null
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].category === category) {
          group = groups[j]
          break
        }
      }
      if (group === null) {
        group = new ProviderCategoryGroup()
        group.category = category
        groups.push(group)
      }
      group.providers.push(descriptor)
    }
    return groups
  }

  @Builder
  private SourceCard(descriptor: ProviderDescriptor): void {
    Row({ space: 14 }) {
      SymbolGlyph(this.providerIcon(descriptor)).fontSize(28).fontColor([$r('app.color.accent_blue')])
      Column({ space: 4 }) {
        Text(descriptor.displayName).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.subtitle(descriptor)).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(descriptor.enabled ? '添加' : '即将支持').fontSize(13).fontColor(descriptor.enabled ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
    }
    .width('100%').padding(16).borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .opacity(descriptor.enabled ? 1 : 0.6)
    .onClick(() => { if (descriptor.enabled) router.pushUrl({ url: descriptor.addRoute }) })
  }

  private subtitle(descriptor: ProviderDescriptor): string {
    return descriptor.description.length > 0 ? descriptor.description : descriptor.category
  }

  private providerIcon(descriptor: ProviderDescriptor): Resource {
    return descriptor.iconKind === 'folder' ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle')
  }
}
