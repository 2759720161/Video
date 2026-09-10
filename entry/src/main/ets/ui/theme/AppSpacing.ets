/** V3 统一空间节奏，单位为 vp。 */
export class AppSpacing {
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 16
  static readonly LG: number = 24
  static readonly XL: number = 32
  static readonly XXL: number = 40

  static readonly PAGE_PHONE: number = 16
  static readonly PAGE_TABLET: number = 24
  static readonly PAGE_WIDE: number = 32
  static readonly SECTION: number = 32
  static readonly SECTION_COMPACT: number = 24

  // Compatibility aliases for existing components. New components should use
  // the semantic XS/SM/MD/LG/XL tokens above.
  static readonly PAGE: number = AppSpacing.PAGE_PHONE
  static readonly CARD: number = 12
  static readonly CARD_CONTENT: number = AppSpacing.MD
  static readonly SMALL: number = AppSpacing.SM
  static readonly TINY: number = AppSpacing.XS
}
