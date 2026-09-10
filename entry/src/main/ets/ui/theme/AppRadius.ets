/** V3 语义化圆角 Token，单位为 vp。 */
export class AppRadius {
  static readonly MEDIA_POSTER: number = 12
  static readonly MEDIA_LANDSCAPE: number = 16
  static readonly NAVIGATION: number = 16
  static readonly SURFACE: number = 20
  static readonly HERO: number = 24
  static readonly SHEET: number = 28
  static readonly BUTTON: number = 20
  static readonly SMALL_BUTTON: number = 12

  // Compatibility aliases for the existing V2 component API.
  static readonly SMALL: number = AppRadius.SMALL_BUTTON
  static readonly CARD: number = AppRadius.MEDIA_POSTER
  static readonly LARGE_CARD: number = AppRadius.MEDIA_LANDSCAPE
}
