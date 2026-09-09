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
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct SourceManagerPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(MEDIA_SOURCE_VERSION_KEY) @Watch('onSourceVersionChanged') sourceVersion: number = 0
  @State private sources: MediaSourceInstance[] = []
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
        }.width('100%').padding({ left: 16, right: 8, top: 12, bottom: 8 })
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.sources, (source: MediaSourceInstance) => {
              this.SourceRow(source)
            })
          }.width('100%').padding({ left: 12, right: 12, bottom: 20 })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%')
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions('媒体源', this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private SourceRow(source: MediaSourceInstance): void {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        SymbolGlyph(this.isBuiltInSource(source) ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle'))
          .fontSize(26).fontColor([$r('app.color.accent_blue')])
        Column({ space: 3 }) {
          Text(source.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.sourceSubtitle(source, ProviderCatalog.get(source.providerType)))
            .fontSize(13).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.hasDescriptorCapability(source, ProviderCapability.HOME) && !this.isBuiltInSource(source)) {
          Toggle({ type: ToggleType.Switch, isOn: source.enabled }).onChange((isOn: boolean) => this.toggleSource(source, isOn))
        }
      }.width('100%')
      Row({ space: 8 }) {
        if (!this.isBuiltInSource(source)) {
          Button('↑').width(36).height(36).fontSize(13).backgroundColor(Color.Transparent)
            .onClick(() => this.moveSource(source, -1))
          Button('↓').width(36).height(36).fontSize(13).backgroundColor(Color.Transparent)
            .onClick(() => this.moveSource(source, 1))
        }
        if (this.hasDescriptorCapability(source, ProviderCapability.BROWSE)) {
          Button('浏览').layoutWeight(1).height(36).fontSize(13).backgroundColor($r('app.color.accent_blue'))
          .fontColor($r('app.color.text_on_primary'))
          .enabled(source.enabled || this.isBuiltInSource(source))
          .onClick(() => this.browse(source))
        }
        if (this.hasEditRoute(source)) {
          Button('编辑').layoutWeight(1).height(36).fontSize(13)
            .enabled(this.canEdit(source))
            .onClick(() => this.editSource(source))
        }
        if (this.hasEditRoute(source)) {
          Button('测试').layoutWeight(1).height(36).fontSize(13).onClick(() => this.testSource(source))
        }
        if (!this.isBuiltInSource(source)) {
          Button('删除').height(36).fontSize(13).fontColor($r('app.color.status_error')).backgroundColor(Color.Transparent)
            .onClick(() => this.confirmDelete(source))
        }
      }.width('100%')
    }.width('100%').padding(16).borderRadius(14)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .opacity(source.enabled || this.isBuiltInSource(source) ? 1 : 0.58)
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

  private sourceSubtitle(source: MediaSourceInstance, descriptor: ProviderDescriptor | null): string {
    if (this.isBuiltInSource(source)) return '本机文件夹'
    const label = descriptor === null || descriptor.displayName.length === 0 ? source.providerType : descriptor.displayName
    return label + (source.enabled ? ' · 已启用' : ' · 已停用')
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

  private hasEditRoute(source: MediaSourceInstance): boolean {
    const descriptor = ProviderCatalog.get(source.providerType)
    return descriptor !== null && descriptor.editRoute.length > 0
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
