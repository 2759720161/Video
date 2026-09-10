import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { router } from '@kit.ArkUI'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { ProviderDescriptor } from '../../providers/base/ProviderDescriptor'
import { getContentMaxWidth, isTabletLayout } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { ProviderIcon } from '../../components/source/ProviderIcon'
import { PageEmptyState } from '../../components/common/PageEmptyState'

class ProviderCategoryGroup {
  category: string = ''
  providers: ProviderDescriptor[] = []
}

@Entry
@Component
struct AddSourcePage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private pressedProviderType: string = ''
  private providers: ProviderDescriptor[] = ProviderCatalog.getGalleryProviders()

  build() {
    HdsNavigation() {
      Scroll() {
        Column({ space: 12 }) {
          Text('连接你的媒体')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ top: AppSpacing.SMALL, bottom: AppSpacing.TINY })
          if (this.providerGroups().length === 0) {
            this.EmptyProviderState()
          } else {
            ForEach(this.providerGroups(), (group: ProviderCategoryGroup) => {
              Column({ space: 8 }) {
                Text(group.category).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 8, bottom: 2 })
                Grid() {
                  ForEach(group.providers, (descriptor: ProviderDescriptor) => {
                    GridItem() { this.SourceCard(descriptor) }
                  }, (descriptor: ProviderDescriptor) => 'add_provider_' + descriptor.type)
                }
                .columnsTemplate(this.providerColumns())
                .columnsGap(AppSpacing.SMALL)
                .rowsGap(AppSpacing.SMALL)
                .width('100%')
              }.width('100%')
            }, (group: ProviderCategoryGroup) => 'add_category_' + group.category)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: getContentMaxWidth(this.screenWidthVp) || '100%' })
        .padding({ left: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
          right: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
          bottom: AppSpacing.SECTION })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
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
    Column({ space: 9 }) {
      Row({ space: 12 }) {
        ProviderIcon({ providerType: descriptor.type })
        Column({ space: 3 }) {
          Text(descriptor.displayName).fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitle(descriptor)).fontSize(13).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      Text(this.featureSummary(descriptor)).fontSize(12).fontColor($r('app.color.text_secondary'))
        .maxLines(2).width('100%').textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Blank().layoutWeight(1)
        Text(descriptor.enabled ? '添加' : (descriptor.comingSoonText.length > 0 ? descriptor.comingSoonText : '即将支持'))
          .fontSize(13)
          .fontColor(descriptor.enabled ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
      }.width('100%')
    }
    .width('100%').height(174).padding(16).borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .enabled(descriptor.enabled)
    .opacity(descriptor.enabled ? (this.pressedProviderType === descriptor.type ? 0.86 : 1) : 0.6)
    .scale({ x: this.providerCardScale(descriptor.type), y: this.providerCardScale(descriptor.type) })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => this.handleProviderTouch(descriptor.type, event))
    .onClick(() => { if (descriptor.enabled) router.pushUrl({ url: descriptor.addRoute }) })
  }

  private subtitle(descriptor: ProviderDescriptor): string {
    if (descriptor.shortDescription.length > 0) return descriptor.shortDescription
    return descriptor.description.length > 0 ? descriptor.description : descriptor.category
  }

  private featureSummary(descriptor: ProviderDescriptor): string {
    return descriptor.featureSummary.length > 0 ? descriptor.featureSummary : descriptor.description
  }

  private providerCardScale(providerType: string): number {
    return this.pressedProviderType === providerType && this.providersEnabled(providerType) ? 0.96 : 1
  }

  private providersEnabled(providerType: string): boolean {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].type === providerType) return this.providers[i].enabled
    }
    return false
  }

  private handleProviderTouch(providerType: string, event: TouchEvent): void {
    if (!this.providersEnabled(providerType)) return
    if (event.type === TouchType.Down) {
      this.pressedProviderType = providerType
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.pressedProviderType === providerType) this.pressedProviderType = ''
    }
  }

  private providerColumns(): string {
    return isTabletLayout(this.screenWidthVp) ? '1fr 1fr' : '1fr'
  }

  @Builder
  private EmptyProviderState(): void {
    PageEmptyState({ icon: $r('sys.symbol.plus'), title: '暂无可添加的媒体源',
      message: '当前没有已注册的 Provider 类型' })
  }
}
