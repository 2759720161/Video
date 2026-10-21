import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { ActiveSourceStore, ACTIVE_HOME_SOURCE_KEY } from '../../store/ActiveSourceStore'
import { HomeSourcePolicy } from '../../services/library/HomeSourcePolicy'
import { ComponentContent, LengthMetrics, promptAction, router } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, IconStyleMode } from '@kit.UIDesignKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore, MEDIA_SOURCE_VERSION_KEY } from '../../store/MediaSourceStore'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { getManagementContentMaxWidth, getTopSpacerHeight, buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { SourceActionKind } from '../../components/source/SourceActionSheet'
import { SourceManagerRow } from '../../components/source/SourceManagerRow'
import { SourceSectionHeader } from '../../components/source/SourceSectionHeader'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { AppSurface } from '../../ui/theme/AppSurface'
import { ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { UserDownloadFolder, OwnFolderCreationStatus } from '../../services/UserDownloadFolder'

class AddSourceMenuParams {
  onSelect: (sourceType: string) => void = (_sourceType: string): void => {}
}

@Builder
function AddSourceMenu(params: AddSourceMenuParams): void {
  Menu() {
    MenuItem({ content: 'Emby' })
      .onClick(() => params.onSelect('emby'))
    MenuItem({ content: '猫源' })
      .onClick(() => params.onSelect('catvod'))
    MenuItem({ content: 'Cat 订阅' })
      .onClick(() => params.onSelect('catnode'))
    MenuItem({ content: '本地文件夹' })
      .onClick(() => params.onSelect('local'))
  }
  .menuItemDivider({ strokeWidth: LengthMetrics.px(0), color: Color.Transparent })
}

@Component
export struct ServicesContent {
  @Prop embedded: boolean = false
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink(ACTIVE_HOME_SOURCE_KEY) activeSource: string = 'local'
  @StorageLink(MEDIA_SOURCE_VERSION_KEY) @Watch('onSourceVersionChanged') sourceVersion: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private sources: MediaSourceInstance[] = []
  @State private reorderMode: boolean = false
  private loadGeneration: number = 0
  private addMenuTargetId: string = 'services_add_menu'
  private scroller: Scroller = new Scroller()
  private selectingHome: boolean = false
  private creatingLocalFolder: boolean = false

  aboutToAppear(): void { this.loadSources() }
  aboutToDisappear(): void { this.loadGeneration++ }

  onSourceVersionChanged(): void { this.loadSources() }

  build() {
    HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            if (this.sources.length === 0) {
              this.EmptySourcesState()
            } else if (this.reorderMode) {
              this.ReorderState()
            } else {
              if (this.localSources().length > 0) {
                Column({ space: 12 }) {
                  SourceSectionHeader({ title: '本地', count: this.localSources().length })
                  ForEach(this.localSources(), (source: MediaSourceInstance) => {
                    Column({ space: 4 }) {
                      SourceManagerRow({ source: source,
                        providerLabel: this.providerLabel(source),
                        summaryText: this.sourceSummary(source),
                        isBuiltIn: this.isBuiltInSource(source),
                        isSelected: source.id === this.activeSource,
                        canSelect: HomeSourcePolicy.canSelect(source),
                        isEnabled: source.enabled,
                        onSelect: () => { void this.selectForHome(source) } })
                    }.width('100%')
                  }, (source: MediaSourceInstance) => 'source_manager_local_' + source.id)
                }
                .width('100%')
              }
              if (this.remoteSources().length > 0) {
                Column({ space: 12 }) {
                  SourceSectionHeader({ title: '服务器', count: this.remoteSources().length })
                  ForEach(this.remoteSources(), (source: MediaSourceInstance) => {
                    Column() {
                    SourceManagerRow({ source: source,
                      providerLabel: this.providerLabel(source),
                      summaryText: this.sourceSummary(source),
                      isBuiltIn: this.isBuiltInSource(source),
                      isSelected: source.id === this.activeSource,
                      canSelect: HomeSourcePolicy.canSelect(source),
                      isEnabled: source.enabled,
                      canEdit: this.canEdit(source),
                      userToggleable: this.canToggle(source),
                      userReorderable: this.canReorder(source) && this.reorderableSources().length > 1,
                      userRemovable: this.canRemove(source),
                      onSelect: () => { void this.selectForHome(source) },
                      onAction: (action: SourceActionKind) => this.handleSourceAction(source, action) })
                    }.width('100%')
                  }, (source: MediaSourceInstance) => 'source_manager_remote_' + source.id)
                }
                .width('100%')
              }
            }
          }.width('100%').constraintSize({ maxWidth: getManagementContentMaxWidth(this.screenWidthVp) || '100%' })
            .padding({ left: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
              right: ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp),
              top: getTopSpacerHeight(this.topSafeHeight) + AppSpacing.SM,
              bottom: this.bottomSafeHeight + (this.embedded ? 120 : AppSpacing.SECTION) })
            .alignItems(HorizontalAlign.Center)
        }.width('100%').height('100%')
          .align(Alignment.Top)
          .scrollable(ScrollDirection.Vertical)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollBar(BarState.Off)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(this.titleOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(this.embedded).backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  private titleOptions(): HdsNavigationTitleBarOptions {
    const options = buildTitleBarOptions('服务', this.hdsMaterialLevel)
    options.content = {
      title: { mainTitle: '服务' },
      menu: {
        value: [{
          content: {
            icon: $r('sys.symbol.plus'),
            type: IconStyleMode.SMALL,
            label: '添加服务',
            componentId: this.addMenuTargetId,
            action: (): void => this.openAddMenu()
          }
        }]
      }
    }
    return options
  }

  @Builder
  private EmptySourcesState(): void {
    PageEmptyState({ icon: $r('sys.symbol.externaldrive'), title: '还没有媒体来源',
      message: '添加 Emby 或 WebDAV，即可从首页浏览远程媒体', primaryActionText: '添加媒体源',
      onPrimaryAction: () => router.pushUrl({ url: 'pages/sources/AddSourcePage' }) })
  }

  @Builder
  private ReorderState(): void {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('调整顺序').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('使用上移和下移调整来源顺序').fontSize(12).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('完成').height(44).fontSize(13).fontColor($r('app.color.accent_blue'))
          .backgroundColor(Color.Transparent).onClick(() => this.reorderMode = false)
      }.width('100%').padding({ left: AppSpacing.MD, right: AppSpacing.SM, bottom: AppSpacing.SM })
      ForEach(this.reorderableSources(), (source: MediaSourceInstance, index: number) => {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(19)
            .fontColor([$r('app.color.text_secondary')])
          Text(source.name).fontSize(AppTypography.BODY).fontColor($r('app.color.text_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('上移').width(48).height(44).fontSize(12).backgroundColor(Color.Transparent)
            .enabled(index > 0).onClick(() => this.moveSource(source, -1))
          Button('下移').width(48).height(44).fontSize(12).backgroundColor(Color.Transparent)
            .enabled(index < this.reorderableSources().length - 1).onClick(() => this.moveSource(source, 1))
        }.width('100%').height(72).padding({ left: AppSpacing.MD, right: AppSpacing.SM,
          top: AppSpacing.SM, bottom: AppSpacing.SM })
          .border({ width: { bottom: index < this.reorderableSources().length - 1 ? 0.5 : 0 },
            color: $r('app.color.divider_color') })
      }, (source: MediaSourceInstance) => 'source_reorder_' + source.id)
    }
    .width('100%').borderRadius(AppRadius.SURFACE).clip(true)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE))
    .border({ width: 0.5, color: AppSurface.borderColor() })
  }

  private async loadSources(): Promise<void> {
    const generation = ++this.loadGeneration
    try {
      const sources = await MediaSourceStore.getAll()
      if (generation === this.loadGeneration) this.sources = sources
    } catch (_) {
      if (generation === this.loadGeneration) this.sources = []
    }
  }

  private openAddMenu(): void {
    const params = new AddSourceMenuParams()
    params.onSelect = (sourceType: string): void => this.openAddFlow(sourceType)
    try {
      const uiContext = this.getUIContext()
      const content = new ComponentContent<AddSourceMenuParams>(uiContext, wrapBuilder(AddSourceMenu), params)
      uiContext.getPromptAction().openMenu(content, { id: this.addMenuTargetId }, {
        placement: Placement.BottomRight,
        enableArrow: false
      })
    } catch (_) {
      // The title-bar action remains harmless if the popup cannot be created.
    }
  }

  private openAddFlow(sourceType: string): void {
    if (sourceType === 'catnode') {
      void router.pushUrl({ url: 'pages/catvod/CatNodeSourceEditPage' })
      return
    }
    if (sourceType === 'catvod') {
      router.pushUrl({ url: 'pages/catvod/CatVodSourceEditPage' })
      return
    }
    if (sourceType === 'emby') {
      void router.pushUrl({ url: 'pages/sources/EmbySourceEditPage' })
      return
    }
    if (sourceType === 'local') {
      void this.createLocalFolder()
    }
  }

  private async createLocalFolder(): Promise<void> {
    if (this.creatingLocalFolder) return
    this.creatingLocalFolder = true
    try {
      const context = getContext(this) as common.UIAbilityContext
      const result = await UserDownloadFolder.createOwnFolder(context)
      if (result.status === OwnFolderCreationStatus.ALREADY_EXISTS) {
        promptAction.showToast(buildDetailToastOptions('已创建应用专属文件夹'))
      } else if (result.status === OwnFolderCreationStatus.CREATED) {
        promptAction.showToast(buildDetailToastOptions('应用专属文件夹创建成功'))
      } else if (result.status === OwnFolderCreationStatus.FAILED) {
        promptAction.showToast(buildDetailToastOptions('创建失败，请重试'))
      }
    } catch (_) {
      promptAction.showToast(buildDetailToastOptions('创建失败，请重试'))
    } finally {
      this.creatingLocalFolder = false
    }
  }

  private async moveSource(source: MediaSourceInstance, delta: number): Promise<void> {
    const reorderable = this.reorderableSources()
    const index = reorderable.findIndex((item: MediaSourceInstance) => item.id === source.id)
    const target = index + delta
    if (index < 0 || target < 0 || target >= reorderable.length) return
    try {
      const other = reorderable[target]
      if (!this.canReorder(source) || !this.canReorder(other)) return
      await MediaSourceStore.swapOrder(source.id, other.id)
      await this.loadSources()
    } catch (_) { promptAction.showToast(buildDetailToastOptions('媒体源排序失败')) }
  }

  private providerLabel(source: MediaSourceInstance): string {
    const descriptor = ProviderCatalog.get(source.providerType)
    if (this.isBuiltInSource(source) && source.providerType === 'local') return '本机文件夹'
    return descriptor === null || descriptor.displayName.length === 0 ? source.providerType : descriptor.displayName
  }

  private sourceSummary(source: MediaSourceInstance): string {
    if (this.isBuiltInSource(source)) return '本地文件'
    const descriptor = ProviderCatalog.get(source.providerType)
    if (descriptor === null) return this.providerLabel(source)
    return descriptor.featureSummary.length > 0 ? descriptor.featureSummary :
      (descriptor.shortDescription.length > 0 ? descriptor.shortDescription : this.providerLabel(source))
  }

  private localSources(): MediaSourceInstance[] {
    return this.sources.filter((source: MediaSourceInstance) => this.isBuiltInSource(source))
  }

  private remoteSources(): MediaSourceInstance[] {
    return this.sources.filter((source: MediaSourceInstance) => !this.isBuiltInSource(source))
  }

  private reorderableSources(): MediaSourceInstance[] {
    return this.remoteSources().filter((source: MediaSourceInstance) => this.canReorder(source))
  }

  private handleSourceAction(source: MediaSourceInstance, action: SourceActionKind): void {
    if (action === SourceActionKind.EDIT) {
      if (this.canEdit(source)) this.editSource(source)
    } else if (action === SourceActionKind.TEST) {
      void this.testSource(source)
    } else if (action === SourceActionKind.TOGGLE) {
      if (this.canToggle(source)) void this.toggleSource(source, !source.enabled)
    } else if (action === SourceActionKind.REORDER) {
      if (this.canReorder(source) && this.reorderableSources().length > 1) this.reorderMode = true
    } else if (action === SourceActionKind.DELETE) {
      if (this.canRemove(source)) this.confirmDelete(source)
    }
  }

  private canEdit(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.editRoute.length > 0
  }

  private isBuiltInSource(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.builtIn
  }

  private canToggle(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.userToggleable
  }

  private canReorder(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.userReorderable
  }

  private canRemove(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.userRemovable
  }

  private editSource(source: MediaSourceInstance): void {
    const descriptor = ProviderCatalog.get(source.providerType)
    if (descriptor !== null && descriptor.editRoute.length > 0) {
      void router.pushUrl({ url: descriptor.editRoute, params: descriptor.editParams(source.id) })
    }
  }

  private async selectForHome(source: MediaSourceInstance): Promise<void> {
    if (this.selectingHome || !HomeSourcePolicy.canSelect(source)) return
    this.selectingHome = true
    try {
      await ActiveSourceStore.select(source.id)
    } catch (_) {
      this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('无法切换首页服务，请重试'))
    } finally {
      this.selectingHome = false
    }
  }

  private async toggleSource(source: MediaSourceInstance, enabled: boolean): Promise<void> {
    if (!this.canToggle(source)) return
    try { await MediaSourceStore.setEnabled(source.id, enabled); await this.loadSources() }
    catch (_) { promptAction.showToast(buildDetailToastOptions('媒体源状态更新失败')) }
  }

  private confirmDelete(source: MediaSourceInstance): void {
    if (!this.canRemove(source)) return
    this.getUIContext().getPromptAction().showDialog({
      title: '删除媒体源？',
      message: '将移除“' + source.name + '”及其连接配置。',
      buttons: [
        { text: '取消', color: $r('app.color.text_primary') },
        { text: '删除', color: $r('app.color.status_error') }
      ]
    }, (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err === undefined && result.index === 1) void this.deleteSource(source)
    })
  }

  private async deleteSource(source: MediaSourceInstance): Promise<void> {
    if (!this.canRemove(source)) return
    try { await MediaSourceStore.remove(source.id); await this.loadSources(); promptAction.showToast(buildDetailToastOptions('已删除媒体源')) }
    catch (_) { promptAction.showToast(buildDetailToastOptions('媒体源删除失败')) }
  }

  private async testSource(source: MediaSourceInstance): Promise<void> {
    try {
      const provider = await ProviderRegistry.get(source.id, getContext(this) as common.UIAbilityContext, true)
      if (provider === null) throw new Error('媒体源不可用')
      const health = await provider.testConnection()
      promptAction.showToast(buildDetailToastOptions(health.ok ?
        (health.message + (health.latencyMs > 0 ? ' · ' + health.latencyMs + 'ms' : '')) : health.message))
    } catch (_) {
      promptAction.showToast(buildDetailToastOptions('连接失败，请检查地址和账号'))
    }
  }
}
