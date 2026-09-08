/** API 24 compatibility helpers. API 26 immersive material is unavailable here. */
export const PREFS_KEY_API26_MATERIAL_STYLE: string = 'api26MaterialStyle'
export const API26_MATERIAL_STYLE_ULTRA_THIN: string = 'ultra_thin'
export const API26_MATERIAL_STYLE_THIN: string = 'thin'
export const API26_MATERIAL_STYLE_REGULAR: string = 'regular'
export const API26_MATERIAL_STYLE_THICK: string = 'thick'
export const API26_MATERIAL_STYLE_ULTRA_THICK: string = 'ultra_thick'
export const API26_MATERIAL_STYLE_DEFAULT: string = API26_MATERIAL_STYLE_REGULAR

export function isImmersiveMaterialSupported(): boolean { return false }

export function normalizeApi26MaterialStyle(style: string): string {
  if (style === API26_MATERIAL_STYLE_ULTRA_THIN || style === API26_MATERIAL_STYLE_THIN ||
    style === API26_MATERIAL_STYLE_REGULAR || style === API26_MATERIAL_STYLE_THICK ||
    style === API26_MATERIAL_STYLE_ULTRA_THICK) {
    return style
  }
  return API26_MATERIAL_STYLE_DEFAULT
}

export function getApi26MaterialStyleStorageValue(): string {
  return normalizeApi26MaterialStyle(AppStorage.get<string>(PREFS_KEY_API26_MATERIAL_STYLE) ?? API26_MATERIAL_STYLE_DEFAULT)
}

export function getApi26MaterialStyleLabel(style: string): string {
  switch (normalizeApi26MaterialStyle(style)) {
    case API26_MATERIAL_STYLE_ULTRA_THIN: return '超薄'
    case API26_MATERIAL_STYLE_THIN: return '薄'
    case API26_MATERIAL_STYLE_THICK: return '厚'
    case API26_MATERIAL_STYLE_ULTRA_THICK: return '超厚'
    default: return '标准'
  }
}
