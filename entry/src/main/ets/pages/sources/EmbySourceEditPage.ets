import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { promptAction } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyClient } from '../../providers/emby/EmbyClient'
import { EmbyServerConfig } from '../../providers/emby/EmbyModels'
import { EmbyConnectionAddress } from '../../providers/emby/EmbyConnectionAddress'
import { EmbySourceConfigCodec } from '../../providers/emby/EmbySourceConfig'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { SecureCredentialStore } from '../../services/security/SecureCredentialStore'
import {
  buildTitleBarOptions, getTopSpacerHeight, getManagementContentMaxWidth,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

class EmbyFormInputModifier implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(instance: TextInputAttribute): void {
    instance.height(48).fontSize(15).fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_hint')).caretColor($r('app.color.accent_blue'))
      .backgroundColor($r('app.color.page_background')).borderRadius(24)
      .padding({ left: 16, right: 16 })
  }
}

@Entry
@Component
struct EmbySourceEditPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private displayName: string = ''
  @State private protocol: string = 'http'
  @State private host: string = ''
  @State private port: string = ''
  @State private path: string = ''
  @State private userName: string = ''
  @State private password: string = ''
  @State private busy: boolean = false
  @State private loading: boolean = false
  @State private saving: boolean = false
  @State private sourceId: string = ''
  @State private connectionMessage: string = ''
  @State private connectionFailed: boolean = false
  private connectedConfig: EmbyServerConfig | null = null
  private verifiedConfig: EmbyServerConfig | null = null
  private loadGeneration: number = 0
  private scroller: Scroller = new Scroller()
  private inputStyle: EmbyFormInputModifier = new EmbyFormInputModifier()

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') {
      this.sourceId = (params['sourceId'] as string).trim()
    }
    void this.loadConfig()
  }

  aboutToDisappear(): void {
    ++this.loadGeneration
    this.password = ''
    this.verifiedConfig = null
    this.connectedConfig = null
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          this.EmbyIntro()
          this.NameForm()
          this.AddressForm()
          this.AccountForm()
          if (this.connectionMessage.length > 0) {
            this.ConnectionResult()
          }
          this.FormActions()
          this.SecurityHint()
        }
        .width('100%')
        .constraintSize({ maxWidth: getManagementContentMaxWidth(this.screenWidthVp) || '100%' })
        .padding({ left: 16, right: 16, top: getTopSpacerHeight(this.topSafeHeight) + 12,
          bottom: this.bottomSafeHeight + 28 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%').height('100%').align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions(this.sourceId.length > 0 ? '编辑 Emby' : '添加 Emby', this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Styles
  private formCard() {
    .width('100%').padding(16).borderRadius(24)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 3 })
  }

  @Builder
  private EmbyIntro(): void {
    Row({ space: 16 }) {
      Stack({ alignContent: Alignment.Center }) {
        Rect().width(44).height(44).fill($r('app.color.status_success'))
          .rotate({ angle: 45 })
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(27).fontColor([Color.White])
      }.width(60).height(64).flexShrink(0)
      Column({ space: 6 }) {
        Text('Emby').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text('连接你的服务器，畅享媒体库中的影视内容')
          .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.formCard().constraintSize({ minHeight: 104 })
  }

  @Builder
  private NameForm(): void {
    Row({ space: 12 }) {
      this.RowLabel('名称')
      TextInput({ text: this.displayName, placeholder: '服务器名称（可选）' })
        .attributeModifier(this.inputStyle).layoutWeight(1).enabled(!this.busy && !this.loading)
        .onChange((value: string) => this.displayName = value)
    }.formCard()
  }

  @Builder
  private AddressForm(): void {
    Column({ space: 14 }) {
      this.SectionTitle('服务器地址')
      Column({ space: 8 }) {
        this.FieldLabel('主机地址', false)
        TextInput({ text: this.host, placeholder: '192.168.1.10 或 emby.example.com' })
          .attributeModifier(this.inputStyle).width('100%').enabled(!this.busy && !this.loading)
          .onChange((value: string) => { this.host = value; this.invalidateVerification() })
          .onBlur(() => this.recognizeAddress(false))
        Text('可直接粘贴完整地址，自动识别协议、端口和路径')
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 2 })
      }.width('100%').alignItems(HorizontalAlign.Start)

      Row({ space: 12 }) {
        Column({ space: 8 }) {
          this.FieldLabel('协议', false)
          Select([{ value: 'HTTP' }, { value: 'HTTPS' }])
            .selected(this.protocol === 'https' ? 1 : 0).value(this.protocol.toUpperCase())
            .font({ size: 15, weight: FontWeight.Medium }).fontColor($r('app.color.text_primary'))
            .width('100%').height(48).borderRadius(24)
            .backgroundColor($r('app.color.page_background'))
            .enabled(!this.busy && !this.loading)
            .onSelect((index: number) => {
              this.protocol = index === 1 ? 'https' : 'http'
              this.invalidateVerification()
            })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 8 }) {
          this.FieldLabel('端口', true)
          TextInput({ text: this.port, placeholder: '如 8096' })
            .attributeModifier(this.inputStyle).type(InputType.Number).width('100%')
            .enabled(!this.busy && !this.loading)
            .onChange((value: string) => { this.port = value; this.invalidateVerification() })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Top)

      Column({ space: 8 }) {
        this.FieldLabel('路径', true)
        TextInput({ text: this.path, placeholder: '/emby 或反向代理子路径' })
          .attributeModifier(this.inputStyle).width('100%').enabled(!this.busy && !this.loading)
          .onChange((value: string) => { this.path = value; this.invalidateVerification() })
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.formCard().alignItems(HorizontalAlign.Start)
  }

  @Builder
  private AccountForm(): void {
    Column({ space: 14 }) {
      this.SectionTitle('账号信息')
      Row({ space: 12 }) {
        this.RowLabel('用户名')
        TextInput({ text: this.userName, placeholder: '登录用户名' })
          .attributeModifier(this.inputStyle).layoutWeight(1).enabled(!this.busy && !this.loading)
          .onChange((value: string) => { this.userName = value; this.invalidateVerification() })
      }.width('100%')
      Row({ space: 12 }) {
        this.RowLabel('密码')
        TextInput({ text: this.password, placeholder: this.passwordPlaceholder() })
          .attributeModifier(this.inputStyle).type(InputType.Password).showPasswordIcon(true)
          .layoutWeight(1).enabled(!this.busy && !this.loading)
          .onChange((value: string) => { this.password = value; this.invalidateVerification() })
      }.width('100%')
    }.formCard().alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SectionTitle(title: string): void {
    Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      .width('100%').padding({ left: 2 })
  }

  @Builder
  private RowLabel(title: string): void {
    Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      .width(52).flexShrink(0).maxLines(1)
  }

  @Builder
  private FieldLabel(title: string, optional: boolean): void {
    Row({ space: 4 }) {
      Text(title).fontSize(13).fontColor($r('app.color.text_secondary'))
      if (optional) {
        Text('（可选）').fontSize(12).fontColor($r('app.color.text_hint'))
      }
    }.width('100%').padding({ left: 2 })
  }

  @Builder
  private ConnectionResult(): void {
    Row({ space: 8 }) {
      SymbolGlyph(this.connectionFailed ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.checkmark_circle_fill'))
        .fontSize(18).fontColor([this.connectionFailed ? $r('app.color.status_error') : $r('app.color.status_success')])
        .flexShrink(0)
      Text(this.connectionMessage).fontSize(13)
        .fontColor(this.connectionFailed ? $r('app.color.status_error') : $r('app.color.status_success'))
        .layoutWeight(1)
    }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Top)
  }

  @Builder
  private FormActions(): void {
    Row({ space: 12 }) {
      Button(this.busy && !this.saving ? '测试中…' : '测试连接')
        .layoutWeight(1).height(50).borderRadius(25).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') })
        .enabled(!this.busy && !this.loading).onClick(() => { void this.submit(false) })
      Button(this.busy && this.saving ? '保存中…' : '保存')
        .layoutWeight(1).height(50).borderRadius(25).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
        .enabled(!this.busy && !this.loading).onClick(() => { void this.submit(true) })
    }.width('100%').margin({ top: 4 })
  }

  @Builder
  private SecurityHint(): void {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.lock')).fontSize(14).fontColor([$r('app.color.text_secondary')]).flexShrink(0)
      Text('密码不在本地保存，仅安全存储登录令牌。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
    }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Top)
  }

  private invalidateVerification(): void {
    this.verifiedConfig = null
    this.connectionMessage = ''
    this.connectionFailed = false
  }

  private applyAddress(address: EmbyConnectionAddress): void {
    this.protocol = address.protocol
    this.host = address.host
    this.port = address.port
    this.path = address.path
  }

  private recognizeAddress(showError: boolean): void {
    const value = this.host.trim()
    // Plain hosts retain the protocol, port and path selected in the form.
    if (value.length === 0 || (!value.includes('/') && !value.includes(':'))) return
    if (/^\[[0-9a-f:.]+\]$/i.test(value)) return
    try {
      this.applyAddress(EmbyConnectionAddress.parse(value, this.protocol))
      this.invalidateVerification()
    } catch (err) {
      if (showError) throw new Error(err instanceof Error ? err.message : '服务器地址无法识别')
    }
  }

  private async loadConfig(): Promise<void> {
    if (this.sourceId.length === 0) return
    const generation = ++this.loadGeneration
    this.loading = true
    try {
      const source = await MediaSourceStore.getById(this.sourceId)
      if (source === null || source.providerType !== 'emby') throw new Error('未找到 Emby 配置')
      const config = EmbySourceConfigCodec.decode(source.configJson)
      if (config === null) throw new Error('Emby 配置无法读取')
      const credential = await SecureCredentialStore.getInstance().get(this.sourceId)
      if (generation !== this.loadGeneration) return
      if (credential !== null && credential.providerType === 'emby') {
        config.accessToken = credential.values['accessToken'] ?? config.accessToken
      }
      this.connectedConfig = config
      this.displayName = source.name
      this.applyAddress(EmbyConnectionAddress.parse(config.baseUrl))
      this.userName = config.userName
    } catch (err) {
      if (generation === this.loadGeneration) {
        this.connectionFailed = true
        this.connectionMessage = err instanceof Error ? err.message : '配置读取失败，请重新填写'
      }
    } finally {
      if (generation === this.loadGeneration) this.loading = false
    }
  }

  private canReuseSavedLogin(serverUrl: string): boolean {
    const current = this.connectedConfig
    return current !== null && current.isValid() &&
      EmbyClient.normalizeBaseUrl(serverUrl) === current.baseUrl && this.userName.trim() === current.userName
  }

  private passwordPlaceholder(): string {
    try {
      const serverUrl = EmbyConnectionAddress.build(this.protocol, this.host, this.port, this.path)
      if (this.canReuseSavedLogin(serverUrl)) return '留空保留现有登录'
    } catch (_err) {}
    return '无密码可留空'
  }

  private async authenticate(serverUrl: string, verifyAgain: boolean = false): Promise<EmbyServerConfig> {
    if (this.verifiedConfig !== null) {
      if (verifyAgain) await new EmbyClient(this.verifiedConfig).getLibraries()
      return this.verifiedConfig.copy()
    }
    const current = this.connectedConfig
    if (current !== null && this.password.length === 0 && this.canReuseSavedLogin(serverUrl)) {
      // Editing the display name does not require re-entering a saved password.
      await new EmbyClient(current).getLibraries()
      return current.copy()
    }
    return EmbyClient.login(serverUrl, this.userName.trim(), this.password, current !== null ? current.deviceId : '')
  }

  private async submit(save: boolean): Promise<void> {
    if (this.busy || this.loading) return
    let serverUrl: string
    try {
      this.recognizeAddress(true)
      serverUrl = EmbyConnectionAddress.build(this.protocol, this.host, this.port, this.path)
      if (this.userName.trim().length === 0) throw new Error('请输入用户名')
    } catch (err) {
      this.connectionFailed = true
      this.connectionMessage = err instanceof Error ? err.message : '请检查服务器信息'
      return
    }
    const generation = ++this.loadGeneration
    this.busy = true
    this.saving = save
    this.connectionMessage = ''
    try {
      const config = await this.authenticate(serverUrl, !save)
      if (generation !== this.loadGeneration) return
      this.verifiedConfig = config.copy()
      this.connectionFailed = false
      if (!save) {
        this.connectionMessage = '连接成功 · ' + (config.serverName || 'Emby')
        return
      }
      await MediaSourceStore.upsertEmby(config, this.sourceId, this.displayName)
      if (generation !== this.loadGeneration) return
      this.password = ''
      promptAction.showToast(buildDetailToastOptions(this.sourceId.length > 0 ? 'Emby 配置已保存' : 'Emby 已添加'))
      await this.getUIContext().getRouter().back()
    } catch (err) {
      if (generation === this.loadGeneration) {
        this.verifiedConfig = null
        this.connectionFailed = true
        this.connectionMessage = err instanceof Error ? err.message : (save ? '保存失败，请重试' : '连接失败，请重试')
      }
    } finally {
      if (generation === this.loadGeneration) {
        this.busy = false
        this.saving = false
      }
    }
  }
}
