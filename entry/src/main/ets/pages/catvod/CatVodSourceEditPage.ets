import { promptAction } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaSourceInstance, createMediaSourceId } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { CatVodClient } from '../../providers/catvod/CatVodClient'
import { CatVodSourceConfig, CatVodSourceConfigCodec, CATVOD_DEFAULT_API } from '../../providers/catvod/CatVodSourceConfig'
import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct CatVodSourceEditPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private sourceId: string = ''
  @State private name: string = '天堂采集'
  @State private apiUrl: string = CATVOD_DEFAULT_API
  @State private referer: string = ''
  @State private saving: boolean = false
  @State private loading: boolean = false
  private config: CatVodSourceConfig = new CatVodSourceConfig()
  private generation: number = 0
  private alive: boolean = true

  aboutToAppear(): void {
    this.alive = true
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') this.sourceId = params['sourceId'] as string
    void this.load()
  }
  aboutToDisappear(): void { this.alive = false; this.generation++ }

  build() {
    HdsNavigation() {
      Scroll() {
        Column({ space: 18 }) {
          Text($r('app.string.catvod_source_intro')).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
          this.Field($r('app.string.catvod_source_name'), this.name, $r('app.string.catvod_source_name_hint'),
            (value: string) => this.name = value)
          this.Field($r('app.string.catvod_source_address'), this.apiUrl, $r('app.string.catvod_source_address_hint'),
            (value: string) => this.apiUrl = value)
          this.Field($r('app.string.catvod_referer'), this.referer, $r('app.string.catvod_optional'),
            (value: string) => this.referer = value)
          Button(this.saving ? $r('app.string.catvod_saving') : $r('app.string.catvod_test_save'))
            .width('100%').height(48).enabled(!this.saving && !this.loading)
            .backgroundColor($r('app.color.accent_blue')).fontColor($r('app.color.text_on_primary'))
            .onClick(() => { void this.save() })
        }.width('100%').padding(20).enabled(!this.loading && !this.saving)
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.sourceId.length > 0 ? '编辑猫源' : '添加猫源', this.materialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private Field(label: Resource, value: string, placeholder: Resource, change: (value: string) => void): void {
    Column({ space: 7 }) {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: value, placeholder: placeholder }).height(48).width('100%').borderRadius(12)
        .backgroundColor($r('app.color.card_background')).onChange(change)
    }.width('100%')
  }

  private async load(): Promise<void> {
    if (this.sourceId.length === 0) return
    const generation = ++this.generation
    this.loading = true
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      if (!this.alive || generation !== this.generation) return
      if (source === null || source.providerType !== 'catvod') throw new Error('该来源已不可用')
      const config = CatVodSourceConfigCodec.decode(source.configJson)
      if (config === null) throw new Error('来源配置无效')
      this.config = config; this.name = source.name; this.apiUrl = config.apiUrl; this.referer = config.referer
    } catch (err) {
      if (this.alive && generation === this.generation) promptAction.showToast(buildDetailToastOptions(err instanceof Error ? err.message : '读取来源失败'))
    } finally { if (this.alive && generation === this.generation) this.loading = false }
  }

  private async save(): Promise<void> {
    if (this.saving || this.loading) return
    this.saving = true
    const generation = ++this.generation
    try {
      const config = new CatVodSourceConfig()
      config.apiUrl = this.apiUrl; config.referer = this.referer; config.userAgent = this.config.userAgent
      if (!CatVodSourceConfigCodec.normalize(config)) throw new Error('请填写有效的采集来源地址；源程序和校验文件不能直接使用')
      const categories = await new CatVodClient(config).categories()
      if (categories.length === 0) throw new Error('来源没有返回可用分类，请检查地址')
      if (!this.alive || generation !== this.generation) return
      const existing = this.sourceId.length > 0 ? await MediaSourceStore.getById(this.sourceId) : null
      if (this.sourceId.length > 0 && (existing === null || existing.providerType !== 'catvod')) throw new Error('该来源已被删除')
      const source = new MediaSourceInstance()
      source.id = existing === null ? createMediaSourceId('catvod') : existing.id
      source.providerType = 'catvod'; source.name = this.name.trim() || '猫源'
      source.configJson = CatVodSourceConfigCodec.encode(config)
      if (existing !== null) {
        source.enabled = existing.enabled; source.sortOrder = existing.sortOrder; source.createdAt = existing.createdAt
        await MediaSourceStore.update(source)
      } else { await MediaSourceStore.add(source) }
      if (!this.alive || generation !== this.generation) return
      promptAction.showToast(buildDetailToastOptions('猫源已保存'))
      this.getUIContext().getRouter().back()
    } catch (err) {
      if (this.alive && generation === this.generation) promptAction.showToast(buildDetailToastOptions(err instanceof Error ? err.message : '来源保存失败'))
    } finally { if (this.alive && generation === this.generation) this.saving = false }
  }
}
