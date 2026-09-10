import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { buildTitleBarOptions, getDetailContentMaxWidth, isWideDetailLayout,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { AppSpacing } from '../../ui/theme/AppSpacing'
import { AppTypography } from '../../ui/theme/AppTypography'
import { AppDimensions } from '../../ui/theme/AppDimensions'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { MediaSectionHeader } from '../../components/media/MediaSectionHeader'
import { EpisodeRow } from '../../components/media/EpisodeRow'
import { MediaDetailHero } from '../../components/media/MediaDetailHero'
import { AppRadius } from '../../ui/theme/AppRadius'
import { AppSurface } from '../../ui/theme/AppSurface'
import { ResponsiveSizeClass, ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { ImmersiveArtworkBackground } from '../../components/media/ImmersiveArtworkBackground'
import { ArtworkPaletteService, ArtworkVisualProfile } from '../../services/media/ArtworkPaletteService'

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
  @State private ambientArtworkUrl: string = ''
  @State private detailScrollOffset: number = 0
  @State private visualProfile: ArtworkVisualProfile = new ArtworkVisualProfile()
  @State private primaryActionPressed: boolean = false
  private provider: EmbyProvider | null = null
  private seasonLoadGeneration: number = 0
  private scroller: Scroller = new Scroller()
  private paletteGeneration: number = 0

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
      .bindToScrollable([this.scroller])
  }

  @Builder
  private DetailContent(item: EmbyItem): void {
    Stack({ alignContent: Alignment.Top }) {
      ImmersiveArtworkBackground({ artworkUrl: this.ambientArtworkUrl,
        primaryColor: this.visualProfile.primaryColor,
        secondaryColor: this.visualProfile.secondaryColor,
        artworkMode: this.ambientArtworkMode(item),
        ambientOpacity: this.visualProfile.ambientOpacity,
        scrimOpacity: this.visualProfile.scrimOpacity,
        heightVp: this.ambientHeight(), scrollOffsetVp: this.detailScrollOffset })
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          if (isWideDetailLayout(this.screenWidthVp)) {
            this.TabletDetailLayout(item)
          } else {
            this.PhoneDetailLayout(item)
          }
        }.width('100%')
          .constraintSize({ maxWidth: getDetailContentMaxWidth(this.screenWidthVp) || '100%' })
          .padding(ResponsiveSizeClassResolver.pagePadding(this.screenWidthVp))
          .alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').scrollBar(BarState.Off)
        .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
          this.detailScrollOffset = Math.max(0, yOffset)
        })
    }
    .width('100%').height('100%')
  }

  @Builder
  private PhoneDetailLayout(item: EmbyItem): void {
    MediaDetailHero({
      title: item.name,
      meta: this.metaText(item),
      overview: item.overview,
      artworkUrl: this.heroImageUrl(item),
      usePosterFallback: this.heroUsesPoster(item),
      showIdentity: false,
      showAction: false,
      showOverview: false
    })
    this.DetailIdentity(item)
    this.PrimaryActionSection(item)
    this.OverviewSection(item)
    this.DetailSections(item)
  }

  @Builder
  private TabletDetailLayout(item: EmbyItem): void {
    Row({ space: AppSpacing.XL }) {
      MediaDetailHero({
        title: item.name,
        meta: this.metaText(item),
        overview: item.overview,
        artworkUrl: this.imageUrl(item),
        wide: true,
        artworkWidth: this.detailPosterWidth(),
        artworkHeight: this.detailPosterHeight(),
        showIdentity: false,
        showAction: false,
        showOverview: false
      })
      Column({ space: AppSpacing.MD }) {
        this.DetailIdentity(item)
        this.PrimaryActionSection(item)
        this.OverviewSection(item)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    this.DetailSections(item)
  }

  @Builder
  private DetailIdentity(item: EmbyItem): void {
    Column({ space: AppSpacing.XS }) {
      Text(item.name)
        .fontSize(isWideDetailLayout(this.screenWidthVp) ? 28 : AppTypography.PAGE_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.metaText(item))
        .fontSize(AppTypography.META)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PrimaryActionSection(item: EmbyItem): void {
    Button(this.primaryActionText(item))
      .height(48)
      .constraintSize({ minWidth: 144 })
      .fontSize(AppTypography.BODY_LARGE)
      .fontColor($r('app.color.text_on_primary'))
      .backgroundColor($r('app.color.accent_blue'))
      .borderRadius(AppRadius.BUTTON)
      .scale({ x: this.primaryActionPressed ? 0.97 : 1, y: this.primaryActionPressed ? 0.97 : 1 })
      .opacity(this.playing ? 0.72 : 1)
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) this.primaryActionPressed = true
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.primaryActionPressed = false
      })
      .onClick(() => this.handlePrimaryAction(item))
  }

  @Builder
  private OverviewSection(item: EmbyItem): void {
    if (item.overview.length > 0) {
      Text(item.overview)
        .fontSize(AppTypography.BODY)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(22)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .alignSelf(ItemAlign.Start)
    }
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
      Column() {
        this.DetailInfoRow('类型', EmbyItem.typeLabel(item.type),
          item.productionYear > 0 || item.durationMs() > 0 || item.container.length > 0)
        if (item.productionYear > 0) {
          this.DetailInfoRow('年份', String(item.productionYear),
            item.durationMs() > 0 || item.container.length > 0)
        }
        if (item.durationMs() > 0) {
          this.DetailInfoRow('时长', this.formatDuration(item.durationMs()), item.container.length > 0)
        }
        if (item.container.length > 0) this.DetailInfoRow('格式', item.container.toUpperCase(), false)
      }
      .width('100%')
      .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM, left: AppSpacing.MD, right: AppSpacing.MD })
      .borderRadius(AppRadius.SURFACE)
      .backgroundColor(AppSurface.color(AppSurface.SURFACE))
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailInfoRow(label: string, value: string, showDivider: boolean = true): void {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).width(64)
      Text(value).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ top: 7, bottom: 7 })
    .border({ width: { bottom: showDivider ? 0.5 : 0 }, color: $r('app.color.divider_color') })
  }

  @Builder
  private PlaybackVariantSection(): void {
    Column({ space: 8 }) {
      MediaSectionHeader({ title: '播放版本' })
      this.CompactSelectorRow('播放版本', this.selectedVariantLabel(), () => this.openVariantMenu())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private async loadItem(): Promise<void> {
    this.seasonLoadGeneration++
    this.loading = true
    this.errorText = ''
    this.ambientArtworkUrl = ''
    this.detailScrollOffset = 0
    this.paletteGeneration++
    this.visualProfile = new ArtworkVisualProfile()
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
      this.ambientArtworkUrl = this.paletteArtworkUrl(loadedItem)
      void this.loadArtworkProfile(loadedItem)
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

  private paletteArtworkUrl(item: EmbyItem): string {
    const provider = this.itemProvider()
    if (provider === null) return ''
    const backdrop = provider.backdropUrlFor(item, 96)
    if (backdrop.length > 0) return backdrop
    const thumbnail = provider.thumbnailUrlFor(item, 96)
    if (thumbnail.length > 0) return thumbnail
    return provider.imageUrlFor(item, 96)
  }

  private ambientArtworkMode(item: EmbyItem): string {
    const provider = this.itemProvider()
    if (provider === null) return 'none'
    if (provider.backdropUrlFor(item, 1200).length > 0) return 'backdrop'
    if (provider.thumbnailUrlFor(item, 900).length > 0) return 'thumbnail'
    if (provider.imageUrlFor(item, 900).length > 0) return 'poster'
    return 'none'
  }

  private ambientHeight(): number {
    return isWideDetailLayout(this.screenWidthVp) ? 660 : 580
  }

  private detailPosterWidth(): number {
    return ResponsiveSizeClassResolver.resolve(this.screenWidthVp) === ResponsiveSizeClass.LARGE ? 280 : 240
  }

  private detailPosterHeight(): number {
    return Math.round(this.detailPosterWidth() / AppDimensions.MEDIA_POSTER_RATIO)
  }

  private async loadArtworkProfile(item: EmbyItem): Promise<void> {
    const generation = ++this.paletteGeneration
    const url = this.paletteArtworkUrl(item)
    if (url.length === 0) {
      if (generation === this.paletteGeneration) this.visualProfile = new ArtworkVisualProfile()
      return
    }
    try {
      const profile = await ArtworkPaletteService.resolve(getContext(this) as common.UIAbilityContext, url)
      if (generation === this.paletteGeneration) this.visualProfile = profile
    } catch (_) {
      if (generation === this.paletteGeneration) this.visualProfile = new ArtworkVisualProfile()
    }
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

  private primaryActionText(item: EmbyItem): string {
    if (!item.isFolder) return this.resumeLabel(item)
    if (this.episodeItems.length > 0) return this.episodeActionLabel()
    return '浏览下级'
  }

  private handlePrimaryAction(item: EmbyItem): void {
    if (!item.isFolder) {
      void this.play(item)
      return
    }
    if (this.episodeItems.length > 0) {
      const episode = this.preferredEpisode()
      if (episode !== null) void this.playEpisode(episode)
      return
    }
    this.openChildren(item)
  }

  @Builder
  private SeasonSection(): void {
    Column({ space: 8 }) {
      MediaSectionHeader({ title: '选集' })
      this.CompactSelectorRow('选集', this.selectedSeasonLabel(), () => this.openSeasonMenu())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CompactSelectorRow(label: string, value: string, onClick: () => void): void {
    Row() {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(value)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(56)
    .padding({ left: AppSpacing.MD, right: AppSpacing.SM })
    .borderRadius(AppRadius.SURFACE)
    .backgroundColor(AppSurface.color(AppSurface.SURFACE))
    .onClick(onClick)
  }

  @Builder
  private EpisodeSection(): void {
    Column({ space: 8 }) {
      MediaSectionHeader({ title: '剧集' })
      ForEach(this.episodeItems, (episode: EmbyItem, index: number) => {
        EpisodeRow({
          indexLabel: episode.indexNumber > 0 ? String(episode.indexNumber).padStart(2, '0') : String(index + 1),
          title: episode.name,
          meta: this.episodeMeta(episode),
          artworkUrl: this.episodeArtworkUrl(episode),
          progress: this.episodeProgress(episode),
          showDivider: index < this.episodeItems.length - 1,
          onRowClick: () => { void this.playEpisode(episode) }
        })
      }, (episode: EmbyItem) => 'detail_episode_' + episode.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private episodeMeta(episode: EmbyItem): string {
    const duration = episode.durationMs() > 0 ? this.formatDuration(episode.durationMs()) : ''
    const progress = this.episodeProgress(episode)
    let watchState = ''
    if (episode.userData.played || progress >= 95) {
      watchState = '已看完'
    } else if (progress > 0) {
      watchState = '已观看 ' + String(Math.round(progress)) + '%'
    }
    if (duration.length > 0 && watchState.length > 0) return duration + ' · ' + watchState
    if (duration.length > 0) return duration
    if (watchState.length > 0) return watchState
    return '点击播放'
  }

  private episodeProgress(episode: EmbyItem): number {
    const reported = Number.isFinite(episode.userData.playedPercentage) ? episode.userData.playedPercentage : 0
    if (reported > 0) return Math.min(100, Math.max(0, reported))
    const duration = episode.durationMs()
    if (duration <= 0) return 0
    return Math.min(100, Math.max(0, episode.resumePositionMs() / duration * 100))
  }

  private episodeArtworkUrl(episode: EmbyItem): string {
    const provider = this.itemProvider()
    return provider === null ? '' : provider.thumbnailUrlFor(episode, 320)
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
    } catch (_) {
      promptAction.showToast({ message: '无法播放该媒体' })
    } finally {
      this.playing = false
    }
  }

  private async play(item: EmbyItem): Promise<void> {
    if (this.playing) return
    this.playing = true
    try {
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, item, [item])
    } catch (_) {
      promptAction.showToast({ message: '无法播放该媒体' })
    } finally {
      this.playing = false
    }
  }

  private selectPlaybackVariant(variant: PlaybackVariant): void {
    if (this.item === null || variant.id.length === 0) return
    this.selectedVariantId = variant.id
    this.item.variantId = variant.id === 'auto' ? '' : variant.id
  }

  private selectedVariantLabel(): string {
    for (let i = 0; i < this.playbackVariants.length; i++) {
      const variant = this.playbackVariants[i]
      if (variant.id === this.selectedVariantId) {
        const name = variant.name.length > 0 ? variant.name : variant.id
        return variant.quality.length > 0 ? name + ' · ' + variant.quality : name
      }
    }
    return '自动'
  }

  private openVariantMenu(): void {
    if (this.playbackVariants.length === 0) return
    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?,
      promptAction.Button?, promptAction.Button?] = [this.variantMenuButton(this.playbackVariants[0])]
    if (this.playbackVariants.length > 1) buttons[1] = this.variantMenuButton(this.playbackVariants[1])
    if (this.playbackVariants.length > 2) buttons[2] = this.variantMenuButton(this.playbackVariants[2])
    if (this.playbackVariants.length > 3) buttons[3] = this.variantMenuButton(this.playbackVariants[3])
    if (this.playbackVariants.length > 4) buttons[4] = this.variantMenuButton(this.playbackVariants[4])
    if (this.playbackVariants.length > 5) buttons[5] = this.variantMenuButton(this.playbackVariants[5])
    try {
      this.getUIContext().getPromptAction().showActionMenu({ title: '播放版本', buttons },
        (err: BusinessError, result: promptAction.ActionMenuSuccessResponse) => {
          if (err !== undefined || result.index < 0 || result.index >= Math.min(6, this.playbackVariants.length)) return
          this.selectPlaybackVariant(this.playbackVariants[result.index])
        })
    } catch (_) {
      // 选择面板失败时保留当前播放版本。
    }
  }

  private selectedSeasonLabel(): string {
    for (let i = 0; i < this.seasonItems.length; i++) {
      const season = this.seasonItems[i]
      if (season.id === this.selectedSeasonId) return season.subtitle().length > 0 ? season.subtitle() : season.name
    }
    return this.seasonItems.length > 0 ? this.seasonItems[0].name : '选择季'
  }

  private openSeasonMenu(): void {
    if (this.seasonItems.length === 0) return
    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?,
      promptAction.Button?, promptAction.Button?] = [this.seasonMenuButton(this.seasonItems[0])]
    if (this.seasonItems.length > 1) buttons[1] = this.seasonMenuButton(this.seasonItems[1])
    if (this.seasonItems.length > 2) buttons[2] = this.seasonMenuButton(this.seasonItems[2])
    if (this.seasonItems.length > 3) buttons[3] = this.seasonMenuButton(this.seasonItems[3])
    if (this.seasonItems.length > 4) buttons[4] = this.seasonMenuButton(this.seasonItems[4])
    if (this.seasonItems.length > 5) buttons[5] = this.seasonMenuButton(this.seasonItems[5])
    try {
      this.getUIContext().getPromptAction().showActionMenu({ title: '选择季', buttons },
        (err: BusinessError, result: promptAction.ActionMenuSuccessResponse) => {
          if (err !== undefined || result.index < 0 || result.index >= Math.min(6, this.seasonItems.length)) return
          void this.selectSeason(this.seasonItems[result.index])
        })
    } catch (_) {
      // 选择面板失败时保留当前季。
    }
  }

  private variantMenuButton(variant: PlaybackVariant): promptAction.Button {
    const name = variant.name.length > 0 ? variant.name : variant.id
    return {
      text: variant.quality.length > 0 ? name + ' · ' + variant.quality : name,
      color: $r('app.color.text_primary')
    }
  }

  private seasonMenuButton(season: EmbyItem): promptAction.Button {
    return {
      text: season.subtitle().length > 0 ? season.subtitle() : season.name,
      color: $r('app.color.text_primary')
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

  private sortByIndex(items: EmbyItem[]): void {
    items.sort((left: EmbyItem, right: EmbyItem) => {
      const leftIndex = left.indexNumber > 0 ? left.indexNumber : 999999999
      const rightIndex = right.indexNumber > 0 ? right.indexNumber : 999999999
      if (leftIndex !== rightIndex) return leftIndex - rightIndex
      return left.name.localeCompare(right.name)
    })
  }
}
