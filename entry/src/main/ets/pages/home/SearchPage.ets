import { buildDetailToastOptions } from '../../utils/DetailMaterial'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit'
import { SearchTitleMaterialModifier } from '../../utils/DetailMaterial'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { buildEmbyDetailRouteParams } from '../../providers/emby/EmbyDetailRoute'
import { MediaPosterCard } from '../../components/media/MediaPosterCard'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { buildMediaDetailTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL,
  getTopSpacerHeight, IMMERSIVE_STYLE_DEFAULT, PREFS_KEY_IMMERSIVE_MATERIAL_STYLE } from '../../utils/HdsPageStyle'
import { ResponsiveSizeClassResolver } from '../../ui/theme/ResponsiveSizeClass'
import { PreferencesStore } from '../../store/PreferencesStore'

@Entry
@Component
struct SearchPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE) materialThickness: string = IMMERSIVE_STYLE_DEFAULT
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidth: number = 360
  @State private query: string = ''
  @State private items: EmbyItem[] = []
  @State private initializing: boolean = true
  @State private searching: boolean = false
  @State private error: string = ''
  @State private history: string[] = []
  private sourceId: string = ''
  private provider: EmbyProvider | null = null
  private generation: number = 0
  private timer: number = -1
  private alive: boolean = true
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.alive = true
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
    if (params !== undefined && typeof params['sourceId'] === 'string') this.sourceId = params['sourceId'] as string
    void this.initialize()
  }

  aboutToDisappear(): void { this.alive = false; this.cancelSearch() }

  private async initialize(): Promise<void> {
    try {
      const saved = await PreferencesStore.getInstance().getString('emby_search_history', '[]')
      try {
        const entries = JSON.parse(saved) as string[]
        if (Array.isArray(entries) && this.alive) {
          this.history = entries.filter((entry: string) => typeof entry === 'string' && entry.trim().length > 0)
            .filter((entry: string, index: number, all: string[]) => all.indexOf(entry) === index).slice(0, 20)
        }
      } catch (_) { this.history = [] }
      const provider = await ProviderRegistry.get(this.sourceId,
        this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!this.alive) return
      if (!(provider instanceof EmbyProvider)) throw new Error('Unavailable')
      this.provider = provider
      this.error = ''
    } catch (_) {
      if (this.alive) this.error = '无法连接当前服务，请重试'
    } finally {
      if (this.alive) this.initializing = false
    }
  }

  private cancelSearch(): void {
    this.generation++
    if (this.timer >= 0) clearTimeout(this.timer)
    this.timer = -1
    this.searching = false
  }

  private search(value: string, immediate: boolean = false): void {
    this.cancelSearch()
    this.query = value
    this.items = []
    this.error = ''
    if (value.trim().length === 0 || this.provider === null) return
    this.searching = true
    const generation = this.generation
    if (immediate) void this.runSearch(value.trim(), generation)
    else this.timer = setTimeout(() => { this.timer = -1; void this.runSearch(value.trim(), generation) }, 260)
  }

  private async runSearch(query: string, generation: number): Promise<void> {
    if (this.provider === null) return
    try {
      const results = await this.provider.searchRaw(query)
      if (this.alive && generation === this.generation) {
        this.items = results
        this.rememberSearch(query)
      }
    } catch (_) {
      if (this.alive && generation === this.generation) this.error = '搜索失败，请重试'
    } finally {
      if (this.alive && generation === this.generation) this.searching = false
    }
  }

  private rememberSearch(query: string): void {
    const keyword = query.trim()
    if (keyword.length === 0) return
    this.history = [keyword, ...this.history.filter((entry: string) => entry !== keyword)].slice(0, 20)
    void this.saveHistory()
  }

  private removeHistory(keyword: string): void {
    this.history = this.history.filter((entry: string) => entry !== keyword)
    void this.saveHistory()
  }

  private clearHistory(): void {
    this.history = []
    void this.saveHistory()
  }

  private async saveHistory(): Promise<void> {
    try {
      await PreferencesStore.getInstance().setStringStrict('emby_search_history', JSON.stringify(this.history))
    } catch (_) {
      if (this.alive) this.getUIContext().getPromptAction().showToast(buildDetailToastOptions('搜索记录保存失败，请重试'))
    }
  }

  private titleOptions(): HdsNavigationTitleBarOptions {
    const options = buildMediaDetailTitleBarOptions('搜索', this.materialLevel)
    if (options.content !== undefined) {
      options.content.bottomBuilder = { builder: () => { this.SearchField() }, height: 64 }
    }
    return options
  }

  @Builder
  private SearchField(): void {
    Row() {
      Search({ value: this.query, placeholder: '搜索电影、剧集' })
        .width('100%').height(48).borderRadius(24)
        .attributeModifier(new SearchTitleMaterialModifier(this.materialThickness))
        .enabled(!this.initializing && this.provider !== null)
        .onChange((value: string) => this.search(value))
        .onSubmit((value: string) => this.search(value, true))
    }.width('100%').height(64).padding({ left: 20, right: 20, top: 8, bottom: 8 })
  }

  @Builder
  private SearchHistory(): void {
    Column({ space: 12 }) {
      Row() {
        Text('搜索历史').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button('清空', { type: ButtonType.Normal }).fontSize(14)
          .fontColor($r('app.color.text_secondary')).backgroundColor(Color.Transparent)
          .onClick(() => this.clearHistory())
      }.width('100%')
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.history, (keyword: string) => {
          Row() {
            Button(keyword, { type: ButtonType.Normal }).fontSize(14)
              .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent)
              .constraintSize({ maxWidth: this.screenWidth - 112 }).height(40)
              .onClick(() => this.search(keyword, true))
            Button('×', { type: ButtonType.Circle }).width(32).height(32).fontSize(20)
              .fontColor($r('app.color.text_secondary')).backgroundColor(Color.Transparent)
              .accessibilityText('删除搜索记录：' + keyword).onClick(() => this.removeHistory(keyword))
          }.padding({ right: 4 }).borderRadius(20).backgroundColor($r('app.color.card_background'))
            .margin({ right: 8, bottom: 10 })
        }, (keyword: string) => keyword)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight) + 64)
          if (this.query.trim().length === 0 && this.history.length > 0) this.SearchHistory()
          if (this.initializing || this.searching) {
            PageLoadingState({ title: this.initializing ? '正在连接服务' : '正在搜索', minHeight: 180 })
          } else if (this.error.length > 0) {
            PageErrorState({ title: '搜索暂不可用', message: this.error, onRetry: () => {
              if (this.provider === null) { this.initializing = true; void this.initialize() }
              else this.search(this.query, true)
            } })
          } else if (this.items.length > 0) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.items, (item: EmbyItem) => {
                Column() {
                  MediaPosterCard({ title: item.name, subtitle: item.subtitle(),
                    artworkUrl: this.provider?.imageUrlFor(item, 360) ?? '',
                    enableSharedTransition: true,
                    cardWidth: (this.screenWidth - 40 - 12 * (ResponsiveSizeClassResolver.columns(this.screenWidth) + 1)) /
                      (ResponsiveSizeClassResolver.columns(this.screenWidth) + 1),
                    onCardClick: (transitionId: string) => {
                      void this.getUIContext().getRouter().pushUrl({ url: 'pages/emby/EmbyDetailPage',
                        params: buildEmbyDetailRouteParams(this.sourceId, item, transitionId,
                          this.provider?.imageUrlFor(item, 360) ?? '') })
                    } })
                }.margin({ right: 12, bottom: 18 })
              }, (item: EmbyItem) => item.id)
            }.width('100%')
          } else {
            Text(this.query.trim().length === 0 ? '输入关键词，搜索当前服务中的作品' : '没有找到相关作品')
              .fontSize(15).fontColor($r('app.color.text_secondary')).width('100%')
              .textAlign(TextAlign.Start).margin({ top: 16 })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, bottom: 24 + this.bottomSafeHeight })
      }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Vertical).edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(this.titleOptions())
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP]).bindToScrollable([this.scroller])
  }
}
