/** Window size classes used by V3 responsive layouts. */
export enum ResponsiveSizeClass {
  COMPACT = 'compact',
  MEDIUM = 'medium',
  EXPANDED = 'expanded',
  LARGE = 'large'
}

export class ResponsiveSizeClassResolver {
  static resolve(widthVp: number): ResponsiveSizeClass {
    if (widthVp >= 1200) return ResponsiveSizeClass.LARGE
    if (widthVp >= 840) return ResponsiveSizeClass.EXPANDED
    if (widthVp >= 600) return ResponsiveSizeClass.MEDIUM
    return ResponsiveSizeClass.COMPACT
  }

  static columns(widthVp: number): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(widthVp)
    switch (sizeClass) {
      case ResponsiveSizeClass.LARGE: return 5
      case ResponsiveSizeClass.EXPANDED: return 4
      case ResponsiveSizeClass.MEDIUM: return 3
      default: return 2
    }
  }

  static pagePadding(widthVp: number): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(widthVp)
    if (sizeClass === ResponsiveSizeClass.LARGE) return 32
    if (sizeClass === ResponsiveSizeClass.EXPANDED || sizeClass === ResponsiveSizeClass.MEDIUM) return 24
    return 16
  }

  /** Rail card widths grow with the window so tablet and desktop do not keep phone-sized media. */
  static posterWidth(widthVp: number): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(widthVp)
    if (sizeClass === ResponsiveSizeClass.LARGE) return 160
    if (sizeClass === ResponsiveSizeClass.EXPANDED) return 152
    if (sizeClass === ResponsiveSizeClass.MEDIUM) return 144
    return 124
  }

  static landscapeWidth(widthVp: number): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(widthVp)
    if (sizeClass === ResponsiveSizeClass.LARGE) return 240
    if (sizeClass === ResponsiveSizeClass.EXPANDED) return 232
    if (sizeClass === ResponsiveSizeClass.MEDIUM) return 220
    return 188
  }

  static shortcutWidth(widthVp: number): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(widthVp)
    if (sizeClass === ResponsiveSizeClass.LARGE) return 168
    if (sizeClass === ResponsiveSizeClass.EXPANDED) return 160
    if (sizeClass === ResponsiveSizeClass.MEDIUM) return 152
    return 128
  }

  static shortcutHeight(widthVp: number): number {
    const sizeClass = ResponsiveSizeClassResolver.resolve(widthVp)
    if (sizeClass === ResponsiveSizeClass.LARGE) return 96
    if (sizeClass === ResponsiveSizeClass.EXPANDED || sizeClass === ResponsiveSizeClass.MEDIUM) return 88
    return 80
  }
}
