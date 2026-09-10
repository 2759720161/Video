/** Shared media geometry and artwork fallback semantics. */
export class AppMediaStyle {
  static readonly POSTER_ASPECT_RATIO: number = 2 / 3
  static readonly LANDSCAPE_ASPECT_RATIO: number = 16 / 9
  static readonly POSTER_RADIUS: number = 12
  static readonly LANDSCAPE_RADIUS: number = 16
  static readonly HERO_RADIUS: number = 24

  static landscapeHeight(widthVp: number): number {
    if (!Number.isFinite(widthVp) || widthVp <= 0) return 106
    return Math.round(widthVp / AppMediaStyle.LANDSCAPE_ASPECT_RATIO)
  }

  static posterHeight(widthVp: number): number {
    if (!Number.isFinite(widthVp) || widthVp <= 0) return 186
    return Math.round(widthVp / AppMediaStyle.POSTER_ASPECT_RATIO)
  }
}
