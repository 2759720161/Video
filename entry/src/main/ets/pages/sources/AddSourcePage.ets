import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { router } from '@kit.ArkUI'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { ProviderDescriptor } from '../../providers/base/ProviderDescriptor'
import { getManagementContentMaxWidth } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { ProviderGalleryCard } from '../../components/source/ProviderGalleryCard'
import { AppTypography } from '../../ui/theme/AppTypography'
import { ResponsiveSizeClass, ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'

class ProviderCategoryGroup {
  category: string = ''
  providers: ProviderDescriptor[] = []
}

@Entry
@Component
struct AddSourcePage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  private providers: ProviderDescriptor[] = ProviderCatalog.getGalleryProviders()

  build() {
    HdsNavigation() {
      Scroll() {
        Column({ space: 12 }) {
          Text('连接你的媒体')
            .fontSize(AppTypography.PAGE_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ top: AppSpacing.SM, bottom: AppSpacing.XS })
          Text('将家庭媒体服务器和网络存储统一到你的媒体库。')
            .fontSize(AppTypography.BODY)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.providerGroups().length === 0) {
            this.EmptyProviderState()
          } else {
            ForEach(this.providerGroups(), (group: ProviderCategoryGroup) => {
              Column({ space: 8 }) {
                Text(group.category).fontSize(AppTypography.BODY_LARGE).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary')).width('100%').margin({ top: AppSpacing.SM, bottom: AppSpacing.XS })
                Grid() {
                  ForEach(group.providers, (descriptor: ProviderDescriptor) => {
                    GridItem() {
                      ProviderGalleryCard({
                        providerType: descriptor.type,
                        title: descriptor.displayName,
                        subtitle: this.subtitle(descriptor),
                        summary: this.featureSummary(descriptor),
                        isEnabled: descriptor.enabled,
                        comingSoonText: descriptor.comingSoonText,
                        onCardClick: () => router.pushUrl({ url: descriptor.addRoute })
                      })
                    }
                  }, (descriptor: ProviderDescriptor) => 'add_provider_' + descriptor.type)
                }
                .columnsTemplate(this.providerColumns())
                .columnsGap(AppSpacing.SM)
                .rowsGap(AppSpacing.SM)
                .width('100%')
              }.width('100%')
            }, (group: ProviderCategoryGroup) => 'add_category_' + group.category)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: getManagementContentMaxWidth(this.screenWidthVp) || '100%' })
        .padding({ left: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
          right: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
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

  private subtitle(descriptor: ProviderDescriptor): string {
    if (descriptor.shortDescription.length > 0) return descriptor.shortDescription
    return descriptor.description.length > 0 ? descriptor.description : descriptor.category
  }

  private featureSummary(descriptor: ProviderDescriptor): string {
    return descriptor.featureSummary.length > 0 ? descriptor.featureSummary : descriptor.description
  }

  private providerColumns(): string {
    const sizeClass = ResponsiveSizeClassResolver.resolve(this.screenWidthVp)
    return sizeClass === ResponsiveSizeClass.COMPACT ? '1fr' : '1fr 1fr'
  }

  @Builder
  private EmptyProviderState(): void {
    PageEmptyState({ icon: $r('sys.symbol.plus'), title: '暂无可添加的媒体源',
      message: '当前没有已注册的 Provider 类型' })
  }
}
