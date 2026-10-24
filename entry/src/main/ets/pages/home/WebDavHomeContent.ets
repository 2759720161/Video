import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { common } from '@kit.AbilityKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaItem } from '../../core/media/MediaItem'
import type { MediaProvider } from '../../providers/base/MediaProvider'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { PageEmptyState } from '../../components/common/PageEmptyState'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { PLAYBACK_HISTORY_VERSION_KEY } from '../../store/PlaybackHistoryChangeSignal'
import { getTopSpacerHeight } from '../../utils/HdsPageStyle'

@Component
export struct WebDavHomeContent {
  @Prop source: MediaSourceInstance = new MediaSourceInstance()
  @Prop @Watch('reload') isActive: boolean = true
  @Prop @Watch('reload') refreshToken: number = 0
  @StorageLink(PLAYBACK_HISTORY_VERSION_KEY) @Watch('reload') historyVersion: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @State private items: MediaItem[] = []
  @State private resume: MediaItem[] = []
  @State private loading: boolean = true
  @State private error: string = ''
  @State private playing: boolean = false
  scroller: Scroller = new Scroller()
  private generation: number = 0

  aboutToAppear(): void { void this.reload() }
  aboutToDisappear(): void { this.generation++ }
  private async reload(): Promise<void> {
    const generation = ++this.generation
    if (!this.isActive) return
    this.loading = this.items.length === 0
    this.error = ''
    try {
      const provider = await ProviderRegistry.get(this.source.id, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (generation !== this.generation) return
      if (provider === null) throw new Error('Service unavailable')
      await Promise.all([this.loadFiles(provider, generation), this.loadResume(provider, generation)])
    } catch (_) { if (generation === this.generation) this.error = '连接暂不可用，请检查地址和账号' }
    finally { if (generation === this.generation) this.loading = false }
  }
  private async loadFiles(provider: MediaProvider, generation: number): Promise<void> {
    const items = await provider.getChildren('')
    if (generation === this.generation) { this.items = items; this.loading = false }
  }
  private async loadResume(provider: MediaProvider, generation: number): Promise<void> {
    try { const items = await provider.getResumeItems(6); if (generation === this.generation) this.resume = items }
    catch (_) {}
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        if (this.error.length > 0) {
          PageErrorState({ title: 'WebDAV 暂不可用', message: this.error, onRetry: () => { void this.reload() } })
        }
        if (this.loading) PageLoadingState({ title: '正在读取文件', minHeight: 220 })
        if (this.resume.length > 0) {
          MediaSectionHeader({ title: '继续观看', actionText: '继续播放', chevronAction: true, onAction: () => {
            void this.getUIContext().getRouter().pushUrl({ url: 'pages/local/ContinueWatchingPage',
              params: { view: 'continue', sourceId: this.source.id, scopeName: this.source.name } })
          } })
          Column() { ForEach(this.resume, (item: MediaItem) => this.FileRow(item), (item: MediaItem) => 'resume:' + item.id) }
            .width('100%').backgroundColor($r('app.color.card_background')).borderRadius(20)
        }
        Row() {
          Text('文件').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).layoutWeight(1)
          Button('全部').height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.accent_blue'))
            .onClick(() => this.browse(''))
        }.width('100%')
        Column() {
          ForEach(this.items.slice(0, 30), (item: MediaItem) => this.FileRow(item), (item: MediaItem) => item.id)
        }.width('100%').backgroundColor($r('app.color.card_background')).borderRadius(20)
        if (!this.loading && this.error.length === 0 && this.items.length === 0) {
          PageEmptyState({ title: '此目录暂无文件', minHeight: 200 })
        }
      }.width('100%').padding({ left: 20, right: 20,
        top: getTopSpacerHeight(this.topSafeHeight) + 12, bottom: this.bottomSafeHeight + 120 })
        .constraintSize({ maxWidth: 840 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }

  @Builder
  private FileRow(item: MediaItem): void {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        SymbolGlyph(item.browsable ? $r('sys.symbol.folder') : $r('sys.symbol.play_round_rectangle'))
          .fontSize(26).fontColor([$r('app.color.accent_blue')])
        Column({ space: 5 }) {
          Text(item.title).fontSize(16).fontColor($r('app.color.text_primary')).maxLines(2)
          if (item.subtitle.length > 0) Text(item.subtitle).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('app.color.text_secondary')])
      }.width('100%').padding(16)
    }.width('100%').backgroundColor(Color.Transparent).constraintSize({ minHeight: 72 })
      .enabled(!this.playing).onClick(() => { if (item.browsable) this.browse(item.id); else void this.play(item) })
  }
  private browse(id: string): void {
    void this.getUIContext().getRouter().pushUrl({ url: 'pages/sources/SourceBrowserPage',
      params: { sourceId: this.source.id, parentId: id, title: this.source.name } })
  }
  private async play(item: MediaItem): Promise<void> {
    if (this.playing || !item.playable) return
    this.playing = true
    try { await ProviderPlaybackLauncher.open(this.getUIContext(), item) }
    catch (_) { this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('无法播放该文件')) }
    finally { this.playing = false }
  }
}
