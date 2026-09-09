import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaItem } from '../../core/media/MediaItem'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct SourceBrowserPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private sourceId: string = ''
  @State private parentId: string = ''
  @State private title: string = '媒体源'
  @State private items: MediaItem[] = []
  @State private loading: boolean = true
  @State private errorText: string = ''
  private loadGeneration: number = 0

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['parentId'] === 'string') this.parentId = (params['parentId'] as string).trim()
      if (typeof params['title'] === 'string' && (params['title'] as string).trim().length > 0) {
        this.title = (params['title'] as string).trim()
      }
    }
    void this.loadItems()
  }

  build() {
    HdsNavigation() {
      if (this.loading) {
        LoadingProgress().width(36).height(36).margin({ top: 60 })
      } else if (this.errorText.length > 0) {
        Column({ space: 12 }) {
          Text(this.errorText).fontSize(15).fontColor($r('app.color.text_secondary'))
          Button('重试').onClick(() => this.loadItems())
        }.width('100%').padding(32).alignItems(HorizontalAlign.Center)
      } else if (this.items.length === 0) {
        Text('此目录暂无媒体').fontSize(15).fontColor($r('app.color.text_secondary')).margin({ top: 60 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.items, (item: MediaItem) => { this.ItemCard(item) })
          }.width('100%').padding(16)
        }.width('100%').height('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.title, this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private ItemCard(item: MediaItem): void {
    Row({ space: 12 }) {
      SymbolGlyph(item.browsable ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle'))
        .fontSize(26).fontColor([$r('app.color.accent_blue')])
      Column({ space: 4 }) {
        Text(item.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        if (item.subtitle.length > 0) Text(item.subtitle).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.text_secondary')])
    }.width('100%').padding(14).borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .onClick(() => this.openItem(item))
  }

  private async loadItems(): Promise<void> {
    const generation = ++this.loadGeneration
    this.loading = true
    this.errorText = ''
    try {
      if (this.sourceId.length === 0) throw new Error('媒体源参数无效')
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (generation !== this.loadGeneration) return
      if (provider === null) throw new Error('媒体源不可用或已停用')
      const items = await provider.getChildren(this.parentId)
      if (generation !== this.loadGeneration) return
      this.items = items
    } catch (err) {
      if (generation !== this.loadGeneration) return
      this.items = []
      this.errorText = err instanceof Error ? err.message : '媒体目录读取失败'
    } finally {
      if (generation === this.loadGeneration) this.loading = false
    }
  }

  private async openItem(item: MediaItem): Promise<void> {
    try {
      if (this.sourceId.length === 0) throw new Error('媒体源参数无效')
      if (item.browsable) {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/sources/SourceBrowserPage', params: { sourceId: this.sourceId, parentId: item.id, title: item.title }
        })
        return
      }
      if (!item.playable) {
        promptAction.showToast({ message: '该文件类型暂不支持播放' })
        return
      }
      const playable = this.items.filter((value: MediaItem) => value.playable)
      await ProviderPlaybackLauncher.open(this.getUIContext(), item, playable)
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法打开媒体' })
    }
  }
}
