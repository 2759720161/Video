import { promptAction, router } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore, MEDIA_SOURCE_VERSION_KEY } from '../../store/MediaSourceStore'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderCatalog } from '../../providers/base/ProviderCatalog'
import { ProviderDescriptor } from '../../providers/base/ProviderDescriptor'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { buildTitleBarOptions, getContentMaxWidth, isTabletLayout,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppTypography } from '../../ui/theme/AppTypography'
import { SourceActionKind } from '../../components/source/SourceActionSheet'
import { SourceManagerCard } from '../../components/source/SourceManagerCard'
import { SourceSectionHeader } from '../../components/source/SourceSectionHeader'
import { PageEmptyState } from '../../components/common/PageEmptyState'

@Entry
@Component
struct SourceManagerPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(MEDIA_SOURCE_VERSION_KEY) @Watch('onSourceVersionChanged') sourceVersion: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private sources: MediaSourceInstance[] = []
  @State private reorderMode: boolean = false
  private loadGeneration: number = 0

  aboutToAppear(): void { this.loadSources() }

  onSourceVersionChanged(): void { this.loadSources() }

  build() {
    HdsNavigation() {
      Column() {
        Row() {
          Text('管理已连接的媒体来源').fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Button('+ 添加').fontSize(14).fontColor($r('app.color.accent_blue')).backgroundColor(Color.Transparent)
            .onClick(() => router.pushUrl({ url: 'pages/sources/AddSourcePage' }))
        }.width('100%').padding({ left: AppSpacing.PAGE, right: AppSpacing.PAGE,
          top: AppSpacing.SECTION_COMPACT, bottom: AppSpacing.SMALL })
        Scroll() {
          Column({ space: 12 }) {
            if (this.sources.length === 0) {
              this.EmptySourcesState()
            } else if (this.reorderMode) {
              this.ReorderState()
            } else {
              if (this.localSources().length > 0) {
                SourceSectionHeader({ title: '本地', count: this.localSources().length })
                ForEach(this.localSources(), (source: MediaSourceInstance) => {
                  SourceManagerCard({ source: source,
                    providerLabel: this.providerLabel(source),
                    statusText: this.sourceStatus(source),
                    isBuiltIn: true,
                    canBrowse: this.hasDescriptorCapability(source, ProviderCapability.BROWSE),
                    isEnabled: source.enabled,
                    onBrowse: () => this.browse(source) })
                }, (source: MediaSourceInstance) => 'source_manager_local_' + source.id)
              }
              if (this.remoteSources().length > 0) {
                SourceSectionHeader({ title: '服务器', count: this.remoteSources().length })
                ForEach(this.remoteSources(), (source: MediaSourceInstance) => {
                  SourceManagerCard({ source: source,
                    providerLabel: this.providerLabel(source),
                    statusText: this.sourceStatus(source),
                    isBuiltIn: false,
                    canBrowse: this.hasDescriptorCapability(source, ProviderCapability.BROWSE),
                    isEnabled: source.enabled,
                    onBrowse: () => this.browse(source),
                    onAction: (action: SourceActionKind) => this.handleSourceAction(source, action) })
                }, (source: MediaSourceInstance) => 'source_manager_remote_' + source.id)
              }
            }
          }.width('100%').constraintSize({ maxWidth: getContentMaxWidth(this.screenWidthVp) || '100%' })
            .padding({ left: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
              right: isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE,
              bottom: AppSpacing.SECTION })
            .alignItems(HorizontalAlign.Center)
        }.layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%')
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions('媒体源', this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private EmptySourcesState(): void {
    PageEmptyState({ icon: $r('sys.symbol.externaldrive'), title: '还没有媒体来源',
      message: '添加 Emby 或 WebDAV，即可从首页浏览远程媒体', primaryActionText: '添加媒体源',
      onPrimaryAction: () => router.pushUrl({ url: 'pages/sources/AddSourcePage' }) })
  }

  @Builder
  private ReorderState(): void {
    Row() {
      Column({ space: 3 }) {
        Text('调整顺序').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('拖动排序入口已收口到这里').fontSize(12).fontColor($r('app.color.text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('完成').height(36).fontSize(13).fontColor($r('app.color.accent_blue'))
        .backgroundColor(Color.Transparent).onClick(() => this.reorderMode = false)
    }.width('100%').padding({ left: AppSpacing.TINY, right: AppSpacing.TINY, bottom: AppSpacing.SMALL })
    ForEach(this.remoteSources(), (source: MediaSourceInstance, index: number) => {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(19)
          .fontColor([$r('app.color.text_secondary')])
        Text(source.name).fontSize(AppTypography.BODY).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('↑').width(36).height(36).fontSize(13).backgroundColor(Color.Transparent)
          .enabled(index > 0).onClick(() => this.moveSource(source, -1))
        Button('↓').width(36).height(36).fontSize(13).backgroundColor(Color.Transparent)
          .enabled(index < this.remoteSources().length - 1).onClick(() => this.moveSource(source, 1))
      }.width('100%').padding({ left: AppSpacing.CARD_CONTENT, right: AppSpacing.SMALL,
        top: AppSpacing.SMALL, bottom: AppSpacing.SMALL })
        .borderRadius(AppRadius.CARD)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }, (source: MediaSourceInstance) => 'source_reorder_' + source.id)
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

  private async moveSource(source: MediaSourceInstance, delta: number): Promise<void> {
    const index = this.sources.findIndex((item: MediaSourceInstance) => item.id === source.id)
    const target = index + delta
    if (index < 0 || target < 0 || target >= this.sources.length) return
    try {
      const other = this.sources[target]
      // 内置 local 永远固定在首位，不能参与用户来源排序交换。
      if (this.isBuiltInSource(source) || this.isBuiltInSource(other)) return
      await MediaSourceStore.swapOrder(source.id, other.id)
      await this.loadSources()
    } catch (_) { promptAction.showToast({ message: '媒体源排序失败' }) }
  }

  private providerLabel(source: MediaSourceInstance): string {
    if (this.isBuiltInSource(source)) return '本机文件夹'
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor === null || descriptor.displayName.length === 0 ? source.providerType : descriptor.displayName
  }

  private sourceStatus(source: MediaSourceInstance): string {
    return source.enabled || this.isBuiltInSource(source) ? '' : '已停用'
  }

  private localSources(): MediaSourceInstance[] {
    return this.sources.filter((source: MediaSourceInstance) => this.isBuiltInSource(source))
  }

  private remoteSources(): MediaSourceInstance[] {
    return this.sources.filter((source: MediaSourceInstance) => !this.isBuiltInSource(source))
  }

  private handleSourceAction(source: MediaSourceInstance, action: SourceActionKind): void {
    if (action === SourceActionKind.EDIT) {
      if (this.canEdit(source)) this.editSource(source)
    } else if (action === SourceActionKind.TEST) {
      void this.testSource(source)
    } else if (action === SourceActionKind.TOGGLE) {
      void this.toggleSource(source, !source.enabled)
    } else if (action === SourceActionKind.REORDER) {
      this.reorderMode = true
    } else if (action === SourceActionKind.DELETE) {
      this.confirmDelete(source)
    }
  }

  private canEdit(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.editRoute.length > 0
  }

  private isBuiltInSource(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && !descriptor.supportsMultipleInstances
  }

  private hasDescriptorCapability(source: MediaSourceInstance, capability: ProviderCapability): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.hasCapability(capability)
  }

  private editSource(source: MediaSourceInstance): void {
    const descriptor = ProviderCatalog.get(source.providerType)
    if (descriptor !== null && descriptor.editRoute.length > 0) {
      void router.pushUrl({ url: descriptor.editRoute, params: descriptor.editParams(source.id) })
    }
  }

  private browse(source: MediaSourceInstance): void {
    const descriptor = ProviderCatalog.get(source.providerType)
    if (descriptor === null || descriptor.browserRoute.length === 0) return
    void router.pushUrl({ url: descriptor.browserRoute, params: descriptor.browserParams(source.id) })
  }

  private async toggleSource(source: MediaSourceInstance, enabled: boolean): Promise<void> {
    try { await MediaSourceStore.setEnabled(source.id, enabled); await this.loadSources() }
    catch (_) { promptAction.showToast({ message: '媒体源状态更新失败' }) }
  }

  private confirmDelete(source: MediaSourceInstance): void {
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
    try { await MediaSourceStore.remove(source.id); await this.loadSources(); promptAction.showToast({ message: '已删除媒体源' }) }
    catch (_) { promptAction.showToast({ message: '媒体源删除失败' }) }
  }

  private async testSource(source: MediaSourceInstance): Promise<void> {
    try {
      const provider = await ProviderRegistry.get(source.id, getContext(this) as common.UIAbilityContext, true)
      if (provider === null) throw new Error('媒体源不可用')
      const health = await provider.testConnection()
      promptAction.showToast({ message: health.ok ?
        (health.message + (health.latencyMs > 0 ? ' · ' + health.latencyMs + 'ms' : '')) : health.message })
    } catch (_) { promptAction.showToast({ message: '连接失败，请检查地址和账号' }) }
  }
}
