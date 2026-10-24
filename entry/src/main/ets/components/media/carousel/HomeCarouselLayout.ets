export class HomeCarouselLayout {
  static readonly GAP: number = 20
  static readonly CAPTION_HEIGHT: number = 74
  static readonly STAGE_PADDING: number = 16

  static width(value: number): number {
    return Number.isFinite(value) && value >= 240 ? value : 360
  }

  static stageWidth(width: number): number {
    return Math.min(720, HomeCarouselLayout.width(width))
  }

  static cardWidth(width: number): number {
    return Math.max(144, Math.min(260, HomeCarouselLayout.stageWidth(width) * 0.54))
  }

  /** RotateOptions.perspective is px; callers convert this viewport-relative vp distance. */
  static perspectiveVp(width: number): number {
    return HomeCarouselLayout.cardWidth(width) * 2.8
  }

  static margin(width: number): number {
    return (HomeCarouselLayout.stageWidth(width) - HomeCarouselLayout.cardWidth(width)) / 2 - HomeCarouselLayout.GAP
  }

  static imageHeight(width: number): number {
    return Math.round(HomeCarouselLayout.cardWidth(width) * 3 / 2)
  }

  static cardHeight(width: number): number {
    return HomeCarouselLayout.imageHeight(width)
  }

  static artworkRatio(width: number, height: number): number {
    const ratio = width / height
    return width > 0 && height > 0 && Number.isFinite(ratio) && ratio > 0 ? ratio : 2 / 3
  }

  static artworkWidth(width: number, ratio: number): number {
    return Math.min(HomeCarouselLayout.cardWidth(width),
      HomeCarouselLayout.imageHeight(width) * HomeCarouselLayout.artworkRatio(ratio, 1))
  }

  static artworkHeight(width: number, ratio: number): number {
    return Math.min(HomeCarouselLayout.imageHeight(width),
      HomeCarouselLayout.cardWidth(width) / HomeCarouselLayout.artworkRatio(ratio, 1))
  }

  static artworkRadius(width: number, ratio: number): number {
    return Math.min(16, HomeCarouselLayout.artworkWidth(width, ratio) / 2,
      HomeCarouselLayout.artworkHeight(width, ratio) / 2)
  }

  static stageHeight(width: number): number {
    return HomeCarouselLayout.cardHeight(width) + HomeCarouselLayout.STAGE_PADDING * 2
  }
}
