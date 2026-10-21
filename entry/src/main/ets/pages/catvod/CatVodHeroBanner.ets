import { CatVodVideo } from '../../providers/catvod/CatVodModels'
import { CatVodHeroSlide } from './CatVodHeroSlide'
import { CatVodHeroPresentation } from './CatVodHeroPresentation'
import { HomeHeroPalette } from '../../services/media/HomeHeroPalette'

/** Kazumi-style featured carousel, supplied by the active Cat subscription. */
@Component
export struct CatVodHeroBanner {
  @Prop items: CatVodVideo[] = []
  @Prop @Watch('resetPosition') version: number = 0
  @Prop topInset: number = 0
  @Prop viewportWidth: number = 360
  @Prop @Watch('onActivityChanged') isActive: boolean = true
  @Prop surfaceColor: ResourceColor = $r('app.color.page_background')
  @StorageLink('appInForeground') @Watch('onActivityChanged') foreground: boolean = true
  @State private currentIndex: number = 0
  @State private visible: boolean = true
  private controller: SwiperController = new SwiperController()
  private alive: boolean = false
  private paletteRequest: number = 0
  private failedArtwork: Set<string> = new Set()
  onOpen: (video: CatVodVideo) => void = () => {}
  onColorChanged: (color: string) => void = () => {}

  aboutToAppear(): void { this.alive = true; void this.updatePalette() }
  private resetPosition(): void {
    this.currentIndex = 0; this.failedArtwork.clear(); void this.updatePalette()
  }
  aboutToDisappear(): void { this.alive = false; this.visible = false; this.paletteRequest++ }
  private canAutoPlay(): boolean { return this.isActive && this.foreground && this.visible && this.items.length > 1 }
  private onActivityChanged(): void {
    this.paletteRequest++
    if (this.alive && this.isActive && this.foreground) void this.updatePalette()
  }
  private changeSlide(index: number): void {
    if (index < 0 || index >= this.items.length) return
    this.currentIndex = index; void this.updatePalette()
  }
  private artworkFailed(url: string): void {
    this.failedArtwork.add(url)
    if (this.items[this.currentIndex]?.poster === url) {
      this.paletteRequest++
      if (this.alive && this.isActive) this.onColorChanged('')
    }
  }
  private async updatePalette(): Promise<void> {
    const request = ++this.paletteRequest
    if (!this.alive || !this.isActive || !this.foreground) return
    const url = this.items[this.currentIndex]?.poster ?? ''
    if (url.length === 0 || this.failedArtwork.has(url)) { this.onColorChanged(''); return }
    const version = this.version
    const color = await HomeHeroPalette.resolve(url)
    if (!this.alive || !this.isActive || !this.foreground || request !== this.paletteRequest ||
      version !== this.version || this.items[this.currentIndex]?.poster !== url) return
    this.onColorChanged(color)
    // Warm just the next cover; do not block the current slide on all six downloads.
    const next = this.items[(this.currentIndex + 1) % this.items.length]
    if (next !== undefined && next.poster !== url && !this.failedArtwork.has(next.poster)) {
      void HomeHeroPalette.resolve(next.poster)
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Swiper(this.controller) {
        ForEach(this.items, (video: CatVodVideo) => {
          CatVodHeroSlide({ video: video, topInset: this.topInset, viewportWidth: this.viewportWidth,
            surfaceColor: this.surfaceColor, onArtworkError: (url: string) => this.artworkFailed(url),
            onOpen: (item: CatVodVideo) => this.onOpen(item) })
        }, (video: CatVodVideo) => String(this.version) + ':hero:' + video.id)
      }.width('100%').height(CatVodHeroPresentation.height(this.viewportWidth, this.topInset))
        .index(this.currentIndex).autoPlay(this.canAutoPlay()).interval(5000)
        .loop(this.items.length > 1).indicator(false).cachedCount(1)
        .onChange((index: number) => this.changeSlide(index))
      Row({ space: 6 }) {
        ForEach(this.items, (video: CatVodVideo, index: number) => {
          Row().width(index === this.currentIndex ? 20 : 8).height(4).borderRadius(2)
            .backgroundColor(index === this.currentIndex ? $r('app.color.text_primary') : $r('app.color.text_hint'))
            .animation({ duration: 200, curve: Curve.EaseOut })
        }, (video: CatVodVideo) => String(this.version) + ':hero-dot:' + video.id)
      }.margin({ left: 20, bottom: 16 }).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
    }.width('100%').height(CatVodHeroPresentation.height(this.viewportWidth, this.topInset))
      .onVisibleAreaChange([0, 0.01], (isVisible: boolean, ratio: number) => { this.visible = isVisible && ratio > 0 })
  }
}
