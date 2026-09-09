import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct EmbyDetailPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private sourceId: string = ''
  @State private itemId: string = ''
  @State private item: EmbyItem | null = null
  @State private loading: boolean = true
  @State private errorText: string = ''
  @State private playing: boolean = false
  private provider: EmbyProvider | null = null

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['itemId'] === 'string') this.itemId = (params['itemId'] as string).trim()
    }
    void this.loadItem()
  }

  build() {
    HdsNavigation() {
      if (this.loading) {
        LoadingProgress().width(36).height(36).margin({ top: 80 })
      } else if (this.errorText.length > 0 || this.item === null) {
        Column({ space: 12 }) {
          Text(this.errorText.length > 0 ? this.errorText : '媒体不存在')
            .fontSize(15).fontColor($r('app.color.text_secondary'))
          Button('返回').onClick(() => this.getUIContext().getRouter().back())
        }.width('100%').padding(32).alignItems(HorizontalAlign.Center)
      } else {
        this.DetailContent(this.item!)
      }
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.item === null ? '媒体详情' : this.item!.name, this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private DetailContent(item: EmbyItem): void {
    Scroll() {
      Column({ space: 16 }) {
        this.HeroImage(item)
        Column({ space: 8 }) {
          Text(item.name).fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          Text(this.metaText(item)).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          if (item.overview.length > 0) {
            Text(item.overview).fontSize(14).fontColor($r('app.color.text_primary'))
              .lineHeight(22).width('100%').textAlign(TextAlign.Start)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 10 }) {
          if (!item.isFolder) {
            Button(this.resumeLabel(item)).layoutWeight(1).height(46).fontSize(15)
              .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
              .onClick(() => this.play(item))
          } else {
            Button('浏览下级').layoutWeight(1).height(46).fontSize(15)
              .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
              .onClick(() => this.openChildren(item))
          }
          Button('返回').height(46).fontSize(14).backgroundColor($r('app.color.button_ghost_bg'))
            .onClick(() => this.getUIContext().getRouter().back())
        }.width('100%')
        if (!item.isFolder) {
          Text('播放版本由 Emby PlaybackInfo 与当前播放策略自动选择')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }
      }.width('100%').padding(16)
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }

  @Builder
  private HeroImage(item: EmbyItem): void {
    Image(this.imageUrl(item)).width('100%').height(210).objectFit(ImageFit.Cover)
      .borderRadius(16).backgroundColor($r('app.color.button_ghost_bg'))
  }

  private async loadItem(): Promise<void> {
    this.loading = true
    this.errorText = ''
    try {
      if (this.sourceId.length === 0 || this.itemId.length === 0) throw new Error('媒体参数无效')
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (provider === null || !(provider instanceof EmbyProvider)) throw new Error('Emby 来源不可用')
      this.provider = provider
      this.item = await provider.getItemRaw(this.itemId)
      if (this.item === null) throw new Error('媒体不存在或已被删除')
    } catch (err) {
      this.item = null
      this.errorText = err instanceof Error ? err.message : '媒体详情读取失败'
    } finally {
      this.loading = false
    }
  }

  private imageUrl(item: EmbyItem): string {
    return this.itemProvider() === null ? '' : this.itemProvider()!.imageUrlFor(item, 900)
  }

  private itemProvider(): EmbyProvider | null {
    return this.provider
  }

  private metaText(item: EmbyItem): string {
    const parts: string[] = [EmbyItem.typeLabel(item.type)]
    if (item.productionYear > 0) parts.push(String(item.productionYear))
    if (item.durationMs() > 0) parts.push(this.formatDuration(item.durationMs()))
    return parts.join(' · ')
  }

  private resumeLabel(item: EmbyItem): string {
    return item.resumePositionMs() > 0 ? '继续播放' : '播放'
  }

  private async play(item: EmbyItem): Promise<void> {
    if (this.playing) return
    this.playing = true
    try {
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, item, [item])
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法播放该媒体' })
    } finally {
      this.playing = false
    }
  }

  private openChildren(item: EmbyItem): void {
    void this.getUIContext().getRouter().pushUrl({
      url: 'pages/emby/EmbyLibraryPage',
      params: { sourceId: this.sourceId, parentId: item.id, title: item.name }
    })
  }

  private formatDuration(durationMs: number): string {
    const totalMinutes = Math.floor(durationMs / 60000)
    const hours = Math.floor(totalMinutes / 60)
    const minutes = totalMinutes % 60
    return hours > 0 ? hours + ' 小时 ' + minutes + ' 分钟' : minutes + ' 分钟'
  }
}
