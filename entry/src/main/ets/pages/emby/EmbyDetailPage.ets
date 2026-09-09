import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { buildTitleBarOptions, getContentMaxWidth, isTabletLayout,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'

@Entry
@Component
struct EmbyDetailPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State private sourceId: string = ''
  @State private itemId: string = ''
  @State private item: EmbyItem | null = null
  @State private loading: boolean = true
  @State private errorText: string = ''
  @State private playing: boolean = false
  @State private seasonItems: EmbyItem[] = []
  @State private episodeItems: EmbyItem[] = []
  @State private selectedSeasonId: string = ''
  @State private playbackVariants: PlaybackVariant[] = []
  @State private selectedVariantId: string = 'auto'
  private provider: EmbyProvider | null = null
  private seasonLoadGeneration: number = 0

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
        PageLoadingState({ title: '正在读取媒体详情', minHeight: 300 })
      } else if (this.errorText.length > 0 || this.item === null) {
        PageErrorState({ title: '媒体详情不可用', message: this.errorText.length > 0 ? this.errorText : '媒体不存在',
          onRetry: () => this.loadItem() })
      } else {
        this.DetailContent(this.item!)
      }
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.item === null ? '媒体详情' : this.item!.name, this.hdsMaterialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private DetailContent(item: EmbyItem): void {
    Stack({ alignContent: Alignment.Top }) {
      if (isTabletLayout(this.screenWidthVp) && this.tabletBackdropUrl(item).length > 0) {
        Image(this.tabletBackdropUrl(item))
          .width('100%').height(430).objectFit(ImageFit.Cover)
          .blur(22).opacity(0.24).draggable(false)
          .align(Alignment.Top)
        Column()
          .width('100%').height(430)
          .linearGradient({ direction: GradientDirection.Bottom,
            colors: [['#00000000', 0.08], [$r('app.color.page_background'), 1]] })
          .align(Alignment.Top)
      }
      Scroll() {
        Column({ space: 16 }) {
          if (isTabletLayout(this.screenWidthVp)) {
            this.TabletDetailLayout(item)
          } else {
            this.PhoneDetailLayout(item)
          }
        }.width('100%')
          .constraintSize({ maxWidth: getContentMaxWidth(this.screenWidthVp) || '100%' })
          .padding(isTabletLayout(this.screenWidthVp) ? AppSpacing.PAGE_TABLET : AppSpacing.PAGE)
          .alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }
    .width('100%').height('100%')
  }

  @Builder
  private TabletPoster(item: EmbyItem): void {
    if (this.imageUrl(item).length > 0) {
      Image(this.imageUrl(item))
        .width('100%').height(this.detailHeroHeight())
        .objectFit(ImageFit.Contain).draggable(false)
        .backgroundColor($r('app.color.button_ghost_bg'))
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(48)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%').height(this.detailHeroHeight())
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.button_ghost_bg'))
    }
  }

  private tabletBackdropUrl(item: EmbyItem): string {
    const provider = this.itemProvider()
    return provider === null ? '' : provider.backdropUrlFor(item, 1400)
  }

  @Builder
  private PhoneDetailLayout(item: EmbyItem): void {
    this.HeroImage(item)
    this.DetailMeta(item)
    this.DetailActions(item)
    this.DetailSections(item)
  }

  @Builder
  private TabletDetailLayout(item: EmbyItem): void {
    Row({ space: 24 }) {
      Column() {
        this.TabletPoster(item)
      }.width('42%')
      Column({ space: 16 }) {
        this.DetailMeta(item)
        this.DetailActions(item)
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top)
    this.DetailSections(item)
  }

  @Builder
  private DetailMeta(item: EmbyItem): void {
    Column({ space: 8 }) {
      Text(item.name).fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      Text(this.metaText(item)).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      if (item.overview.length > 0) {
        Text(item.overview).fontSize(14).fontColor($r('app.color.text_primary'))
          .lineHeight(22).width('100%').textAlign(TextAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailActions(item: EmbyItem): void {
    Row({ space: 10 }) {
      if (!item.isFolder) {
        Button(this.resumeLabel(item)).layoutWeight(1).height(46).fontSize(15)
          .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
          .onClick(() => this.play(item))
      } else if (this.episodeItems.length > 0) {
        Button(this.episodeActionLabel()).layoutWeight(1).height(46).fontSize(15)
          .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
          .onClick(() => {
            const episode = this.preferredEpisode()
            if (episode !== null) void this.playEpisode(episode)
          })
      } else {
        Button('浏览下级').layoutWeight(1).height(46).fontSize(15)
          .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
          .onClick(() => this.openChildren(item))
      }
    }.width('100%')
  }

  @Builder
  private DetailSections(item: EmbyItem): void {
    if (this.playbackVariants.length > 1) this.PlaybackVariantSection()
    if (this.seasonItems.length > 0) this.SeasonSection()
    if (this.episodeItems.length > 0) this.EpisodeSection()
    this.DetailInfoSection(item)
  }

  @Builder
  private DetailInfoSection(item: EmbyItem): void {
    Column({ space: 6 }) {
      MediaSectionHeader({ title: '更多信息' })
      this.DetailInfoRow('类型', EmbyItem.typeLabel(item.type))
      if (item.productionYear > 0) this.DetailInfoRow('年份', String(item.productionYear))
      if (item.durationMs() > 0) this.DetailInfoRow('时长', this.formatDuration(item.durationMs()))
      if (item.container.length > 0) this.DetailInfoRow('格式', item.container.toUpperCase())
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  private DetailInfoRow(label: string, value: string): void {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).width(64)
      Text(value).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ top: 7, bottom: 7 })
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider_color') })
  }

  @Builder
  private PlaybackVariantSection(): void {
    Column({ space: 8 }) {
      MediaSectionHeader({ title: '播放版本' })
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.playbackVariants, (variant: PlaybackVariant) => {
            Column({ space: 2 }) {
              Button(variant.name.length > 0 ? variant.name : variant.id)
                .height(36).fontSize(13)
                .fontColor(variant.id === this.selectedVariantId ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
                .backgroundColor(variant.id === this.selectedVariantId ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
                .onClick(() => this.selectPlaybackVariant(variant))
              if (variant.quality.length > 0) {
                Text(variant.quality).fontSize(11).fontColor($r('app.color.text_secondary'))
              }
            }
          }, (variant: PlaybackVariant) => 'detail_variant_' + variant.id)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private HeroImage(item: EmbyItem): void {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.heroUsesPoster(item)) {
        Image(this.heroImageUrl(item))
          .width('100%').height(this.detailHeroHeight()).objectFit(ImageFit.Cover)
          .blur(18).opacity(0.42).draggable(false)
        Image(this.heroImageUrl(item))
          .width('100%').height(this.detailHeroHeight()).objectFit(ImageFit.Contain)
          .draggable(false)
      } else if (this.heroImageUrl(item).length > 0) {
        Image(this.heroImageUrl(item)).width('100%').height(this.detailHeroHeight()).objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.button_ghost_bg')).draggable(false)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.play_round_rectangle')).fontSize(48)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%').height(this.detailHeroHeight())
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.button_ghost_bg'))
      }
      Column()
        .width('100%').height(this.detailHeroHeight() * 0.46)
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [[Color.Transparent, 0], [$r('app.color.page_background'), 1]] })
    }
    .width('100%').height(this.detailHeroHeight())
    .clip(true).borderRadius(16)
  }

  private detailHeroHeight(): number {
    return isTabletLayout(this.screenWidthVp) ? 320 : 210
  }

  private async loadItem(): Promise<void> {
    this.seasonLoadGeneration++
    this.loading = true
    this.errorText = ''
    this.playbackVariants = []
    this.selectedVariantId = 'auto'
    this.seasonItems = []
    this.episodeItems = []
    this.selectedSeasonId = ''
    try {
      if (this.sourceId.length === 0 || this.itemId.length === 0) throw new Error('媒体参数无效')
      const provider = await ProviderRegistry.get(this.sourceId, getContext(this) as common.UIAbilityContext)
      if (provider === null || !(provider instanceof EmbyProvider)) throw new Error('Emby 来源不可用')
      this.provider = provider
      this.item = await provider.getItemRaw(this.itemId)
      if (this.item === null) throw new Error('媒体不存在或已被删除')
      const loadedItem = this.item
      if (!loadedItem.isFolder) {
        try {
          const variants = await provider.getPlaybackVariants(loadedItem)
          loadedItem.variants = variants
          if (variants.length > 1) {
            const auto = new PlaybackVariant()
            auto.id = 'auto'
            auto.name = '自动'
            const displayVariants: PlaybackVariant[] = [auto]
            for (let i = 0; i < variants.length; i++) displayVariants.push(variants[i])
            this.playbackVariants = displayVariants
            this.selectedVariantId = loadedItem.variantId.length > 0 ? loadedItem.variantId : 'auto'
          }
        } catch (_) {
          loadedItem.variants = []
        }
      }
      if (this.item.type === 'Season') {
        this.episodeItems = (await provider.getItemsRaw(this.item.id)).filter((entry: EmbyItem) => !entry.isFolder)
        this.sortByIndex(this.episodeItems)
      } else if (this.item.type === 'Series') {
        this.seasonItems = (await provider.getItemsRaw(this.item.id)).filter((entry: EmbyItem) => entry.type === 'Season')
        this.sortByIndex(this.seasonItems)
        if (this.seasonItems.length > 0) {
          this.selectedSeasonId = this.seasonItems[0].id
          this.episodeItems = (await provider.getItemsRaw(this.selectedSeasonId)).filter((entry: EmbyItem) => !entry.isFolder)
          this.sortByIndex(this.episodeItems)
        }
      }
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

  private heroImageUrl(item: EmbyItem): string {
    const provider = this.itemProvider()
    if (provider === null) return ''
    const backdrop = provider.backdropUrlFor(item, 1200)
    if (backdrop.length > 0) return backdrop
    const thumbnail = provider.thumbnailUrlFor(item, 900)
    if (thumbnail.length > 0) return thumbnail
    return this.imageUrl(item)
  }

  private heroUsesPoster(item: EmbyItem): boolean {
    const provider = this.itemProvider()
    if (provider === null) return false
    if (provider.backdropUrlFor(item, 1200).length > 0) return false
    if (provider.thumbnailUrlFor(item, 900).length > 0) return false
    return this.imageUrl(item).length > 0
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

  @Builder
  private SeasonSection(): void {
    Column({ space: 8 }) {
      MediaSectionHeader({ title: '选集' })
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.seasonItems, (season: EmbyItem) => {
            Button(season.subtitle().length > 0 ? season.subtitle() : season.name)
              .height(36).fontSize(13)
              .fontColor(season.id === this.selectedSeasonId ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
              .backgroundColor(season.id === this.selectedSeasonId ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
              .onClick(() => { void this.selectSeason(season) })
          }, (season: EmbyItem) => 'detail_season_' + season.id)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EpisodeSection(): void {
    Column({ space: 8 }) {
      MediaSectionHeader({ title: '剧集' })
      ForEach(this.episodeItems, (episode: EmbyItem, index: number) => {
        Row({ space: 10 }) {
          Text(episode.indexNumber > 0 ? String(episode.indexNumber).padStart(2, '0') : String(index + 1))
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_secondary')).width(30)
          Column({ space: 3 }) {
            Text(episode.name).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.episodeMeta(episode)).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (episode.resumePositionMs() > 0) {
            Progress({ value: this.episodeProgress(episode), total: 100, type: ProgressType.Linear })
              .width(48).height(3).color($r('app.color.accent_blue'))
          }
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([$r('app.color.accent_blue')])
        }
        .width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .borderRadius(12).backgroundColor($r('app.color.card_background'))
        .onClick(() => { void this.playEpisode(episode) })
      }, (episode: EmbyItem) => 'detail_episode_' + episode.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private episodeMeta(episode: EmbyItem): string {
    const duration = episode.durationMs() > 0 ? this.formatDuration(episode.durationMs()) : ''
    return duration.length > 0 ? duration : '点击播放'
  }

  private episodeProgress(episode: EmbyItem): number {
    const reported = Number.isFinite(episode.userData.playedPercentage) ? episode.userData.playedPercentage : 0
    if (reported > 0) return Math.min(100, Math.max(0, reported))
    const duration = episode.durationMs()
    if (duration <= 0) return 0
    return Math.min(100, Math.max(0, episode.resumePositionMs() / duration * 100))
  }

  private preferredEpisode(): EmbyItem | null {
    for (let i = 0; i < this.episodeItems.length; i++) {
      if (this.episodeItems[i].resumePositionMs() > 0) return this.episodeItems[i]
    }
    return this.episodeItems.length > 0 ? this.episodeItems[0] : null
  }

  private episodeActionLabel(): string {
    const episode = this.preferredEpisode()
    return episode !== null && episode.resumePositionMs() > 0 ? '继续播放' : '播放第一集'
  }

  private async selectSeason(season: EmbyItem): Promise<void> {
    if (this.provider === null || season.id.length === 0) return
    const generation = ++this.seasonLoadGeneration
    this.selectedSeasonId = season.id
    try {
      const episodes = (await this.provider.getItemsRaw(season.id)).filter((entry: EmbyItem) => !entry.isFolder)
      if (generation !== this.seasonLoadGeneration || this.selectedSeasonId !== season.id) return
      this.episodeItems = episodes
      this.sortByIndex(this.episodeItems)
    } catch (_) {
      if (generation === this.seasonLoadGeneration && this.selectedSeasonId === season.id) {
        this.episodeItems = []
      }
    }
  }

  private async playEpisode(episode: EmbyItem): Promise<void> {
    if (this.playing || this.provider === null) return
    this.playing = true
    try {
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, episode, this.episodeItems)
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法播放该剧集' })
    } finally {
      this.playing = false
    }
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

  private selectPlaybackVariant(variant: PlaybackVariant): void {
    if (this.item === null || variant.id.length === 0) return
    this.selectedVariantId = variant.id
    this.item.variantId = variant.id === 'auto' ? '' : variant.id
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

  private sortByIndex(items: EmbyItem[]): void {
    items.sort((left: EmbyItem, right: EmbyItem) => {
      const leftIndex = left.indexNumber > 0 ? left.indexNumber : 999999999
      const rightIndex = right.indexNumber > 0 ? right.indexNumber : 999999999
      if (leftIndex !== rightIndex) return leftIndex - rightIndex
      return left.name.localeCompare(right.name)
    })
  }
}
