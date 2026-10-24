import { curves, FrameCallback } from '@kit.ArkUI'
import { HomeCarouselItem } from './HomeCarouselItem'
import { HomeCarouselCard } from './HomeCarouselCard'
import { HomeCarouselLayout } from './HomeCarouselLayout'
import { HomeCarouselMotion } from './HomeCarouselMotion'
import { HomeHeroSyncTrace } from '../../../services/media/HomeHeroSyncTrace'

/** Shared overlapping Cover Flow; native Swiper owns gesture physics and the continuous color clock. */
@Component
export struct HomeMediaCarousel {
  @Prop @Watch('syncItems') items: HomeCarouselItem[] = []
  @Prop @Watch('syncSelection') currentIndex: number = 0
  @Prop @Watch('syncItems') version: number = 0
  @Prop viewportWidth: number = 360
  @Prop topInset: number = 0
  @Prop diagnosticKind: string = 'cat'
  @Prop @Watch('activityChanged') isActive: boolean = true
  @StorageLink('appInForeground') @Watch('activityChanged') foreground: boolean = true
  @State private visible: boolean = true
  @State private touching: boolean = false
  @State private displayIndex: number = 0
  @State private visualCenter: number = 0
  @State private interactionPaused: boolean = false
  @State private manualDuration: number = HomeCarouselMotion.TAP_DURATION_MS
  @State private renderedItems: HomeCarouselItem[] = []
  private autoCurve = curves.cubicBezierCurve(0.38, 0, 0.22, 1)
  private manualCurve = curves.cubicBezierCurve(0.22, 0.72, 0.18, 1)
  private contentKey: string = ''
  private metadataKey: string = ''
  private animating: boolean = false
  private itemLength: number = 0
  private alive: boolean = false
  private interactionTimer: number = -1
  private interactionTicket: number = 0
  private moveTicket: number = 0
  private pendingSlot: number = -1
  private controller: SwiperController = new SwiperController()
  private syncTrace: HomeHeroSyncTrace = new HomeHeroSyncTrace()
  onIndexChanged: (index: number) => void = () => {}
  onProgress: (position: number) => void = () => {}
  onOpen: (id: string) => void = () => {}
  onArtworkError: (url: string) => void = () => {}

  private syncItems(): void {
    const key = JSON.stringify([String(this.version), ...this.items.map((item: HomeCarouselItem) =>
      JSON.stringify([item.id, item.artworkUrl]))])
    const metadata = JSON.stringify(this.items.map((item: HomeCarouselItem) =>
      JSON.stringify([item.title, item.subtitle])))
    if (key !== this.contentKey || metadata !== this.metadataKey) {
      this.rebuildSlots(); this.metadataKey = metadata
    }
    if (key === this.contentKey) return
    this.cancelPendingMove()
    this.syncTrace.flush()
    this.contentKey = key
    this.displayIndex = HomeCarouselMotion.anchor(this.currentIndex, this.items.length)
    this.visualCenter = this.displayIndex; this.itemLength = 0; this.animating = false; this.touching = false
    this.cancelInteractionTimer(); this.interactionPaused = false
    this.reportProgress()
  }

  private syncSelection(): void {
    if (HomeCarouselMotion.itemIndex(this.displayIndex, this.items.length) ===
      HomeCarouselMotion.itemIndex(this.currentIndex, this.items.length)) return
    this.cancelPendingMove()
    this.syncTrace.flush()
    this.displayIndex = HomeCarouselMotion.anchor(this.currentIndex, this.items.length)
    this.visualCenter = this.displayIndex; this.itemLength = 0; this.animating = false
    this.cancelInteractionTimer(); this.interactionPaused = false
    this.reportProgress()
  }

  private slots(): HomeCarouselItem[] {
    return this.renderedItems
  }

  private rebuildSlots(): void {
    const result: HomeCarouselItem[] = []
    const count = HomeCarouselMotion.slotCount(this.items.length)
    for (let i = 0; i < count; i++) result.push(this.items[i % this.items.length])
    this.renderedItems = result
  }

  private slidePosition(index: number): number {
    return HomeCarouselMotion.relative(index, this.visualCenter,
      HomeCarouselMotion.slotCount(this.items.length))
  }

  private scrollPosition(index: number, value: number, mainAxisLength: number): void {
    const count = HomeCarouselMotion.slotCount(this.items.length)
    const center = HomeCarouselMotion.centerFromSample(index, value, mainAxisLength, HomeCarouselLayout.GAP, count)
    if (!Number.isFinite(center)) return
    // One near-center page drives every pose; offscreen/cached pages cannot rewind that clock.
    if (Math.abs(value * mainAxisLength / (mainAxisLength + HomeCarouselLayout.GAP)) > 0.75) return
    this.itemLength = mainAxisLength
    if (Math.abs(HomeCarouselMotion.relative(center, this.visualCenter, count)) < 0.00001) return
    this.visualCenter = center
    this.reportProgress()
  }

  private reportProgress(): void {
    if (this.items.length === 0) return
    const position = ((this.visualCenter % this.items.length) + this.items.length) % this.items.length
    this.syncTrace.sample(this.getUIContext(), this.diagnosticKind, position, () => this.onProgress(position))
  }

  private changeSlide(index: number): void {
    if (!Number.isInteger(index) || index < 0 || index >= HomeCarouselMotion.slotCount(this.items.length)) return
    this.displayIndex = index
    this.onIndexChanged(HomeCarouselMotion.itemIndex(index, this.items.length))
  }

  private cancelPendingMove(): void {
    this.moveTicket++; this.pendingSlot = -1
  }

  private moveToSlot(index: number): void {
    this.cancelPendingMove(); this.cancelInteractionTimer()
    const ticket = this.moveTicket
    const origin = this.displayIndex
    this.pendingSlot = index
    // State writes are batched. Start only after this frame has applied duration AND curve.
    // Calling the controller in the click callback can still read the preceding touch's 420 ms.
    try {
      this.getUIContext().postFrameCallback(new HomeCarouselTapFrame(() => {
        if (ticket !== this.moveTicket) return
        this.pendingSlot = -1
        if (!this.alive || !this.isActive || !this.foreground || !this.visible || this.touching ||
          this.animating || this.displayIndex !== origin) { this.resumeAfterInteraction(); return }
        this.startMoveToSlot(index)
        this.resumeAfterInteraction()
      }))
    } catch (_) { this.cancelPendingMove(); this.resumeAfterInteraction() }
  }

  private startMoveToSlot(index: number): void {
    const step = HomeCarouselMotion.relative(index, this.displayIndex,
      HomeCarouselMotion.slotCount(this.items.length))
    // Absolute indices can take the long route across the loop seam. Keep adjacent taps directional.
    if (step === 1) this.controller.showNext()
    else if (step === -1) this.controller.showPrevious()
    else this.controller.changeIndex(index, true)
  }

  private openSlot(index: number): void {
    if (this.animating || this.pendingSlot >= 0 || !this.alive || !this.isActive || !this.foreground || !this.visible || !Number.isInteger(index) || index < 0 ||
      index >= HomeCarouselMotion.slotCount(this.items.length)) return
    this.pauseInteraction()
    this.manualDuration = HomeCarouselMotion.TAP_DURATION_MS
    if (index !== this.displayIndex || Math.abs(this.slidePosition(index)) > 0.01) {
      this.moveToSlot(index); return
    }
    this.onOpen(this.items[HomeCarouselMotion.itemIndex(index, this.items.length)].id)
  }

  private activeItem(): HomeCarouselItem {
    return this.items[HomeCarouselMotion.itemIndex(this.displayIndex, this.items.length)] ?? new HomeCarouselItem()
  }

  private itemPosition(index: number): number {
    const count = HomeCarouselMotion.slotCount(this.items.length)
    let position = this.slidePosition(index)
    for (let slot = index + this.items.length; this.items.length > 0 && slot < count; slot += this.items.length) {
      const candidate = this.slidePosition(slot)
      if (Math.abs(candidate) < Math.abs(position)) position = candidate
    }
    return position
  }

  private captionWeight(index: number): number { return HomeCarouselMotion.captionWeight(this.itemPosition(index)) }

  private indicatorWeight(index: number): number { return HomeCarouselMotion.focusWeight(this.itemPosition(index)) }

  private switchDuration(): number {
    return this.interactionPaused ? this.manualDuration : HomeCarouselMotion.AUTO_DURATION_MS
  }

  private selectItem(index: number): void {
    if (this.animating || this.pendingSlot >= 0 || !this.alive || !this.isActive || !this.foreground || !this.visible || !Number.isInteger(index) ||
      index < 0 || index >= this.items.length) return
    const target = HomeCarouselMotion.nearestSlot(index, this.displayIndex, this.items.length)
    this.pauseInteraction()
    this.manualDuration = HomeCarouselMotion.TAP_DURATION_MS
    if (target !== this.displayIndex) this.moveToSlot(target)
  }

  private finishSlide(index: number, currentOffset?: number): void {
    if (Number.isInteger(index) && index >= 0 && index < HomeCarouselMotion.slotCount(this.items.length)) {
      this.displayIndex = index
      if (currentOffset !== undefined && Number.isFinite(currentOffset) && this.itemLength > 0) {
        const origin = HomeCarouselLayout.margin(this.viewportWidth) + HomeCarouselLayout.GAP
        this.scrollPosition(index, (currentOffset - origin) / this.itemLength, this.itemLength)
      }
    }
    this.animating = false; this.syncTrace.flush()
    if (this.interactionPaused) this.resumeAfterInteraction()
  }

  private cancelInteractionTimer(): void {
    this.interactionTicket++
    if (this.interactionTimer >= 0) clearTimeout(this.interactionTimer)
    this.interactionTimer = -1
  }

  private resumeAfterInteraction(): void {
    this.cancelInteractionTimer()
    if (!this.alive || !this.isActive || !this.foreground || !this.visible || this.touching ||
      this.animating || this.pendingSlot >= 0 || this.items.length < 2) return
    const ticket = this.interactionTicket
    this.interactionTimer = setTimeout(() => {
      if (ticket !== this.interactionTicket) return
      this.interactionTimer = -1
      if (this.alive && this.isActive && this.foreground && this.visible && !this.touching && !this.animating && this.pendingSlot < 0) {
        this.interactionPaused = false
      }
    }, HomeCarouselMotion.INTERACTION_PAUSE_MS)
  }

  private pauseInteraction(): void {
    this.interactionPaused = true; this.resumeAfterInteraction()
  }

  private beginSlide(): void {
    this.animating = true; this.cancelInteractionTimer()
  }

  private activityChanged(): void {
    if (this.isActive && this.foreground && this.visible) return
    this.cancelPendingMove()
    this.syncTrace.flush()
    this.cancelInteractionTimer(); this.interactionPaused = false; this.touching = false
  }

  private setCarouselVisibility(visible: boolean): void {
    this.visible = visible; this.activityChanged()
  }

  private canAutoPlay(): boolean {
    return this.isActive && this.foreground && this.visible && !this.touching && !this.interactionPaused && this.items.length > 1
  }

  aboutToAppear(): void { this.alive = true; this.visible = true; this.syncItems() }
  aboutToDisappear(): void { this.alive = false; this.setCarouselVisibility(false) }

  build() {
    Column({ space: 10 }) {
      if (this.items.length > 1) {
        Swiper(this.controller) {
          ForEach(this.slots(), (item: HomeCarouselItem, index: number) => {
            Column() {
              HomeCarouselCard({ artworkUrl: item.artworkUrl, title: item.title, subtitle: item.subtitle,
                viewportWidth: this.viewportWidth, posePosition: this.slidePosition(index),
                shadeOpacity: HomeCarouselMotion.shadeOpacity(this.slidePosition(index)),
                faceOpacity: HomeCarouselMotion.opacity(this.slidePosition(index)), onOpen: () => this.openSlot(index),
                onArtworkError: (url: string) => this.onArtworkError(url) })
            }.width('100%').height('100%').justifyContent(FlexAlign.Center)
              .zIndex(HomeCarouselMotion.depth(this.slidePosition(index)))
              .hitTestBehavior(Math.abs(this.slidePosition(index)) <= 1.01 ? HitTestMode.Default : HitTestMode.None)
          }, (item: HomeCarouselItem, index: number) => String(this.version) + ':' + String(index) + ':' + item.id + ':' + item.artworkUrl)
        }.width(HomeCarouselLayout.stageWidth(this.viewportWidth)).height(HomeCarouselLayout.stageHeight(this.viewportWidth))
          .index(this.displayIndex).indicator(false).autoPlay(this.canAutoPlay()).interval(5000)
          .loop(true).duration(this.switchDuration())
          .curve(this.interactionPaused && this.manualDuration === HomeCarouselMotion.DRAG_DURATION_MS ? this.manualCurve : this.autoCurve)
          .itemSpace(HomeCarouselLayout.GAP)
          .prevMargin(HomeCarouselLayout.margin(this.viewportWidth))
          // Pulled-in side faces can be visible before their native page enters the viewport.
          .nextMargin(HomeCarouselLayout.margin(this.viewportWidth)).cachedCount(1, true).clip(false)
          .onChange((index: number) => this.changeSlide(index))
          .onContentDidScroll((_selectedIndex: number, index: number, position: number, mainAxisLength: number) => {
            this.scrollPosition(index, position, mainAxisLength)
          })
          .onAnimationStart(() => this.beginSlide())
          .onAnimationEnd((index: number, info: SwiperAnimationEvent) => this.finishSlide(index, info.currentOffset))
          .onTouch((event: TouchEvent) => {
            if (!this.alive || !this.isActive || !this.foreground || !this.visible) return
            if (event.type === TouchType.Down) {
              this.cancelPendingMove()
              this.manualDuration = HomeCarouselMotion.DRAG_DURATION_MS
              this.touching = true; this.pauseInteraction()
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.touching = false; this.pauseInteraction()
            }
          })
      } else if (this.items.length === 1) {
        Column() {
          HomeCarouselCard({ artworkUrl: this.items[0].artworkUrl, title: this.items[0].title,
            subtitle: this.items[0].subtitle, viewportWidth: this.viewportWidth,
            onOpen: () => this.onOpen(this.items[0].id), onArtworkError: (url: string) => this.onArtworkError(url) })
            .width(HomeCarouselLayout.cardWidth(this.viewportWidth))
        }.height(HomeCarouselLayout.stageHeight(this.viewportWidth)).justifyContent(FlexAlign.Center)
      }
      if (this.items.length > 0) {
        Stack() {
          ForEach(this.items, (item: HomeCarouselItem, index: number) => {
            this.Caption(item, index)
          }, (item: HomeCarouselItem) => String(this.version) + ':caption:' + item.id)
        }.width(HomeCarouselLayout.stageWidth(this.viewportWidth)).height(HomeCarouselLayout.CAPTION_HEIGHT)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      }
      if (this.items.length > 1) {
        Row() {
          ForEach(this.items, (item: HomeCarouselItem, index: number) => {
            Button({ type: ButtonType.Normal }) {
              Row().width(8).height(4).borderRadius(2)
                .backgroundColor($r('app.color.text_primary'))
                .scale({ x: 1 + this.indicatorWeight(index) * 1.5, y: 1 })
                .opacity(0.28 + this.indicatorWeight(index) * 0.72)
            }.width(32).height(32).padding(0).backgroundColor(Color.Transparent)
              .accessibilityText(item.title).onClick(() => this.selectItem(index))
          }, (item: HomeCarouselItem) => item.id)
        }.height(32)
      }
    }.width('100%').padding({ top: this.topInset + 12, bottom: 4 })
      .alignItems(HorizontalAlign.Center).clip(true)
      .onVisibleAreaChange([0, 0.01], (isVisible: boolean, ratio: number) => this.setCarouselVisibility(isVisible && ratio > 0))
  }

  @Builder
  private Caption(item: HomeCarouselItem, index: number): void {
    Column({ space: 4 }) {
      Text(item.title).fontSize(20).fontWeight(FontWeight.Bold).lineHeight(26)
        .fontColor($r('app.color.text_primary')).width('100%').height(52).textAlign(TextAlign.Center)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(this.captionWeight(index))
        .translate({ y: HomeCarouselMotion.captionOffset(this.itemPosition(index)) }).renderGroup(true)
      Text(item.subtitle).fontSize(13).lineHeight(18)
        .fontColor($r('app.color.home_carousel_subtitle')).width('100%').height(18).textAlign(TextAlign.Center)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(HomeCarouselMotion.subtitleWeight(this.itemPosition(index)))
        .translate({ y: HomeCarouselMotion.captionOffset(this.itemPosition(index)) * 1.25 }).renderGroup(true)
    }.width('100%').height(HomeCarouselLayout.CAPTION_HEIGHT).padding({ left: 24, right: 24 })
  }
}

/** onIdle runs after the frame's UI updates, unlike a timer or onFrame at render start. */
class HomeCarouselTapFrame extends FrameCallback {
  private start: () => void
  constructor(start: () => void) { super(); this.start = start }
  onIdle(_timeLeftInNano: number): void { this.start() }
}
