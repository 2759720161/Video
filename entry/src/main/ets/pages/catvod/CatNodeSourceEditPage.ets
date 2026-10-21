import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, IconStyleMode } from '@kit.UIDesignKit'
import { MediaSourceInstance, createMediaSourceId } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { CatNodeRuntime, CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { CatNodeSourceConfig, CatNodeSubscription, CatNodeSubscriptionCodec, CatNodeSubscriptionStage } from '../../providers/catvod/CatNodeSubscription'
import { extractErrorMsg } from '../../utils/Logger'
import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { buildTitleBarOptions, getTopSpacerHeight, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct CatNodeSourceEditPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State private name: string = ''
  @State private md5Url: string = ''
  @State private iconUri: string = ''
  @State private loading: boolean = false
  @State private saving: boolean = false
  @State private picking: boolean = false
  @State private error: string = ''
  @State private stage: CatNodeSubscriptionStage = CatNodeSubscriptionStage.CHECKING
  private sourceId: string = ''
  private originalUrl: string = ''
  private config: CatNodeSourceConfig = new CatNodeSourceConfig()
  private alive: boolean = true
  private generation: number = 0
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.alive = true
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') this.sourceId = params['sourceId'] as string
    if (this.sourceId.length > 0) void this.load()
  }
  aboutToDisappear(): void { this.alive = false; this.generation++ }

  private async load(): Promise<void> {
    const generation = ++this.generation
    this.loading = true
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      if (!this.alive || generation !== this.generation) return
      if (source === null || source.providerType !== 'catnode') throw new Error('该订阅已不可用')
      this.config = CatNodeSubscriptionCodec.decode(source.configJson)
      this.name = source.name; this.md5Url = this.config.md5Url; this.originalUrl = this.md5Url; this.iconUri = this.config.iconUri
      if (this.config.md5Url.length === 0) {
        this.config.legacySpiderKey = this.config.spiderKey
        this.error = '请填写订阅地址，原来的播放记录会保留'
      }
    } catch (error) { if (this.alive) this.error = error instanceof Error ? error.message : '读取订阅失败' }
    finally { if (this.alive && generation === this.generation) this.loading = false }
  }

  private async pickIcon(): Promise<void> {
    if (this.saving || this.loading || this.picking) return
    this.picking = true
    try {
      const options = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE; options.maxSelectNumber = 1
      const result = await new photoAccessHelper.PhotoViewPicker().select(options)
      if (this.alive && result.photoUris.length > 0) this.iconUri = result.photoUris[0]
    } catch (_) {
      if (this.alive) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('未能选择图标，请重试'))
    } finally { if (this.alive) this.picking = false }
  }

  private async storeIcon(context: common.Context, id: string): Promise<string> {
    if (this.iconUri.length === 0 || this.iconUri === this.config.iconUri) return this.iconUri
    const source = fileIo.openSync(this.iconUri, fileIo.OpenMode.READ_ONLY)
    try {
      const size = fileIo.statSync(source.fd).size
      if (size <= 0 || size > 8 * 1024 * 1024) throw new Error('请选择小于 8 MB 的图片')
      const bytes = new ArrayBuffer(size)
      if (fileIo.readSync(source.fd, bytes) !== size) throw new Error('图标读取不完整')
      const directory = context.filesDir + '/catnode/icons'
      if (!fileIo.accessSync(directory)) fileIo.mkdirSync(directory, true)
      const path = directory + '/' + id + '.' + Date.now() + '.image'
      CatNodeSubscription.atomicWrite(path, bytes)
      return fileUri.getUriFromPath(path)
    } finally { fileIo.closeSync(source) }
  }

  private async save(origin: string = 'form'): Promise<void> {
    hilog.info(0, 'CatSubscription', 'save_clicked origin=%{public}s saving=%{public}s loading=%{public}s picking=%{public}s addressLength=%{public}d',
      origin, String(this.saving), String(this.loading), String(this.picking), this.md5Url.trim().length)
    if (!this.alive || this.saving || this.loading || this.picking) return
    let normalized: string
    try { normalized = CatNodeSubscriptionCodec.normalizeUrl(this.md5Url) }
    catch (error) { this.showSaveError(extractErrorMsg(error)); return }
    this.saving = true; this.error = ''; this.stage = CatNodeSubscriptionStage.STOPPING
    const generation = ++this.generation
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      hilog.info(0, 'CatSubscription', 'save_stage %{public}s', this.stage)
      await CatNodeRuntime.shutdown()
      if (!this.alive || generation !== this.generation) return
      const sites = await CatNodeRuntime.sites(context, normalized, (stage: CatNodeSubscriptionStage) => {
        if (this.alive && generation === this.generation) {
          this.stage = stage
          hilog.info(0, 'CatSubscription', 'save_stage %{public}s', stage)
        }
      })
      if (!this.alive || generation !== this.generation) return
      if (sites.length === 0) throw new Error('订阅没有返回可用的影视来源')
      this.stage = CatNodeSubscriptionStage.SAVING
      const existing = this.sourceId.length > 0 ? await MediaSourceStore.getById(this.sourceId) : null
      if (this.sourceId.length > 0 && (existing === null || existing.providerType !== 'catnode')) throw new Error('该订阅已被删除')
      const config = new CatNodeSourceConfig()
      config.md5Url = normalized
      config.spiderKey = (this.originalUrl === normalized || this.originalUrl.length === 0) &&
        sites.some((site: CatNodeSite) => site.key === this.config.spiderKey) ? this.config.spiderKey :
        sites[0].key
      config.legacySpiderKey = this.config.legacySpiderKey
      const source = new MediaSourceInstance()
      source.id = existing === null ? createMediaSourceId('catnode') : existing.id
      config.iconUri = await this.storeIcon(context, source.id)
      if (!this.alive || generation !== this.generation) return
      source.providerType = 'catnode'; source.name = this.name.trim() || 'Cat 订阅'
      source.configJson = JSON.stringify(config)
      if (existing !== null) {
        source.enabled = existing.enabled; source.sortOrder = existing.sortOrder; source.createdAt = existing.createdAt
        await MediaSourceStore.update(source)
      } else await MediaSourceStore.add(source)
      if (!this.alive || generation !== this.generation) return
      hilog.info(0, 'CatSubscription', 'save_complete sites=%{public}d', sites.length)
      this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('Cat 订阅已保存'))
      this.getUIContext().getRouter().back()
    } catch (error) {
      if (this.alive && generation === this.generation) this.showSaveError(extractErrorMsg(error))
    }
    finally { if (this.alive && generation === this.generation) this.saving = false }
  }

  private showSaveError(message: string): void {
    this.error = message || this.label($r('app.string.cat_subscription_save_failed'))
    hilog.error(0, 'CatSubscription', 'save_failed stage=%{public}s message=%{public}s', this.stage, this.error)
    // 表单可能仍被键盘遮挡；即时提示与页面内错误同时保留。
    try { this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(this.error)) } catch (_) {}
  }

  private titleOptions(): HdsNavigationTitleBarOptions {
    const title = this.label(this.sourceId.length > 0 ? $r('app.string.cat_subscription_edit') : $r('app.string.cat_subscription_add'))
    const options = buildTitleBarOptions(title, this.materialLevel)
    options.content = { title: { mainTitle: title }, menu: { value: [{ content: {
      icon: new SymbolGlyphModifier($r('sys.symbol.save')), type: IconStyleMode.SMALL,
      componentId: 'cat-subscription-save', isEnabled: !this.saving && !this.loading && !this.picking,
      label: this.label(this.saving ? $r('app.string.cat_subscription_saving') : $r('app.string.cat_subscription_save')),
      action: (): void => { void this.save('toolbar') }
    } }] } }
    return options
  }

  private label(resource: Resource): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id) ?? ''
  }

  private stageLabel(): Resource {
    if (this.stage === CatNodeSubscriptionStage.STOPPING) return $r('app.string.cat_subscription_stopping')
    if (this.stage === CatNodeSubscriptionStage.DOWNLOADING) return $r('app.string.cat_subscription_downloading')
    if (this.stage === CatNodeSubscriptionStage.VERIFYING) return $r('app.string.cat_subscription_verifying')
    if (this.stage === CatNodeSubscriptionStage.STARTING) return $r('app.string.cat_subscription_starting')
    if (this.stage === CatNodeSubscriptionStage.READING) return $r('app.string.cat_subscription_reading')
    if (this.stage === CatNodeSubscriptionStage.SAVING) return $r('app.string.cat_subscription_saving')
    return $r('app.string.cat_subscription_checking')
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          Text() {
            Span($r('app.string.cat_subscription_name')).fontColor($r('app.color.text_primary'))
            Span($r('app.string.cat_subscription_optional')).fontColor($r('app.color.text_secondary'))
          }.fontSize(20).fontWeight(FontWeight.Medium).width('100%')
          TextInput({ text: this.name, placeholder: $r('app.string.cat_subscription_name_hint') })
            .width('100%').height(58).borderRadius(18).fontSize(17).padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.cat_subscription_field')).fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary')).enabled(!this.loading && !this.saving)
            .onChange((value: string) => this.name = value)
          Text() {
            Span($r('app.string.cat_subscription_address')).fontColor($r('app.color.text_primary'))
            Span('*').fontColor($r('app.color.status_error'))
          }.fontSize(18).fontWeight(FontWeight.Medium).width('100%').margin({ top: 2 })
          TextInput({ text: this.md5Url, placeholder: $r('app.string.cat_subscription_address_hint') })
            .width('100%').height(58).borderRadius(18).fontSize(16).padding({ left: 16, right: 16 })
            .type(InputType.URL).backgroundColor($r('app.color.cat_subscription_field'))
            .fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.text_secondary'))
            .enabled(!this.loading && !this.saving).onChange((value: string) => { this.md5Url = value; this.error = '' })
          if (this.saving) {
            Row({ space: 10 }) {
              LoadingProgress().width(20).height(20).color($r('app.color.accent_blue')).flexShrink(0)
              Text(this.stageLabel()).fontSize(14).fontColor($r('app.color.accent_blue')).layoutWeight(1)
            }.width('100%').padding({ top: 4, bottom: 4 })
          } else {
            Text($r('app.string.cat_subscription_notice'))
              .width('100%').fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
          }
          if (this.error.length > 0) Text(this.error).width('100%').fontSize(13).fontColor($r('app.color.status_error'))
          Text() {
            Span($r('app.string.cat_subscription_icon')).fontColor($r('app.color.text_primary'))
            Span($r('app.string.cat_subscription_optional')).fontColor($r('app.color.text_secondary'))
          }.fontSize(20).fontWeight(FontWeight.Medium).width('100%').margin({ top: 2 })
          Button({ type: ButtonType.Normal }) {
            Row({ space: 14 }) {
              if (this.iconUri.length > 0) Image(this.iconUri).width(28).height(28).borderRadius(8).objectFit(ImageFit.Cover)
              else SymbolGlyph($r('sys.symbol.picture')).fontSize(22).fontColor([$r('app.color.text_secondary')])
              Text($r('app.string.cat_subscription_icon_choose')).fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
              Text(this.iconUri.length > 0 ? $r('app.string.cat_subscription_icon_selected') : $r('app.string.cat_subscription_icon_default'))
                .fontSize(15).fontColor($r('app.color.text_secondary'))
            }.width('100%').padding({ left: 16, right: 16 })
          }.height(58).width('100%').borderRadius(18).backgroundColor($r('app.color.cat_subscription_field'))
            .enabled(!this.loading && !this.saving && !this.picking).onClick(() => { void this.pickIcon() })
          if (this.iconUri.length > 0) Button($r('app.string.cat_subscription_icon_reset')).fontSize(13).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary')).enabled(!this.saving).onClick(() => this.iconUri = '')
          Button(this.saving ? this.stageLabel() : $r('app.string.cat_subscription_download_save'))
            .id('cat-subscription-download-save').width('100%').height(50).borderRadius(18).fontSize(16)
            .backgroundColor($r('app.color.accent_blue')).fontColor($r('app.color.text_on_primary'))
            .enabled(!this.saving && !this.loading && !this.picking).margin({ top: 4 })
            .onClick(() => { void this.save('form') })
        }.width('100%').padding({ left: 22, right: 22, top: getTopSpacerHeight(this.topSafeHeight) + 12,
          bottom: this.bottomSafeHeight + 28 }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
    }.width('100%').height('100%').mode(NavigationMode.Stack).titleBar(this.titleOptions())
      .bindToScrollable([this.scroller]).titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
      .backgroundColor($r('app.color.cat_subscription_background'))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
