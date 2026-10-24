import { CatVodVideo } from '../../providers/catvod/CatVodModels'
import { HomeMediaCarousel } from '../../components/media/carousel/HomeMediaCarousel'
import { CatVodHeroPresentation } from './CatVodHeroPresentation'
import { HomeHeroPalette } from '../../services/media/HomeHeroPalette'
import { HomeHeroSyncTrace } from '../../services/media/HomeHeroSyncTrace'

/** Cat data and palette adapter for the shared home carousel. */
@Component
export struct CatVodHeroBanner {
  @Prop items: CatVodVideo[] = []
  @Prop @Watch('resetPosition') version: number = 0
  @Prop topInset: number = 0
  @Prop viewportWidth: number = 360
  @Prop @Watch('onActivityChanged') isActive: boolean = true
  @StorageLink('appInForeground') @Watch('onActivityChanged') foreground: boolean = true
  @State private currentIndex: number = 0
  private alive: boolean = false
  private paletteRequest: number = 0
  private visualProgress: number = 0
  private progressReady: boolean = false
  private lastColor: string = ''
  private failedArtwork: Set<string> = new Set()
  onOpen: (video: CatVodVideo) => void = () => {}
  onColorChanged: (color: string) => void = () => {}

  aboutToAppear(): void { this.alive = true; void this.updatePalette(); void this.warmColors() }
  private resetPosition(): void {
    this.currentIndex = 0; this.visualProgress = 0; this.progressReady = false; this.lastColor = ''
    this.failedArtwork.clear(); void this.updatePalette(); void this.warmColors()
  }
  aboutToDisappear(): void { this.alive = false; this.paletteRequest++ }
  private onActivityChanged(): void {
    this.paletteRequest++
    if (this.alive && this.isActive && this.foreground) { void this.updatePalette(); void this.warmColors() }
  }
  private changeSlide(index: number): void {
    if (index < 0 || index >= this.items.length) return
    this.currentIndex = index
    if (!this.progressReady) this.visualProgress = index
    void this.updatePalette()
  }

  private followProgress(position: number): void {
    if (!Number.isFinite(position)) return
    this.visualProgress = position; this.progressReady = true; this.publishProgressColor()
  }

  private publishProgressColor(allowEmpty: boolean = false): void {
    if (!this.alive || !this.isActive || !this.foreground) return
    const color = HomeHeroPalette.at(this.items.map((item: CatVodVideo) => item.poster),
      this.progressReady ? this.visualProgress : this.currentIndex, this.failedArtwork)
    HomeHeroSyncTrace.palette('cat', color.length > 0, color)
    if ((!allowEmpty && color.length === 0) || color === this.lastColor) return
    this.lastColor = color; this.onColorChanged(color)
  }

  private async warmColors(): Promise<void> {
    if (!this.alive || !this.isActive || !this.foreground) return
    const version = this.version
    await HomeHeroPalette.warm(this.items.map((item: CatVodVideo) => item.poster), () => {
      if (version === this.version) this.publishProgressColor()
    }, this.currentIndex, () => this.alive && this.isActive && this.foreground && version === this.version)
  }
  private artworkFailed(url: string): void {
    this.failedArtwork.add(url)
    if (this.items[this.currentIndex]?.poster === url) {
      this.paletteRequest++
      if (this.alive && this.isActive) { this.lastColor = ''; this.onColorChanged('') }
    }
  }
  private async updatePalette(): Promise<void> {
    const request = ++this.paletteRequest
    if (!this.alive || !this.isActive || !this.foreground) return
    const url = this.items[this.currentIndex]?.poster ?? ''
    if (url.length === 0 || this.failedArtwork.has(url)) { this.publishProgressColor(true); return }
    const version = this.version
    await HomeHeroPalette.resolve(url)
    if (!this.alive || !this.isActive || !this.foreground || request !== this.paletteRequest ||
      version !== this.version || this.items[this.currentIndex]?.poster !== url) return
    this.publishProgressColor(true)
  }

  private openItem(id: string): void {
    const video = this.items.find((item: CatVodVideo) => item.id === id)
    if (video !== undefined) this.onOpen(video)
  }

  build() {
    HomeMediaCarousel({ items: CatVodHeroPresentation.carouselItems(this.items), currentIndex: this.currentIndex, diagnosticKind: 'cat',
      version: this.version, topInset: this.topInset, viewportWidth: this.viewportWidth, isActive: this.isActive,
      onIndexChanged: (index: number) => this.changeSlide(index), onProgress: (position: number) => this.followProgress(position),
      onOpen: (id: string) => this.openItem(id),
      onArtworkError: (url: string) => this.artworkFailed(url) })
  }
}
