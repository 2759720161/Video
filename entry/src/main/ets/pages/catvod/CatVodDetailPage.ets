import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { CatVodProvider } from '../../providers/catvod/CatVodProvider'
import { CatVodVideo, CatVodRoad } from '../../providers/catvod/CatVodModels'
import { MediaItem } from '../../core/media/MediaItem'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'
import { EpisodeRow } from '../../components/media/EpisodeRow'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { buildTitleBarOptions, getTopSpacerHeight, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct CatVodDetailPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State private video: CatVodVideo | null = null
  @State private roadId: string = ''
  @State private episodes: MediaItem[] = []
  @State private loading: boolean = true
  @State private playing: boolean = false
  @State private error: string = ''
  private sourceId: string = ''
  private videoId: string = ''
  private provider: CatVodProvider | null = null
  private generation: number = 0
  private alive: boolean = true
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.alive = true
    this.playing = false
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined) {
      this.sourceId = typeof params['sourceId'] === 'string' ? params['sourceId'] as string : ''
      this.videoId = typeof params['videoId'] === 'string' ? params['videoId'] as string : ''
    }
    void this.load()
  }
  aboutToDisappear(): void { this.alive = false; this.generation++ }

  private async load(): Promise<void> {
    const generation = ++this.generation
    this.loading = true; this.error = ''
    try {
      const provider = await ProviderRegistry.get(this.sourceId, this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!(provider instanceof CatVodProvider)) throw new Error('猫源不可用或已停用')
      const video = await provider.getDetail(this.videoId)
      if (!this.alive || generation !== this.generation) return
      if (video === null) throw new Error('该作品已不可用')
      this.provider = provider; this.video = video
      this.chooseRoad(CatVodProvider.defaultRoad(video)?.id ?? '')
    } catch (err) {
      if (this.alive && generation === this.generation) this.error = err instanceof Error ? err.message : '读取作品失败'
    } finally { if (this.alive && generation === this.generation) this.loading = false }
  }

  private chooseRoad(id: string): void {
    if (this.playing) return
    this.roadId = id
    this.episodes = this.provider !== null && this.video !== null ? this.provider.episodeItems(this.video, id) : []
  }

  private async play(item: MediaItem): Promise<void> {
    if (this.playing || this.provider === null) return
    this.playing = true
    try { await ProviderPlaybackLauncher.openWithProvider(this.getUIContext(), this.provider, item, this.episodes) }
    catch (err) {
      if (this.alive) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions(err instanceof Error ? err.message : '无法打开播放'))
    } finally { if (this.alive) this.playing = false }
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          if (this.loading) PageLoadingState({ title: '正在读取作品', minHeight: 300 })
          else if (this.error.length > 0) PageErrorState({ title: '详情暂不可用', message: this.error, onRetry: () => { void this.load() } })
          else if (this.video !== null) {
            Row({ space: 18 }) {
              Image(this.video.poster.length > 0 ? this.video.poster : $r('app.media.ic_placeholder'))
                .width(124).height(180).objectFit(ImageFit.Cover).borderRadius(16)
              Column({ space: 10 }) {
                Text(this.video.name).fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).maxLines(4)
                Text(this.video.remarks).fontSize(14).fontColor($r('app.color.text_secondary'))
                if (this.video.year > 0) Text(String(this.video.year)).fontSize(14).fontColor($r('app.color.text_secondary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(VerticalAlign.Top)
            if (this.video.overview.length > 0) Text(this.video.overview).fontSize(15)
              .fontColor($r('app.color.text_secondary')).width('100%')
            Text($r('app.string.catvod_episodes')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.video.roads, (road: CatVodRoad) => {
                  Button(road.name).height(38).enabled(!this.playing)
                    .backgroundColor(road.id === this.roadId ? $r('app.color.accent_blue') : $r('app.color.card_background'))
                    .fontColor(road.id === this.roadId ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
                    .onClick(() => this.chooseRoad(road.id))
                }, (road: CatVodRoad) => road.id)
              }
            }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            if (this.episodes.length === 0) Text($r('app.string.catvod_no_playable')).fontColor($r('app.color.text_secondary'))
            Column() {
              ForEach(this.episodes, (item: MediaItem, index: number) => {
                EpisodeRow({ indexLabel: String(index + 1), title: item.subtitle, artworkUrl: item.poster,
                  playbackEnabled: !this.playing, showDivider: index < this.episodes.length - 1,
                  onRowClick: () => { void this.play(item) } })
              }, (item: MediaItem) => item.id)
            }.width('100%')
          }
        }.width('100%').padding({ left: 20, right: 20, top: getTopSpacerHeight(this.topSafeHeight) + 12,
          bottom: this.bottomSafeHeight + 28 }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.video?.name ?? '作品详情', this.materialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor($r('app.color.page_background'))
      .bindToScrollable([this.scroller])
  }
}
