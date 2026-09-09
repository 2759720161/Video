import { EmbyPlaybackLauncher } from '../../providers/emby/EmbyPlaybackLauncher'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationIconOptions, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { EmbyItem, EmbyServerConfig } from '../../providers/emby/EmbyModels'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { EmbySourceConfigCodec } from '../../providers/emby/EmbySourceConfig'
import { PreferencesStore } from '../../store/PreferencesStore'
import { buildImmersiveTitleBarStyle, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL, getTopSpacerHeight } from '../../utils/HdsPageStyle'

const EMBY_GREEN: string = '#52B54B'
const EMBY_GREEN_DARK: string = '#27833C'
const EMBY_WINE: string = '#3A0807'
const EMBY_WINE_LIGHT: string = '#6D1712'
const EMBY_HOME_CACHE_KEY_PREFIX: string = 'embyHomeCacheV1_'

class EmbyHomeSection {
  id: string = ''
  title: string = ''
  collectionType: string = ''
  items: EmbyItem[] = []
}

class EmbyHomeCachePayload {
  timestamp: number = 0
  libraries: EmbyItem[] = []
  resumeItems: EmbyItem[] = []
  latestItems: EmbyItem[] = []
  sections: EmbyHomeSection[] = []
}

@Entry
@Component
struct EmbyLibraryPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private title: string = 'Emby'
  @State private sourceId: string = ''
  @State private pendingItemId: string = ''
  @State private parentId: string = ''
  @State private latestOnly: boolean = false
  @State private libraryRoot: boolean = false
  @State private collectionType: string = ''
  @State private config: EmbyServerConfig | null = null
  @State private provider: EmbyProvider | null = null
  @State private items: EmbyItem[] = []
  @State private resumeItems: EmbyItem[] = []
  @State private latestItems: EmbyItem[] = []
  @State private homeSections: EmbyHomeSection[] = []
  @State private loading: boolean = true
  @State private errorText: string = ''
  @State private playingItemId: string = ''
  @State private pressedCardKey: string = ''
  @State private searchText: string = ''
  @State private showSearch: boolean = false
  @State private selectedFilter: string = '全部'
  @State private selectedHomeTab: string = '首页'
  @State private pageWidth: number = 360
  private scroller: Scroller = new Scroller()
  private filters: string[] = ['全部', '电影', '剧集', '文件夹']
  private loadGeneration: number = 0

  aboutToAppear(): void {
    const rawParams = this.getUIContext().getRouter().getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      if (typeof params['parentId'] === 'string') this.parentId = (params['parentId'] as string).trim()
      if (typeof params['sourceId'] === 'string') this.sourceId = (params['sourceId'] as string).trim()
      if (typeof params['itemId'] === 'string') this.pendingItemId = (params['itemId'] as string).trim()
      if (typeof params['title'] === 'string' && (params['title'] as string).trim().length > 0) {
        this.title = (params['title'] as string).trim()
      }
      if (params['view'] === 'latest') this.latestOnly = true
      if (params['libraryRoot'] === true || params['libraryRoot'] === 'true') this.libraryRoot = true
      if (typeof params['collectionType'] === 'string') {
        this.collectionType = (params['collectionType'] as string).trim()
      }
    }
    this.loadItems()
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.isHome() && this.latestItems.length > 0 && this.itemImageUrl(this.latestItems[0], 1000).length > 0) {
        Image(this.itemImageUrl(this.latestItems[0], 1000))
          .width('100%')
          .height(560)
          .objectFit(ImageFit.Cover)
          .blur(14)
          .opacity(0.38)
          .draggable(false)
          .align(Alignment.Top)
      }

      Column()
        .width('100%')
        .height(620)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#22000000', 0], [EMBY_WINE_LIGHT, 0.48], [EMBY_WINE, 1]]
        })
        .align(Alignment.Top)

      HdsNavigation() {
        Scroll(this.scroller) {
          Column() {
            Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')

          if (this.showSearch) {
            this.SearchBar()
          }

          if (this.loading) {
            this.LoadingState()
          } else if (this.errorText.length > 0) {
            this.ErrorState()
          } else if (this.searchText.trim().length > 0) {
            this.SearchResults()
          } else if (this.isHome()) {
            if (this.selectedHomeTab === '首页') {
              this.HomeContent()
            } else if (this.selectedHomeTab === '进度') {
              this.ProgressContent()
            } else {
              this.MediaLibrariesContent()
            }
          } else {
            this.LibraryContent()
          }

          Blank().height(this.bottomSafeHeight + 28).width('100%')
          }
          .width('100%')
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
      .titleBar(this.buildEmbyTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.isHome())
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

    }
    .width('100%')
    .height('100%')
    .backgroundColor(EMBY_WINE)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.pageWidth = Math.max(320, newArea.width as number)
    })
  }

  private buildEmbyTitleBarOptions(): HdsNavigationTitleBarOptions {
    const mainTitle: string = this.isHome() ?
      (this.config === null || this.config!.serverName.length === 0 ? 'Emby' : this.config!.serverName) :
      this.title
    const subTitle: string = this.isHome() ?
      (this.config === null || this.config!.userName.length === 0 ? '媒体中心' : this.config!.userName) :
      this.items.length + ' 个项目'
    const base: HdsNavigationTitleBarOptions = {
      style: buildImmersiveTitleBarStyle(this.hdsMaterialLevel),
      content: {
        title: { mainTitle: mainTitle, subTitle: subTitle },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.magnifyingglass'),
                label: '搜索 Emby 内容',
                action: (): void => {
                  this.showSearch = !this.showSearch
                  if (!this.showSearch) this.searchText = ''
                }
              } as HdsNavigationIconOptions
            },
            {
              content: {
                icon: this.isHome() ? $r('sys.symbol.folder_fill') : $r('sys.symbol.arrow_clockwise'),
                label: this.isHome() ? '媒体库' : '刷新 Emby 内容',
                action: (): void => {
                  if (this.isHome()) {
                    this.selectedHomeTab = '媒体库'
                  } else {
                    this.loadItems()
                  }
                }
              } as HdsNavigationIconOptions
            }
          ]
        }
      },
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
    return base
  }

  @Builder
  private SearchBar(): void {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor(['#BFFFFFFF'])
      TextInput({ placeholder: '搜索当前页面', text: this.searchText })
        .layoutWeight(1)
        .height(46)
        .fontSize(15)
        .fontColor(Color.White)
        .placeholderColor('#99FFFFFF')
        .backgroundColor(Color.Transparent)
        .padding(0)
        .onChange((value: string) => this.searchText = value)
      if (this.searchText.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(18)
          .fontColor(['#BFFFFFFF'])
          .onClick(() => this.searchText = '')
      }
    }
    .width('calc(100% - ' + this.pagePadding() * 2 + 'vp)')
    .height(48)
    .padding({ left: 14, right: 14 })
    .margin({ left: this.pagePadding(), right: this.pagePadding(), bottom: 14 })
    .borderRadius(16)
    .backgroundColor('#48000000')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.7, color: '#38FFFFFF' })
  }

  @Builder
  private HomeContent(): void {
    Column({ space: 30 }) {
      if (this.latestItems.length > 0) {
        this.FeaturedStrip()
      }

      if (this.resumeItems.length > 0) {
        this.HomeMediaSection('继续观看', this.resumeItems, 'resume')
      }

      ForEach(this.homeSections, (section: EmbyHomeSection) => {
        if (section.items.length > 0) {
          this.HomeMediaSection(section.title, section.items, section.id, section.collectionType)
        }
      }, (section: EmbyHomeSection) => 'section_' + section.id)

      if (this.latestItems.length === 0 && this.resumeItems.length === 0 && this.homeSections.length === 0) {
        this.InlineEmptyState('服务器没有返回可显示的媒体')
      }
    }
    .width('100%')
    .padding({ top: 6 })
  }

  @Builder
  private FeaturedStrip(): void {
    Column({ space: 14 }) {
      Row() {
        Text('最近更新')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Row() {
          Text('全部').fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White)
        }
        .height(34)
        .padding({ left: 16, right: 16 })
        .borderRadius(18)
        .backgroundColor('#30000000')
        .border({ width: 0.6, color: '#30FFFFFF' })
        .onClick(() => this.openSection('latest', '最近更新'))
      }
      .width('100%')
      .padding({ left: this.pagePadding(), right: this.pagePadding() })

      Scroll() {
        Row({ space: 16 }) {
          ForEach(this.featuredItems(), (item: EmbyItem) => {
            this.ReferencePosterCard(item, true)
          }, (item: EmbyItem) => 'featured_' + item.id)
        }
        .padding({ left: this.pagePadding(), right: this.pagePadding() })
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private HomeMediaSection(title: string, source: EmbyItem[], sectionId: string,
    collectionType: string = ''): void {
    Column({ space: 14 }) {
      Row() {
        Text(title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Row({ space: 5 }) {
          Text('全部').fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([Color.White])
        }
        .height(34)
        .padding({ left: 14, right: 12 })
        .borderRadius(18)
        .backgroundColor('#30000000')
        .border({ width: 0.6, color: '#30FFFFFF' })
        .onClick(() => this.openSection(sectionId, title, collectionType))
      }
      .width('100%')
      .padding({ left: this.pagePadding(), right: this.pagePadding() })

      Scroll() {
        Row({ space: 16 }) {
          ForEach(source, (item: EmbyItem) => {
            this.ReferencePosterCard(item, false)
          }, (item: EmbyItem) => sectionId + '_' + item.id)
        }
        .padding({ left: this.pagePadding(), right: this.pagePadding() })
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
  }

  @Builder
  private ReferencePosterCard(item: EmbyItem, featured: boolean): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.ItemImage(item, this.referenceCardWidth(), featured ? this.referenceFeaturedHeight() :
          this.referencePosterHeight())
        if (item.userData.playedPercentage > 0 && !item.userData.played) {
          Text(Math.round(item.userData.playedPercentage) + '%')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor('#B0000000')
        }
        if (this.playingItemId === item.id) {
          this.PlayingOverlay()
        }
      }
      .width(this.referenceCardWidth())
      .height(featured ? this.referenceFeaturedHeight() : this.referencePosterHeight())
      .clip(true)
      .borderRadius(17)
      .backgroundColor('#381716')

      Text(item.name)
        .width(this.referenceCardWidth())
        .fontSize(featured ? 17 : 16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.subtitle())
        .width(this.referenceCardWidth())
        .fontSize(13)
        .fontColor('#AFFFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .onClick(() => this.openItem(item))
    .scale({ x: this.cardScale('featured_' + item.id), y: this.cardScale('featured_' + item.id) })
    .opacity(this.cardOpacity('featured_' + item.id))
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => this.handleCardTouch('featured_' + item.id, event))
  }

  @Builder
  private ServerHero(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(150)
        .height(150)
        .borderRadius(75)
        .backgroundColor('#20FFFFFF')
        .position({ x: '70%', y: -45 })

      Column({ space: 16 }) {
        Row() {
          Column({ space: 4 }) {
            Text(this.config === null || this.config!.serverName.length === 0 ? '我的 Emby' : this.config!.serverName)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.config === null ? '媒体服务器' : this.config!.baseUrl)
              .fontSize(12)
              .fontColor('#CCFFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Row({ space: 6 }) {
            Circle().width(7).height(7).fill('#B9F7B4')
            Text('在线').fontSize(12).fontColor(Color.White)
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('#24FFFFFF')
        }
        .width('100%')

        Row({ space: 20 }) {
          this.HeroMetric(String(this.items.length), '媒体库')
          this.HeroMetric(String(this.resumeItems.length), '待续播')
          this.HeroMetric(this.config === null ? '—' : this.config!.serverVersion, '版本')
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(22)
    }
    .width('100%')
    .height(176)
    .clip(true)
    .borderRadius(24)
    .linearGradient({
      direction: GradientDirection.RightBottom,
      colors: [[EMBY_GREEN, 0], [EMBY_GREEN_DARK, 0.6], ['#164E3A', 1]]
    })
    .shadow({ radius: 18, color: '#3052B54B', offsetY: 8 })
  }

  @Builder
  private HeroMetric(value: string, label: string): void {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label).fontSize(11).fontColor('#BFFFFFFF')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SectionTitle(title: string, detail: string): void {
    Row() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(detail)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ResumeCard(item: EmbyItem): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        this.ItemImage(item, 232, 130)
        Column()
          .width('100%')
          .height(54)
          .linearGradient({
            direction: GradientDirection.Top,
            colors: [['#B0000000', 0], ['#00000000', 1]]
          })
        Row() {
          Text(Math.round(item.userData.playedPercentage) + '%')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(15).fontColor([Color.White])
        }
        .padding({ left: 12, right: 12, bottom: 10 })
        .width('100%')
        Progress({ value: item.userData.playedPercentage, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(EMBY_GREEN)
          .backgroundColor('#45FFFFFF')
      }
      .width(232)
      .height(130)
      .clip(true)
      .borderRadius(16)
      .backgroundColor($r('app.color.skeleton_background'))

      Text(item.name)
        .width(232)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.subtitle())
        .width(232)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .onClick(() => this.openItem(item))
    .scale({ x: this.cardScale('resume_' + item.id), y: this.cardScale('resume_' + item.id) })
    .opacity(this.cardOpacity('resume_' + item.id))
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => this.handleCardTouch('resume_' + item.id, event))
  }

  @Builder
  private CompactPosterCard(item: EmbyItem): void {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.ItemImage(item, 126, 178)
        if (this.playingItemId === item.id) {
          this.PlayingOverlay()
        }
      }
      .width(126)
      .height(178)
      .clip(true)
      .borderRadius(15)
      .backgroundColor($r('app.color.skeleton_background'))
      Text(item.name)
        .width(126)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.subtitle())
        .width(126)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .onClick(() => this.openItem(item))
    .scale({ x: this.cardScale('compact_' + item.id), y: this.cardScale('compact_' + item.id) })
    .opacity(this.cardOpacity('compact_' + item.id))
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => this.handleCardTouch('compact_' + item.id, event))
  }

  @Builder
  private LibraryTiles(): void {
    Grid() {
      ForEach(this.items, (item: EmbyItem) => {
        GridItem() {
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.itemImageUrl(item, 700).length > 0) {
              Image(this.itemImageUrl(item, 700))
                .width('100%')
                .height(126)
                .objectFit(ImageFit.Cover)
                .draggable(false)
                .opacity(0.72)
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.play_round_rectangle'))
                  .fontSize(40)
                  .fontColor(['#BFFFFFFF'])
              }
              .width('100%')
              .height(126)
              .justifyContent(FlexAlign.Center)
            }
            Column()
              .width('100%')
              .height(86)
              .linearGradient({
                direction: GradientDirection.Top,
                colors: [['#C9000000', 0], ['#00000000', 1]]
              })
            Row() {
              Column({ space: 3 }) {
                Text(item.name)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text('进入媒体库').fontSize(11).fontColor('#C8FFFFFF')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(17).fontColor([Color.White])
            }
            .width('100%')
            .padding({ left: 16, right: 14, bottom: 14 })
          }
          .height(126)
          .clip(true)
          .borderRadius(18)
          .backgroundColor('#163A35')
          .onClick(() => this.openItem(item, true))
        }
      }, (item: EmbyItem) => 'library_' + item.id)
    }
    .columnsTemplate(this.libraryColumns())
    .columnsGap(12)
    .rowsGap(12)
    .width('100%')
  }

  @Builder
  private ProgressContent(): void {
    Column({ space: 18 }) {
      Row() {
        Text('观看进度')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Text(this.resumeItems.length + ' 项').fontSize(13).fontColor('#AFFFFFFF')
      }
      .width('100%')

      if (this.resumeItems.length === 0) {
        this.InlineEmptyState('还没有未看完的内容')
      } else {
        this.PosterGrid(this.resumeItems)
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 12 })
  }

  @Builder
  private MediaLibrariesContent(): void {
    Column({ space: 18 }) {
      Row() {
        Text('媒体库')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Text(this.items.length + ' 个').fontSize(13).fontColor('#AFFFFFFF')
      }
      .width('100%')

      if (this.items.length === 0) {
        this.InlineEmptyState('服务器没有返回可访问的媒体库')
      } else {
        this.LibraryTiles()
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 12 })
  }

  @Builder
  private LibraryContent(): void {
    Column({ space: 16 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.filters, (filter: string) => {
            Text(filter)
              .fontSize(13)
              .fontWeight(this.selectedFilter === filter ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.selectedFilter === filter ? Color.White : '#C8FFFFFF')
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
              .borderRadius(18)
              .backgroundColor(this.selectedFilter === filter ? EMBY_GREEN : '#28000000')
              .border({ width: 0.5, color: this.selectedFilter === filter ? EMBY_GREEN :
                '#30FFFFFF' })
              .onClick(() => this.selectedFilter = filter)
          }, (filter: string) => filter)
        }
        .padding({ right: this.pagePadding() })
      }
      .width('calc(100% + ' + this.pagePadding() + 'vp)')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      Row() {
        Text(this.filteredItems().length + ' 个项目')
          .fontSize(13)
          .fontColor('#AFFFFFFF')
          .layoutWeight(1)
        Text('按名称排序').fontSize(12).fontColor('#AFFFFFFF')
      }
      .width('100%')

      if (this.filteredItems().length === 0) {
        this.InlineEmptyState('当前分类没有可显示的内容')
      } else {
        this.PosterGrid(this.filteredItems())
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 10 })
  }

  @Builder
  private SearchResults(): void {
    Column({ space: 16 }) {
      Row() {
        Text('搜索结果')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Text(this.searchResults().length + ' 项').fontSize(12).fontColor('#AFFFFFFF')
      }
      .width('100%')

      if (this.searchResults().length === 0) {
        this.InlineEmptyState('没有找到“' + this.searchText.trim() + '”')
      } else {
        this.PosterGrid(this.searchResults())
      }
    }
    .width('100%')
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: 10 })
  }

  @Builder
  private PosterGrid(source: EmbyItem[]): void {
    Grid() {
      ForEach(source, (item: EmbyItem) => {
        GridItem() {
          this.MediaCard(item)
        }
      }, (item: EmbyItem) => 'poster_' + item.id)
    }
    .columnsTemplate(this.posterColumns())
    .columnsGap(12)
    .rowsGap(18)
    .width('100%')
  }

  @Builder
  private MediaCard(item: EmbyItem): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.ItemImage(item, '100%', this.posterHeight())
        if (item.isFolder && this.itemImageUrl(item).length === 0) {
          SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(42).fontColor([EMBY_GREEN])
        }
        if (this.playingItemId === item.id) {
          this.PlayingOverlay()
        }
        if (item.userData.playedPercentage > 0 && !item.userData.played) {
          Progress({ value: item.userData.playedPercentage, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color(EMBY_GREEN)
            .backgroundColor('#55000000')
            .align(Alignment.Bottom)
        }
      }
      .width('100%')
      .height(this.posterHeight())
      .clip(true)
      .borderRadius(16)
      .backgroundColor($r('app.color.skeleton_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_light'), offsetY: 4 })

      Text(item.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(item.subtitle())
        .fontSize(11)
        .fontColor('#AFFFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .onClick(() => this.openItem(item))
    .scale({ x: this.cardScale('media_' + item.id), y: this.cardScale('media_' + item.id) })
    .opacity(this.cardOpacity('media_' + item.id))
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => this.handleCardTouch('media_' + item.id, event))
  }

  private cardScale(cardKey: string): number {
    return this.pressedCardKey === cardKey ? 0.96 : 1
  }

  private cardOpacity(cardKey: string): number {
    return this.pressedCardKey === cardKey ? 0.84 : 1
  }

  private handleCardTouch(cardKey: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedCardKey = cardKey
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.pressedCardKey === cardKey) {
        this.pressedCardKey = ''
      }
    }
  }

  @Builder
  private ItemImage(item: EmbyItem, width: Length, height: Length): void {
    if (this.itemImageUrl(item).length > 0) {
      Image(this.itemImageUrl(item))
        .width(width)
        .height(height)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Column() {
        SymbolGlyph(item.isFolder ? $r('sys.symbol.folder_fill') : $r('sys.symbol.play_fill'))
          .fontSize(38)
          .fontColor([item.isFolder ? EMBY_GREEN : $r('app.color.text_secondary')])
      }
      .width(width)
      .height(height)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  private PlayingOverlay(): void {
    Column() {
      LoadingProgress().width(32).height(32).color(Color.White)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#78000000')
  }

  @Builder
  private LoadingState(): void {
    Column({ space: 16 }) {
      LoadingProgress().width(44).height(44).color(EMBY_GREEN)
      Text(this.isHome() ? '正在同步媒体首页' : '正在读取“' + this.title + '”')
        .fontSize(14)
        .fontColor('#BFFFFFFF')
    }
    .width('100%')
    .height(420)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorState(): void {
    Column({ space: 14 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([$r('app.color.status_error')])
      }
      .width(68)
      .height(68)
      .justifyContent(FlexAlign.Center)
      .borderRadius(22)
      .backgroundColor($r('app.color.card_background'))
      Text('媒体库暂时不可用')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(this.errorText)
        .fontSize(13)
        .fontColor('#BFFFFFFF')
        .textAlign(TextAlign.Center)
        .maxLines(3)
      Button(this.config === null ? '配置服务器' : '重新加载')
        .fontColor(Color.White)
        .backgroundColor(EMBY_GREEN)
        .onClick(() => this.config === null ? this.openSettings() : this.loadItems())
    }
    .width('100%')
    .height(420)
    .padding({ left: 32, right: 32 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private InlineEmptyState(message: string): void {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.folder')).fontSize(38).fontColor(['#AFFFFFFF'])
      Text(message).fontSize(14).fontColor('#BFFFFFFF').textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(220)
    .justifyContent(FlexAlign.Center)
  }

  private async loadItems(): Promise<void> {
    const generation = ++this.loadGeneration
    this.loading = true
    this.errorText = ''
    let hasCachedHome = false
    try {
      if (this.sourceId.length === 0) {
        this.errorText = '媒体源参数无效，请从媒体来源列表进入'
        return
      }
      const source = await MediaSourceStore.getById(this.sourceId)
      if (generation !== this.loadGeneration) return
      if (source === null || !source.enabled || source.providerType !== 'emby') {
        this.errorText = 'Emby 媒体源不可用或已停用'
        return
      }
      this.config = EmbySourceConfigCodec.decode(source.configJson)
      if (generation !== this.loadGeneration) return
      if (this.config === null) {
        this.errorText = 'Emby 媒体源配置无效'
        return
      }
      const registeredProvider = await ProviderRegistry.get(this.sourceId,
        this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (!(registeredProvider instanceof EmbyProvider)) {
        this.errorText = 'Emby 媒体源不可用或已停用'
        return
      }
      this.provider = registeredProvider
      if (this.isHome()) {
        hasCachedHome = await this.restoreHomeCache(this.config!)
        if (generation !== this.loadGeneration) return
        if (hasCachedHome) {
          this.loading = false
        }
        this.items = await this.provider.getLibrariesRaw()
        if (generation !== this.loadGeneration) return
        const tasks: Array<Promise<EmbyItem[]>> = [
          this.loadResumeItems(this.provider),
          this.loadLatestItems(this.provider)
        ]
        const results: EmbyItem[][] = await Promise.all(tasks)
        if (generation !== this.loadGeneration) return
        this.resumeItems = results[0]
        this.latestItems = results[1]
        this.homeSections = await this.loadHomeSections(this.provider, this.items)
        if (generation !== this.loadGeneration) return
        await this.saveHomeCache()
      } else {
        if (this.latestOnly) {
          this.items = await this.provider.getLatestItemsRaw(0)
        } else if (this.libraryRoot) {
          // Library entry pages should show media posters, not the server's
          // physical folder tree. Nested item pages keep the old behavior.
          this.items = await this.provider.getLibraryItemsRaw(this.parentId, 0, this.collectionType)
        } else {
          this.items = await this.provider.getItemsRaw(this.parentId)
        }
        if (generation !== this.loadGeneration) return
        this.resumeItems = []
        this.latestItems = []
        this.homeSections = []
      }
    } catch (err) {
      if (generation === this.loadGeneration && !hasCachedHome) {
        this.items = []
        this.resumeItems = []
        this.latestItems = []
        this.homeSections = []
        this.errorText = err instanceof Error ? err.message : 'Emby 媒体库读取失败'
      }
    } finally {
      if (generation !== this.loadGeneration) return
      this.loading = false
      if (this.pendingItemId.length > 0 && this.config !== null && this.provider !== null) {
        void this.openPendingItem()
      }
    }
  }

  private async openPendingItem(): Promise<void> {
    const itemId = this.pendingItemId
    this.pendingItemId = ''
    if (itemId.length === 0 || this.config === null || this.provider === null || this.sourceId.length === 0) return
    try {
      const item = await this.provider.getItemRaw(itemId)
      if (item !== null && !item.isFolder) await this.openItem(item)
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法打开远程播放记录' })
    }
  }

  private homeCacheKey(config: EmbyServerConfig): string {
    return EMBY_HOME_CACHE_KEY_PREFIX + encodeURIComponent(
      config.serverId + '|' + config.userId + '|' + config.baseUrl)
  }

  private async restoreHomeCache(config: EmbyServerConfig): Promise<boolean> {
    try {
      const raw = await PreferencesStore.getInstance().getString(this.homeCacheKey(config), '')
      if (raw.length === 0) return false
      const parsed = JSON.parse(raw) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return false
      const payload = parsed as Record<string, Object>
      const timestamp = typeof payload['timestamp'] === 'number' ? payload['timestamp'] as number : 0
      if (timestamp <= 0) return false
      this.items = this.decodeCachedItems(payload['libraries'])
      this.resumeItems = this.decodeCachedItems(payload['resumeItems'])
      this.latestItems = this.decodeCachedItems(payload['latestItems'])
      this.homeSections = this.decodeCachedSections(payload['sections'])
      return true
    } catch (_err) {
      return false
    }
  }

  private async saveHomeCache(): Promise<void> {
    if (this.config === null) return
    try {
      const payload = new EmbyHomeCachePayload()
      payload.timestamp = Date.now()
      payload.libraries = this.items
      payload.resumeItems = this.resumeItems
      payload.latestItems = this.latestItems
      payload.sections = this.homeSections
      await PreferencesStore.getInstance().setString(this.homeCacheKey(this.config!), JSON.stringify(payload))
    } catch (_err) {
      // Cache failures must never affect the Emby page.
    }
  }

  private decodeCachedItems(raw: Object): EmbyItem[] {
    if (!Array.isArray(raw)) return []
    const result: EmbyItem[] = []
    const values = raw as Array<Record<string, Object>>
    for (let i = 0; i < values.length; i++) {
      const candidate = values[i] as Object
      if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) continue
      const value = candidate as Record<string, Object>
      const item = new EmbyItem()
      item.id = this.cachedString(value, 'id')
      item.name = this.cachedString(value, 'name')
      item.type = this.cachedString(value, 'type')
      item.parentId = this.cachedString(value, 'parentId')
      item.collectionType = this.cachedString(value, 'collectionType')
      item.isFolder = this.cachedBoolean(value, 'isFolder')
      item.runTimeTicks = this.cachedNumber(value, 'runTimeTicks')
      item.productionYear = this.cachedNumber(value, 'productionYear')
      item.indexNumber = this.cachedNumber(value, 'indexNumber')
      item.parentIndexNumber = this.cachedNumber(value, 'parentIndexNumber')
      item.seriesName = this.cachedString(value, 'seriesName')
      item.overview = this.cachedString(value, 'overview')
      item.imageItemId = this.cachedString(value, 'imageItemId')
      item.primaryImageTag = this.cachedString(value, 'primaryImageTag')
      item.container = this.cachedString(value, 'container')
      const userData = value['userData']
      if (userData !== null && typeof userData === 'object') {
        const data = userData as Record<string, Object>
        item.userData.playbackPositionTicks = this.cachedNumber(data, 'playbackPositionTicks')
        item.userData.playedPercentage = this.cachedNumber(data, 'playedPercentage')
        item.userData.played = this.cachedBoolean(data, 'played')
      }
      if (item.id.length > 0 && item.name.length > 0) result.push(item)
    }
    return result
  }

  private decodeCachedSections(raw: Object): EmbyHomeSection[] {
    if (!Array.isArray(raw)) return []
    const result: EmbyHomeSection[] = []
    const values = raw as Array<Record<string, Object>>
    for (let i = 0; i < values.length; i++) {
      const candidate = values[i] as Object
      if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) continue
      const value = candidate as Record<string, Object>
      const section = new EmbyHomeSection()
      section.id = this.cachedString(value, 'id')
      section.title = this.cachedString(value, 'title')
      section.collectionType = this.cachedString(value, 'collectionType')
      section.items = this.decodeCachedItems(value['items'])
      if (section.id.length > 0 && section.items.length > 0) result.push(section)
    }
    return result
  }

  private cachedString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }

  private cachedNumber(value: Record<string, Object>, key: string): number {
    return typeof value[key] === 'number' && Number.isFinite(value[key] as number) ? value[key] as number : 0
  }

  private cachedBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }

  private async loadResumeItems(provider: EmbyProvider): Promise<EmbyItem[]> {
    try {
      return await provider.getResumeItemsRaw()
    } catch {
      return []
    }
  }

  private async loadLatestItems(provider: EmbyProvider): Promise<EmbyItem[]> {
    try {
      return await provider.getLatestItemsRaw()
    } catch {
      return []
    }
  }

  private async loadHomeSections(provider: EmbyProvider, libraries: EmbyItem[]): Promise<EmbyHomeSection[]> {
    const tasks: Array<Promise<EmbyItem[]>> = []
    for (let i = 0; i < libraries.length; i++) {
      tasks.push(this.loadLibraryPreview(provider, libraries[i]))
    }
    const previews: EmbyItem[][] = await Promise.all(tasks)
    const sections: EmbyHomeSection[] = []
    for (let i = 0; i < libraries.length; i++) {
      if (previews[i].length > 0) {
        const section = new EmbyHomeSection()
        section.id = libraries[i].id
        section.title = libraries[i].name
        section.collectionType = libraries[i].collectionType
        section.items = previews[i]
        sections.push(section)
      }
    }
    return sections
  }

  private async loadLibraryPreview(provider: EmbyProvider, library: EmbyItem): Promise<EmbyItem[]> {
    try {
      return await provider.getLibraryItemsRaw(library.id, 12, library.collectionType)
    } catch {
      return []
    }
  }

  private filteredItems(): EmbyItem[] {
    const result: EmbyItem[] = []
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i]
      if (this.matchesFilter(item, this.selectedFilter)) result.push(item)
    }
    return result
  }

  private searchResults(): EmbyItem[] {
    const keyword = this.searchText.trim().toLowerCase()
    if (keyword.length === 0) return []
    const source: EmbyItem[] = []
    this.appendUnique(source, this.items)
    this.appendUnique(source, this.resumeItems)
    this.appendUnique(source, this.latestItems)
    for (let i = 0; i < this.homeSections.length; i++) {
      this.appendUnique(source, this.homeSections[i].items)
    }
    const result: EmbyItem[] = []
    for (let i = 0; i < source.length; i++) {
      const item = source[i]
      if (item.name.toLowerCase().indexOf(keyword) >= 0 ||
        item.seriesName.toLowerCase().indexOf(keyword) >= 0) {
        result.push(item)
      }
    }
    return result
  }

  private appendUnique(target: EmbyItem[], source: EmbyItem[]): void {
    for (let i = 0; i < source.length; i++) {
      let exists = false
      for (let j = 0; j < target.length; j++) {
        if (target[j].id === source[i].id) {
          exists = true
          break
        }
      }
      if (!exists) target.push(source[i])
    }
  }

  private matchesFilter(item: EmbyItem, filter: string): boolean {
    if (filter === '全部') return true
    if (filter === '文件夹') return item.isFolder
    if (filter === '电影') return item.type === 'Movie' || item.type === 'Video'
    if (filter === '剧集') {
      return item.type === 'Series' || item.type === 'Season' || item.type === 'Episode'
    }
    return true
  }

  private itemImageUrl(item: EmbyItem, maxWidth: number = 500): string {
    return this.provider === null ? '' : this.provider.imageUrlFor(item, maxWidth)
  }

  private async openItem(item: EmbyItem, libraryRoot: boolean = false): Promise<void> {
    if (item.isFolder) {
      const params: Record<string, Object> = {
        'sourceId': this.sourceId,
        'parentId': item.id,
        'title': item.name
      }
      if (libraryRoot) {
        params['libraryRoot'] = true
        params['collectionType'] = item.collectionType
      }
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/emby/EmbyLibraryPage',
        params: params
      })
      return
    }
    if (this.config === null || this.playingItemId.length > 0) return
    this.playingItemId = item.id
    try {
      if (this.sourceId.length === 0) throw new Error('Emby 媒体源未配置')
      await EmbyPlaybackLauncher.open(this.getUIContext(), this.sourceId, item, this.getPlaybackQueue(item))
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法播放该 Emby 条目' })
    } finally {
      this.playingItemId = ''
    }
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/sources/SourceManagerPage' })
  }

  /** 保持连续播放在当前浏览或首页分区内，避免跨库、跨分区自动跳转。 */
  private getPlaybackQueue(item: EmbyItem): EmbyItem[] {
    const sources: EmbyItem[][] = [this.items, this.resumeItems, this.latestItems]
    for (let i = 0; i < this.homeSections.length; i++) sources.push(this.homeSections[i].items)
    for (let i = 0; i < sources.length; i++) {
      for (let j = 0; j < sources[i].length; j++) {
        if (sources[i][j].id === item.id) return sources[i]
      }
    }
    return [item]
  }

  private openSection(sectionId: string, sectionTitle: string, collectionType: string = ''): void {
    if (sectionId === 'resume') {
      this.selectedHomeTab = '进度'
      this.scroller.scrollEdge(Edge.Top)
      return
    }
    if (sectionId === 'latest') {
      // The latest-only page has no parentId and must not push itself again.
      if (this.latestOnly) return
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/emby/EmbyLibraryPage',
        params: { 'sourceId': this.sourceId, 'view': 'latest', 'title': sectionTitle }
      })
      return
    }
    const params: Record<string, Object> = {
      'sourceId': this.sourceId,
      'parentId': sectionId,
      'title': sectionTitle,
      'libraryRoot': true,
      'collectionType': collectionType
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/emby/EmbyLibraryPage',
      params: params
    })
  }

  private isHome(): boolean {
    // A latest-only route also has no parentId, but it is a list page rather
    // than the home page. Keeping it out of the home branch prevents the
    // "全部" entry from rendering again and recursively navigating.
    return this.parentId.length === 0 && !this.latestOnly
  }

  private featuredItems(): EmbyItem[] {
    const result: EmbyItem[] = []
    const limit = Math.min(6, this.latestItems.length)
    for (let i = 0; i < limit; i++) result.push(this.latestItems[i])
    return result
  }

  private pagePadding(): number {
    return this.pageWidth >= 840 ? 32 : 18
  }

  private referenceCardWidth(): number {
    if (this.pageWidth >= 840) return 176
    if (this.pageWidth >= 600) return 156
    return 132
  }

  private referenceFeaturedHeight(): number {
    return Math.round(this.referenceCardWidth() * 1.45)
  }

  private referencePosterHeight(): number {
    return Math.round(this.referenceCardWidth() * 1.48)
  }

  private libraryColumns(): string {
    if (this.pageWidth >= 900) return '1fr 1fr 1fr'
    if (this.pageWidth >= 560) return '1fr 1fr'
    return '1fr'
  }

  private posterColumns(): string {
    if (this.pageWidth >= 1100) return '1fr 1fr 1fr 1fr 1fr 1fr'
    if (this.pageWidth >= 840) return '1fr 1fr 1fr 1fr 1fr'
    if (this.pageWidth >= 600) return '1fr 1fr 1fr 1fr'
    if (this.pageWidth >= 410) return '1fr 1fr 1fr'
    return '1fr 1fr'
  }

  private posterHeight(): number {
    if (this.pageWidth >= 840) return 210
    if (this.pageWidth >= 600) return 200
    if (this.pageWidth >= 410) return 176
    return 218
  }
}
