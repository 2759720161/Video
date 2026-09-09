import { promptAction } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyClient } from '../../providers/emby/EmbyClient'
import { EmbyServerConfig } from '../../providers/emby/EmbyModels'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { EmbySourceConfigCodec } from '../../providers/emby/EmbySourceConfig'
import {
  buildTitleBarOptions,
  getBottomSpacerHeight,
  getTopSpacerHeight,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

@Entry
@Component
struct EmbySourceEditPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private serverUrl: string = ''
  @State private userName: string = ''
  @State private password: string = ''
  @State private connectedConfig: EmbyServerConfig | null = null
  @State private connecting: boolean = false
  @State private sourceId: string = ''
  private loadGeneration: number = 0
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') {
      this.sourceId = (params['sourceId'] as string).trim()
    }
    this.loadConfig()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          this.ConnectionStatus()
          this.LoginForm()
          this.SecurityHint()
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('Emby 媒体源', this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private ConnectionStatus(): void {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(44)
          .height(44)
          .fill(this.connectedConfig !== null ? $r('app.color.status_success') : $r('app.color.text_secondary'))
          .opacity(0.14)
        SymbolGlyph(this.connectedConfig !== null ? $r('sys.symbol.checkmark_circle_fill') :
          $r('sys.symbol.play_round_rectangle'))
          .fontSize(25)
          .fontColor([this.connectedConfig !== null ? $r('app.color.status_success') :
            $r('app.color.text_secondary')])
      }
      .width(48)
      .height(48)

      Column({ space: 3 }) {
        Text(this.connectedConfig !== null ? this.connectedConfig!.serverName : '尚未连接')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.connectionSubtitle())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
  }

  @Builder
  private LoginForm(): void {
    Column({ space: 14 }) {
      Text('连接信息')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 4, top: 10 })

      Column({ space: 12 }) {
        this.FormLabel('服务器地址')
        TextInput({ text: this.serverUrl, placeholder: '例如 192.168.1.10:8096' })
          .width('100%')
          .height(48)
          .fontSize(15)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(10)
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => this.serverUrl = value)

        this.FormLabel('用户名')
        TextInput({ text: this.userName, placeholder: 'Emby 用户名' })
          .width('100%')
          .height(48)
          .fontSize(15)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(10)
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => this.userName = value)

        this.FormLabel('密码')
        TextInput({ text: this.password, placeholder: '无密码时可留空' })
          .type(InputType.Password)
          .showPasswordIcon(true)
          .width('100%')
          .height(48)
          .fontSize(15)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(10)
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => this.password = value)

        Button(this.connecting ? '连接中…' : (this.connectedConfig === null ? '连接 Emby' : '重新连接'))
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_primary'))
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(12)
          .enabled(!this.connecting)
          .onClick(() => this.connect())

        if (this.connectedConfig !== null) {
          Button('浏览媒体库')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_on_primary'))
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(12)
            .onClick(() => this.openLibrary(false))

          Button('断开连接')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.status_error'))
            .backgroundColor(Color.Transparent)
            .onClick(() => this.disconnect())
        }
      }
      .width('100%')
      .padding(16)
      .borderRadius(14)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
  }

  @Builder
  private FormLabel(text: string): void {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
  }

  @Builder
  private SecurityHint(): void {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.lock')).fontSize(16).fontColor([$r('app.color.text_secondary')])
      Text('密码仅用于本次登录；应用只保存 Emby 返回的访问令牌。远程访问建议使用 HTTPS。')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 14, bottom: 8 })
    .alignItems(VerticalAlign.Top)
  }

  private async loadConfig(): Promise<void> {
    const generation = ++this.loadGeneration
    try {
      if (this.sourceId.length > 0) {
        const source = await MediaSourceStore.getById(this.sourceId)
        if (generation !== this.loadGeneration) return
        this.connectedConfig = source === null ? null : EmbySourceConfigCodec.decode(source.configJson)
      }
      if (generation !== this.loadGeneration) return
      if (this.connectedConfig !== null) {
        this.serverUrl = this.connectedConfig!.baseUrl
        this.userName = this.connectedConfig!.userName
      }
    } catch (_err) {
      if (generation === this.loadGeneration) this.connectedConfig = null
    }
  }

  private async connect(): Promise<void> {
    if (this.serverUrl.trim().length === 0 || this.userName.trim().length === 0) {
      promptAction.showToast({ message: '请输入服务器地址和用户名' })
      return
    }
    ++this.loadGeneration
    this.connecting = true
    try {
      const deviceId = this.connectedConfig !== null ? this.connectedConfig!.deviceId : ''
      const config = await EmbyClient.login(this.serverUrl, this.userName, this.password, deviceId)
      const sourceId = await MediaSourceStore.upsertEmby(config, this.sourceId)
      this.sourceId = sourceId
      this.connectedConfig = config
      this.serverUrl = config.baseUrl
      this.userName = config.userName
      this.password = ''
      promptAction.showToast({ message: '已连接 ' + config.serverName })
      await this.openLibrary(true, sourceId)
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : 'Emby 连接失败' })
    } finally {
      this.connecting = false
    }
  }

  private async openLibrary(replaceCurrent: boolean, sourceId: string = ''): Promise<void> {
    try {
      const pageRouter = this.getUIContext().getRouter()
      if (replaceCurrent) {
        await pageRouter.replaceUrl({ url: 'pages/emby/EmbyLibraryPage', params: { sourceId: sourceId } })
      } else {
        await pageRouter.pushUrl({ url: 'pages/emby/EmbyLibraryPage', params: { sourceId: sourceId } })
      }
    } catch (_err) {
      promptAction.showToast({ message: '媒体库页面打开失败，请返回后从 Emby 卡片重试' })
    }
  }

  private async disconnect(): Promise<void> {
    const config = this.connectedConfig
    if (config !== null) {
      try {
        await new EmbyClient(config).logout()
      } catch (_err) {}
    }
    if (this.sourceId.length > 0) await MediaSourceStore.remove(this.sourceId)
    this.connectedConfig = null
    this.password = ''
    promptAction.showToast({ message: '已断开 Emby' })
  }

  private connectionSubtitle(): string {
    if (this.connectedConfig === null) {
      return '登录后即可浏览媒体库并直接播放'
    }
    const config = this.connectedConfig!
    const version = config.serverVersion.length > 0 ? ' · ' + config.serverVersion : ''
    return config.userName + version + '\n' + config.baseUrl
  }
}
