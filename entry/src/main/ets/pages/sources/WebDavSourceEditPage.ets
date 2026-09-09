import { promptAction } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaSourceInstance, createMediaSourceId } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { WebDavSourceConfig, WebDavSourceConfigCodec } from '../../providers/webdav/WebDavSourceConfig'
import { WebDavClient } from '../../providers/webdav/WebDavClient'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct WebDavSourceEditPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private sourceId: string = ''
  @State private name: string = 'WebDAV'
  @State private baseUrl: string = ''
  @State private userName: string = ''
  @State private password: string = ''
  @State private rootPath: string = '/'
  @State private saving: boolean = false
  private loadGeneration: number = 0

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') {
      this.sourceId = (params['sourceId'] as string).trim()
    }
    void this.loadConfig()
  }

  build() {
    HdsNavigation() {
      Scroll() {
        Column({ space: 12 }) {
          this.InputField('名称', this.name, '例如家庭 NAS', (value: string) => this.name = value)
          this.InputField('服务器地址', this.baseUrl, 'https://example.com/webdav', (value: string) => this.baseUrl = value)
          this.InputField('根路径', this.rootPath, '/', (value: string) => this.rootPath = value)
          this.InputField('用户名', this.userName, '可选', (value: string) => this.userName = value)
          this.InputField('密码', this.password, '可选', (value: string) => this.password = value)
          Button(this.saving ? '保存中…' : '测试并保存').width('100%').height(48).enabled(!this.saving)
            .backgroundColor($r('app.color.accent_blue')).fontColor($r('app.color.text_on_primary'))
            .onClick(() => this.save())
        }.width('100%').padding(16)
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.sourceId.length > 0 ? '编辑 WebDAV' : '添加 WebDAV', this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private InputField(label: string, value: string, placeholder: string, onChange: (value: string) => void): void {
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: value, placeholder: placeholder }).width('100%').height(46)
        .backgroundColor($r('app.color.card_background')).borderRadius(10).onChange(onChange)
    }.width('100%')
  }

  private async loadConfig(): Promise<void> {
    const generation = ++this.loadGeneration
    if (this.sourceId.length === 0) return
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      if (generation !== this.loadGeneration) return
      const config = source === null ? null : WebDavSourceConfigCodec.decode(source.configJson)
      if (source !== null) this.name = source.name
      if (config !== null) {
        this.baseUrl = config.baseUrl
        this.userName = config.userName
        this.password = config.password
        this.rootPath = config.rootPath
      }
    } catch (_err) {
      // Keep the editable defaults when a stale or malformed source cannot be read.
    }
  }

  private async save(): Promise<void> {
    if (this.baseUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入 WebDAV 服务器地址' })
      return
    }
    ++this.loadGeneration
    this.saving = true
    try {
      const normalizedSourceId = this.sourceId.trim()
      const config = new WebDavSourceConfig()
      config.baseUrl = this.baseUrl.trim()
      config.userName = this.userName
      config.password = this.password
      config.rootPath = this.rootPath.trim().length > 0 ? this.rootPath.trim() : '/'
      if (!WebDavSourceConfigCodec.normalize(config)) {
        throw new Error('服务器地址必须以 http:// 或 https:// 开头')
      }
      await new WebDavClient(config).list('')
      const existing = normalizedSourceId.length > 0 ? await MediaSourceStore.getById(normalizedSourceId) : null
      const source = new MediaSourceInstance()
      source.id = normalizedSourceId.length > 0 ? normalizedSourceId : createMediaSourceId('webdav')
      source.providerType = 'webdav'
      source.name = this.name.trim().length > 0 ? this.name.trim() : 'WebDAV'
      source.enabled = true
      source.configJson = WebDavSourceConfigCodec.encode(config)
      if (existing !== null) {
        // 编辑配置时保持来源在列表中的位置，不因新建临时对象而跳到首位。
        source.sortOrder = existing.sortOrder
        source.createdAt = existing.createdAt
      }
      if (normalizedSourceId.length > 0) await MediaSourceStore.update(source)
      else await MediaSourceStore.add(source)
      promptAction.showToast({ message: 'WebDAV 已保存' })
      await this.getUIContext().getRouter().back()
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : 'WebDAV 连接失败' })
    } finally { this.saving = false }
  }
}
