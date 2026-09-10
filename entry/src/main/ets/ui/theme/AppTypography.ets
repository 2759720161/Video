/** V3 层级化字号 Token，单位为 fp。 */
export class AppTypography {
  static readonly HERO_TITLE: number = 30
  static readonly PAGE_TITLE: number = 26
  static readonly SECTION_TITLE: number = 20
  static readonly FEATURE_TITLE: number = 18
  static readonly BODY_LARGE: number = 16
  static readonly BODY: number = 14
  static readonly META: number = 13
  static readonly CAPTION: number = 12

  // Compatibility alias retained for card components that have not yet been
  // migrated to FEATURE_TITLE.
  static readonly CARD_TITLE: number = 14
}
