import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'

export const PREFS_KEY_API26_MATERIAL_STYLE: string = 'api26MaterialStyle'
export const API26_MATERIAL_STYLE_ULTRA_THIN: string = 'ultra_thin'
export const API26_MATERIAL_STYLE_THIN: string = 'thin'
export const API26_MATERIAL_STYLE_REGULAR: string = 'regular'
export const API26_MATERIAL_STYLE_THICK: string = 'thick'
export const API26_MATERIAL_STYLE_ULTRA_THICK: string = 'ultra_thick'
export const API26_MATERIAL_STYLE_DEFAULT: string = API26_MATERIAL_STYLE_REGULAR

// ImmersiveStyle is exposed as a type in some API 26 runtimes, but its
// runtime enum object is not available on all compatible devices.
const IMMERSIVE_STYLE_THIN: uiMaterial.ImmersiveStyle = 1 as uiMaterial.ImmersiveStyle
const IMMERSIVE_STYLE_REGULAR: uiMaterial.ImmersiveStyle = 2 as uiMaterial.ImmersiveStyle
const IMMERSIVE_STYLE_THICK: uiMaterial.ImmersiveStyle = 3 as uiMaterial.ImmersiveStyle
const IMMERSIVE_STYLE_ULTRA_THICK: uiMaterial.ImmersiveStyle = 4 as uiMaterial.ImmersiveStyle
const IMMERSIVE_STYLE_ULTRA_THIN: uiMaterial.ImmersiveStyle = 0 as uiMaterial.ImmersiveStyle

/**
 * API 26 immersive material for ordinary ArkUI controls.
 * Existing HDS controls use systemMaterialEffect and keep their own pipeline.
 */
export function createImmersiveMaterial(
  style: uiMaterial.ImmersiveStyle,
  interactive: boolean = true
): uiMaterial.ImmersiveMaterial | undefined {
  if (!isImmersiveMaterialSupported()) {
    return undefined
  }
  try {
    const configuredStyle = resolveConfiguredStyle(style)
    return new uiMaterial.ImmersiveMaterial({
      style: configuredStyle,
      applyShadow: false,
      interactive: interactive
    })
  } catch (_) {
    return undefined
  }
}

export function createThinImmersiveMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return createImmersiveMaterial(IMMERSIVE_STYLE_THIN)
}

/** Creates a material using the current setting-page material level. */
export function createConfiguredImmersiveMaterial(
  interactive: boolean = true
): uiMaterial.ImmersiveMaterial | undefined {
  return createImmersiveMaterial(IMMERSIVE_STYLE_REGULAR, interactive)
}

export function createRegularImmersiveMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return createImmersiveMaterial(IMMERSIVE_STYLE_REGULAR)
}

export function createThickImmersiveMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return createImmersiveMaterial(IMMERSIVE_STYLE_THICK)
}

export function isImmersiveMaterialSupported(): boolean {
  try {
    return deviceInfo.apiAvailable('26.0.0')
  } catch (_) {
    return false
  }
}

export function normalizeApi26MaterialStyle(style: string): string {
  if (style === API26_MATERIAL_STYLE_ULTRA_THIN ||
    style === API26_MATERIAL_STYLE_THIN ||
    style === API26_MATERIAL_STYLE_REGULAR ||
    style === API26_MATERIAL_STYLE_THICK ||
    style === API26_MATERIAL_STYLE_ULTRA_THICK) {
    return style
  }
  return API26_MATERIAL_STYLE_DEFAULT
}

export function getApi26MaterialStyleStorageValue(): string {
  return normalizeApi26MaterialStyle(
    AppStorage.get<string>(PREFS_KEY_API26_MATERIAL_STYLE) ?? API26_MATERIAL_STYLE_DEFAULT
  )
}

export function getApi26MaterialStyleLabel(style: string): string {
  switch (normalizeApi26MaterialStyle(style)) {
    case API26_MATERIAL_STYLE_ULTRA_THIN:
      return '超薄'
    case API26_MATERIAL_STYLE_THIN:
      return '薄'
    case API26_MATERIAL_STYLE_THICK:
      return '厚'
    case API26_MATERIAL_STYLE_ULTRA_THICK:
      return '超厚'
    default:
      return '标准'
  }
}

function resolveConfiguredStyle(fallback: uiMaterial.ImmersiveStyle): uiMaterial.ImmersiveStyle {
  switch (getApi26MaterialStyleStorageValue()) {
    case API26_MATERIAL_STYLE_ULTRA_THIN:
      return IMMERSIVE_STYLE_ULTRA_THIN
    case API26_MATERIAL_STYLE_THIN:
      return IMMERSIVE_STYLE_THIN
    case API26_MATERIAL_STYLE_THICK:
      return IMMERSIVE_STYLE_THICK
    case API26_MATERIAL_STYLE_ULTRA_THICK:
      return IMMERSIVE_STYLE_ULTRA_THICK
    case API26_MATERIAL_STYLE_REGULAR:
      return IMMERSIVE_STYLE_REGULAR
    default:
      return fallback
  }
}
