import { common } from '@kit.AbilityKit'
import { webview } from '@kit.ArkWeb'
import { buffer } from '@kit.ArkTS'
import { fileIo, picker } from '@kit.CoreFileKit'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { CatNodeProvider } from '../../providers/catvod/CatNodeProvider'
import { CatNodeRuntime } from '../../providers/catvod/CatNodeRuntime'
import { CatNodeConfiguration } from '../../providers/catvod/CatNodeConfiguration'
import { CatNodeConfigurationScript } from '../../providers/catvod/CatNodeConfigurationScript'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct CatNodeConfigurationPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private entryUrl: string = ''
  @State private loading: boolean = true
  @State private error: string = ''
  @State private exporting: boolean = false
  @State private documentId: number = 0
  private sourceId: string = ''
  private alive: boolean = false
  private generation: number = 0
  private attached: boolean = false
  private configurationDirty: boolean = false
  private controller: webview.WebviewController = new webview.WebviewController()

  aboutToAppear(): void {
    this.alive = true
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    this.sourceId = params !== undefined && typeof params['sourceId'] === 'string' ? params['sourceId'] as string : ''
    void this.load()
  }
  aboutToDisappear(): void {
    this.alive = false; this.generation++; this.attached = false
    if (this.configurationDirty) { this.configurationDirty = false; void this.publishChanges() }
  }
  private async publishChanges(): Promise<void> {
    CatNodeRuntime.invalidatePlaybackMetadata()
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      // Touch only the latest source record; its normal version signal refreshes menus and cached catalog data.
      if (source !== null && source.providerType === 'catnode') await MediaSourceStore.update(source)
    } catch (_) {}
  }
  onBackPress(): boolean {
    try {
      if (this.attached && this.error.length === 0 && this.controller.accessBackward()) {
        this.controller.backward(); return true
      }
    } catch (_) {}
    return false
  }
  private text(value: Resource): string {
    return this.getUIContext().getHostContext()!.resourceManager.getStringSync(value.id)
  }
  private async load(): Promise<void> {
    const generation = ++this.generation
    this.documentId = generation
    this.loading = true; this.error = ''; this.entryUrl = ''; this.attached = false
    try {
      const provider = await ProviderRegistry.get(this.sourceId, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!this.alive || generation !== this.generation) return
      if (!(provider instanceof CatNodeProvider)) throw new Error(this.text($r('app.string.cat_config_unavailable')))
      const address = await provider.configurationUrl()
      if (!this.alive || generation !== this.generation) return
      this.controller = new webview.WebviewController()
      this.entryUrl = address
    } catch (error) {
      if (this.alive && generation === this.generation) {
        this.loading = false
        this.error = error instanceof Error ? error.message : this.text($r('app.string.cat_config_unavailable'))
      }
    }
  }
  private isCurrent(address: string, generation: number): boolean {
    return this.alive && generation === this.generation && address === this.entryUrl
  }
  private begin(address: string, generation: number): void {
    if (!this.isCurrent(address, generation)) return
    this.error = ''; this.loading = true
  }
  private end(address: string, generation: number): void {
    if (!this.isCurrent(address, generation)) return
    this.loading = false
    // The source uses window.open for export/registration. Keep those explicit actions in this Web view.
    if (this.attached && this.error.length === 0) {
      void this.controller.runJavaScript(CatNodeConfigurationScript.build() +
        'window.open = function(u) { location.href = new URL(u, location.href).href; return null; };')
        .catch(() => {})
    }
  }
  private failed(address: string, generation: number, reason: string): void {
    if (!this.isCurrent(address, generation)) return
    this.loading = false; this.error = reason || this.text($r('app.string.cat_config_unavailable'))
  }
  private async exportConfiguration(address: string): Promise<void> {
    if (!this.alive || this.exporting || !CatNodeConfiguration.isExport(address, this.entryUrl)) return
    const generation = this.generation
    const entry = this.entryUrl
    this.exporting = true
    try {
      const data = await CatNodeRuntime.request(CatNodeConfiguration.exportUrl(entry), null)
      if (!this.alive || generation !== this.generation) return
      const parsed = JSON.parse(data) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error(this.text($r('app.string.cat_config_export_failed')))
      const options = new picker.DocumentSaveOptions()
      options.newFileNames = ['cat-config.json']
      const files = await new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext).save(options)
      if (!this.alive || generation !== this.generation || files.length === 0) return
      const file = fileIo.openSync(files[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      try {
        if (fileIo.writeSync(file.fd, data) !== buffer.byteLength(data, 'utf-8')) {
          throw new Error(this.text($r('app.string.cat_config_export_failed')))
        }
      } finally { fileIo.closeSync(file) }
      this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(this.text($r('app.string.cat_config_exported'))))
    } catch (_) {
      if (this.alive && generation === this.generation) {
        this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(this.text($r('app.string.cat_config_export_failed'))))
      }
    } finally { this.exporting = false }
  }
  private titleOptions(): HdsNavigationTitleBarOptions {
    const options = buildTitleBarOptions(this.text($r('app.string.cat_config_title')), this.materialLevel)
    // This form must start below the native title bar instead of drawing behind it like media artwork.
    options.enableComponentSafeArea = true
    if (options.content !== undefined) options.content.menu = { value: [{ content: {
      icon: $r('sys.symbol.arrow_clockwise'), label: this.text($r('app.string.cat_config_reload')),
      isEnabled: !this.loading && !this.exporting, action: () => { void this.load() }
    } }] }
    return options
  }

  build() {
    HdsNavigation() {
      Stack() {
        if (this.entryUrl.length > 0) this.Browser(this.entryUrl, this.documentId)
        if (this.error.length > 0) {
          Column() {
            PageErrorState({ title: this.text($r('app.string.cat_config_unavailable')), message: this.error,
              onRetry: () => { void this.load() } })
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.page_background'))
        } else if (this.loading) {
          Column() { PageLoadingState({ title: this.text($r('app.string.cat_config_loading')) }) }
            .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.page_background'))
        }
      }.width('100%').height('100%').clip(true)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(this.titleOptions()).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
      .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Browser(address: string, generation: number): void {
    Web({ src: address, controller: this.controller }).width('100%').height('100%')
      .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None).multiWindowAccess(false)
      .onControllerAttached(() => { if (this.isCurrent(address, generation)) this.attached = true })
      .onPageBegin(() => this.begin(address, generation)).onPageEnd(() => this.end(address, generation))
      .onErrorReceive((event) => {
        if (event !== undefined && event.request.isMainFrame()) this.failed(address, generation, event.error.getErrorInfo())
      })
      .onHttpErrorReceive((event) => {
        if (event !== undefined && event.request.isMainFrame()) {
          this.failed(address, generation, 'HTTP ' + event.response.getResponseCode())
        }
      })
      .onLoadIntercept((event) => {
        if (!this.isCurrent(address, generation)) return true
        if (event === undefined) return false
        const target = event.data.getRequestUrl()
        if (CatNodeConfiguration.isExport(target, address)) { void this.exportConfiguration(target); return true }
        return !CatNodeConfiguration.allowsNavigation(target, address)
      })
      .onDownloadStart((event) => {
        if (event !== undefined && this.isCurrent(address, generation)) void this.exportConfiguration(event.url)
      })
      .onInterceptRequest((event) => {
        if (event !== undefined && this.isCurrent(address, generation) &&
          CatNodeConfiguration.isMutation(event.request.getRequestUrl(), event.request.getRequestMethod(), address)) {
          this.configurationDirty = true
          CatNodeRuntime.invalidatePlaybackMetadata()
        }
        return null
      })
      .onRenderExited(() => this.failed(address, generation, this.text($r('app.string.cat_config_unavailable'))))
  }
}
