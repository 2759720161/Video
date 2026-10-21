import {
  HdsNavigationTitleBarOptions,
  TitleBarStyleOptions,
  ScrollEffectType,
  SystemMaterialParams,
  hdsMaterial
} from '@kit.UIDesignKit'
import { LengthMetrics, uiMaterial } from '@kit.ArkUI'
import { ResponsiveSizeClass, ResponsiveSizeClassResolver } from '../ui/theme/ResponsiveSizeClass'

export const DEFAULT_TOP_SAFE_HEIGHT: number = 36
export const MINI_TITLE_BAR_CONTENT_HEIGHT: number = 72
export const HDS_FLOATING_TAB_CONTENT_SPACER: number = 96
export const TIMELINE_WEEKDAY_BAR_HEIGHT: number = 56
export const PREFS_KEY_HDS_MATERIAL_LEVEL: string = 'hdsMaterialLevel'
export const PREFS_KEY_IMMERSIVE_MATERIAL_STYLE: string = 'immersiveMaterialStyle'
export const HDS_MATERIAL_LEVEL_EXQUISITE: string = 'exquisite'
export const HDS_MATERIAL_LEVEL_GENTLE: string = 'gentle'
export const HDS_MATERIAL_LEVEL_SMOOTH: string = 'smooth'
export const HDS_MATERIAL_LEVEL_ADAPTIVE: string = 'adaptive'
export const HDS_MATERIAL_LEVEL_DEFAULT: string = HDS_MATERIAL_LEVEL_EXQUISITE
export const IMMERSIVE_STYLE_ULTRA_THIN: string = 'ultraThin'
export const IMMERSIVE_STYLE_THIN: string = 'thin'
export const IMMERSIVE_STYLE_REGULAR: string = 'regular'
export const IMMERSIVE_STYLE_THICK: string = 'thick'
export const IMMERSIVE_STYLE_ULTRA_THICK: string = 'ultraThick'
export const IMMERSIVE_STYLE_DEFAULT: string = IMMERSIVE_STYLE_REGULAR

export function getEffectiveTopSafeHeight(topSafeHeight: number): number {
  return topSafeHeight > 0 ? topSafeHeight : DEFAULT_TOP_SAFE_HEIGHT
}

export function getTopSpacerHeight(topSafeHeight: number): number {
  return getEffectiveTopSafeHeight(topSafeHeight) + MINI_TITLE_BAR_CONTENT_HEIGHT
}

export function getBottomSpacerHeight(bottomSafeHeight: number): number {
  return bottomSafeHeight + HDS_FLOATING_TAB_CONTENT_SPACER
}

export function buildAdaptiveMaterialEffect(level: string = getHdsMaterialLevelStorageValue()): SystemMaterialParams {
  let immersiveSupported: boolean = false
  try {
    const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
    immersiveSupported = materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0
  } catch (_) {
    immersiveSupported = false
  }
  return {
    materialType: immersiveSupported ? hdsMaterial.MaterialType.IMMERSIVE :
      hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: immersiveSupported ? resolveHdsMaterialLevel(level) :
      hdsMaterial.MaterialLevel.ADAPTIVE
  }
}

export function getHdsMaterialLevelStorageValue(): string {
  const level = AppStorage.get<string>(PREFS_KEY_HDS_MATERIAL_LEVEL)
  if (level === HDS_MATERIAL_LEVEL_GENTLE ||
    level === HDS_MATERIAL_LEVEL_SMOOTH ||
    level === HDS_MATERIAL_LEVEL_ADAPTIVE ||
    level === HDS_MATERIAL_LEVEL_EXQUISITE) {
    return level
  }
  return HDS_MATERIAL_LEVEL_DEFAULT
}

export function resolveHdsMaterialLevel(level: string): hdsMaterial.MaterialLevel {
  if (level === HDS_MATERIAL_LEVEL_GENTLE) {
    return hdsMaterial.MaterialLevel.GENTLE
  }
  if (level === HDS_MATERIAL_LEVEL_SMOOTH) {
    return hdsMaterial.MaterialLevel.SMOOTH
  }
  if (level === HDS_MATERIAL_LEVEL_ADAPTIVE) {
    return hdsMaterial.MaterialLevel.ADAPTIVE
  }
  return hdsMaterial.MaterialLevel.EXQUISITE
}

export function getHdsMaterialLevelLabel(level: string): string {
  if (level === HDS_MATERIAL_LEVEL_GENTLE) {
    return '柔和'
  }
  if (level === HDS_MATERIAL_LEVEL_SMOOTH) {
    return '平滑'
  }
  if (level === HDS_MATERIAL_LEVEL_ADAPTIVE) {
    return '自适应'
  }
  return '精致'
}

export function getImmersiveMaterialStyleStorageValue(): string {
  const style = AppStorage.get<string>(PREFS_KEY_IMMERSIVE_MATERIAL_STYLE)
  if (style === IMMERSIVE_STYLE_ULTRA_THIN || style === IMMERSIVE_STYLE_THIN ||
    style === IMMERSIVE_STYLE_REGULAR || style === IMMERSIVE_STYLE_THICK ||
    style === IMMERSIVE_STYLE_ULTRA_THICK) {
    return style
  }
  return IMMERSIVE_STYLE_DEFAULT
}

export function resolveImmersiveMaterialStyle(style: string): uiMaterial.ImmersiveStyle {
  if (style === IMMERSIVE_STYLE_ULTRA_THIN) return uiMaterial.ImmersiveStyle.ULTRA_THIN
  if (style === IMMERSIVE_STYLE_THIN) return uiMaterial.ImmersiveStyle.THIN
  if (style === IMMERSIVE_STYLE_THICK) return uiMaterial.ImmersiveStyle.THICK
  if (style === IMMERSIVE_STYLE_ULTRA_THICK) return uiMaterial.ImmersiveStyle.ULTRA_THICK
  return uiMaterial.ImmersiveStyle.REGULAR
}

export function resolveImmersiveBlurStyle(style: string): BlurStyle {
  if (style === IMMERSIVE_STYLE_ULTRA_THIN) return BlurStyle.COMPONENT_ULTRA_THIN
  if (style === IMMERSIVE_STYLE_THIN) return BlurStyle.COMPONENT_THIN
  if (style === IMMERSIVE_STYLE_THICK) return BlurStyle.COMPONENT_THICK
  if (style === IMMERSIVE_STYLE_ULTRA_THICK) return BlurStyle.COMPONENT_ULTRA_THICK
  return BlurStyle.COMPONENT_REGULAR
}

export function getImmersiveMaterialStyleLabel(style: string): string {
  if (style === IMMERSIVE_STYLE_ULTRA_THIN) return '超薄'
  if (style === IMMERSIVE_STYLE_THIN) return '薄'
  if (style === IMMERSIVE_STYLE_THICK) return '厚'
  if (style === IMMERSIVE_STYLE_ULTRA_THICK) return '超厚'
  return '常规'
}

export function buildImmersiveTitleBarStyle(level: string = getHdsMaterialLevelStorageValue()): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(36),
      enableRefreshOffsetChange: false
    },
    originalStyle: {
      backgroundStyle: {
        backgroundColor: Color.Transparent,
        blurRadius: 28
      },
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('app.color.text_primary'),
          subTitleColor: $r('app.color.text_secondary')
        },
        menuStyle: {
          // 保持半透明，让系统材料效果能够透出页面内容与环境光。
          backgroundColor: $r('app.color.titlebar_button_surface'),
          iconColor: $r('app.color.text_primary')
        },
        backIconStyle: {
          backgroundColor: $r('app.color.titlebar_button_surface'),
          iconColor: $r('app.color.text_primary')
        },
        dividerStyle: {
          dividerColor: Color.Transparent
        }
      }
    },
    scrollEffectStyle: {
      backgroundStyle: {
        backgroundColor: Color.Transparent,
        blurRadius: 28
      },
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('app.color.text_primary'),
          subTitleColor: $r('app.color.text_secondary')
        },
        menuStyle: {
          backgroundColor: $r('app.color.titlebar_button_surface'),
          iconColor: $r('app.color.text_primary')
        },
        backIconStyle: {
          backgroundColor: $r('app.color.titlebar_button_surface'),
          iconColor: $r('app.color.text_primary')
        },
        dividerStyle: {
          dividerColor: Color.Transparent
        }
      }
    },
    thermoCtrl: true,
    systemMaterialEffect: buildAdaptiveMaterialEffect(level)
  }
}

export function buildTitleBarOptions(title: string, level: string = getHdsMaterialLevelStorageValue()): HdsNavigationTitleBarOptions {
  return {
    style: buildImmersiveTitleBarStyle(level),
    content: {
      title: {
        mainTitle: title
      }
    },
    enableComponentSafeArea: false,
    avoidLayoutSafeArea: true
  }
}

/** Media artwork remains visible under the title bar until scrolling introduces the material layer. */
export function buildMediaDetailTitleBarOptions(title: string,
  level: string = getHdsMaterialLevelStorageValue()): HdsNavigationTitleBarOptions {
  const options: HdsNavigationTitleBarOptions = buildTitleBarOptions(title, level)
  if (options.style?.originalStyle?.backgroundStyle) {
    options.style.originalStyle.backgroundStyle.blurRadius = 0
  }
  if (options.style?.originalStyle?.contentStyle?.menuStyle) {
    options.style.originalStyle.contentStyle.menuStyle.backgroundColor = Color.Transparent
  }
  if (options.style?.originalStyle?.contentStyle?.backIconStyle) {
    options.style.originalStyle.contentStyle.backIconStyle.backgroundColor = Color.Transparent
  }
  return options
}

/** 首页大图沉浸时使用：首屏标题栏透明并叠在 artwork 上，滚动后回到材料背景。 */
export function buildHeroTitleBarStyle(level: string = getHdsMaterialLevelStorageValue()): TitleBarStyleOptions {
  const base: TitleBarStyleOptions = buildImmersiveTitleBarStyle(level)
  if (base.originalStyle?.backgroundStyle) {
    base.originalStyle.backgroundStyle.blurRadius = 0
  }
  if (base.originalStyle?.contentStyle?.titleStyle) {
    base.originalStyle.contentStyle.titleStyle.mainTitleColor = Color.White
    base.originalStyle.contentStyle.titleStyle.subTitleColor = '#E6FFFFFF'
  }
  if (base.originalStyle?.contentStyle?.menuStyle) {
    base.originalStyle.contentStyle.menuStyle.backgroundColor = '#66000000'
    base.originalStyle.contentStyle.menuStyle.iconColor = Color.White
  }
  if (base.originalStyle?.contentStyle?.backIconStyle) {
    base.originalStyle.contentStyle.backIconStyle.backgroundColor = '#66000000'
    base.originalStyle.contentStyle.backIconStyle.iconColor = Color.White
  }
  return base
}

export function buildTimelineTitleBarStyle(level: string = getHdsMaterialLevelStorageValue()): TitleBarStyleOptions {
  const base: TitleBarStyleOptions = buildImmersiveTitleBarStyle(level)
  if (base.originalStyle?.backgroundStyle) {
    base.originalStyle.backgroundStyle.maskExtraHeight = TIMELINE_WEEKDAY_BAR_HEIGHT
  }
  if (base.scrollEffectStyle?.backgroundStyle) {
    base.scrollEffectStyle.backgroundStyle.maskExtraHeight = TIMELINE_WEEKDAY_BAR_HEIGHT
  }
  return base
}

export function isTabletLayout(screenWidthVp: number): boolean {
  return ResponsiveSizeClassResolver.resolve(screenWidthVp) !== ResponsiveSizeClass.COMPACT
}

export function isWideDetailLayout(screenWidthVp: number): boolean {
  const sizeClass = ResponsiveSizeClassResolver.resolve(screenWidthVp)
  return sizeClass === ResponsiveSizeClass.EXPANDED || sizeClass === ResponsiveSizeClass.LARGE
}

export function getSideBarWidth(screenWidthVp: number): number {
  const sizeClass = ResponsiveSizeClassResolver.resolve(screenWidthVp)
  if (sizeClass === ResponsiveSizeClass.LARGE) return 320
  if (sizeClass === ResponsiveSizeClass.EXPANDED) return 280
  return 240
}

export function getContentMaxWidth(screenWidthVp: number): number {
  const sizeClass = ResponsiveSizeClassResolver.resolve(screenWidthVp)
  if (sizeClass === ResponsiveSizeClass.LARGE) return 1000
  if (sizeClass === ResponsiveSizeClass.EXPANDED) return 840
  if (sizeClass === ResponsiveSizeClass.MEDIUM) return 720
  return 0
}

/** Media pages may use a wider canvas for rails and hero content. */
export function getMediaContentMaxWidth(screenWidthVp: number): number {
  const sizeClass = ResponsiveSizeClassResolver.resolve(screenWidthVp)
  if (sizeClass === ResponsiveSizeClass.LARGE) return 1320
  if (sizeClass === ResponsiveSizeClass.EXPANDED) return 1120
  return 0
}

/** Management pages stay denser than media pages on large windows. */
export function getManagementContentMaxWidth(screenWidthVp: number): number {
  const sizeClass = ResponsiveSizeClassResolver.resolve(screenWidthVp)
  if (sizeClass === ResponsiveSizeClass.LARGE || sizeClass === ResponsiveSizeClass.EXPANDED) return 840
  if (sizeClass === ResponsiveSizeClass.MEDIUM) return 720
  return 0
}

/** Detail pages reserve room for the poster and information columns. */
export function getDetailContentMaxWidth(screenWidthVp: number): number {
  const sizeClass = ResponsiveSizeClassResolver.resolve(screenWidthVp)
  if (sizeClass === ResponsiveSizeClass.LARGE) return 1200
  if (sizeClass === ResponsiveSizeClass.EXPANDED) return 1120
  return 0
}
