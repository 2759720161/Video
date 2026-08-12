export const PREFS_KEY_SUBTITLE_ENABLED: string = 'subtitleEnabled'
export const PREFS_KEY_SUBTITLE_FONT_SIZE: string = 'subtitleFontSize'
export const PREFS_KEY_SUBTITLE_FONT_BOLD: string = 'subtitleFontBold'
export const PREFS_KEY_SUBTITLE_FONT_COLOR: string = 'subtitleFontColor'
export const PREFS_KEY_SUBTITLE_RECENT_COLORS: string = 'subtitleRecentColors'
export const PREFS_KEY_SUBTITLE_BOTTOM_OFFSET: string = 'subtitleBottomOffset'
export const PREFS_KEY_SUBTITLE_OUTLINE_ENABLED: string = 'subtitleOutlineEnabled'
export const PREFS_KEY_SUBTITLE_TIME_OFFSET_MS: string = 'subtitleTimeOffsetMs'

export const SUBTITLE_ENABLED_DEFAULT: boolean = true
export const SUBTITLE_FONT_SIZE_DEFAULT: number = 18
export const SUBTITLE_FONT_BOLD_DEFAULT: boolean = false
export const SUBTITLE_FONT_COLOR_DEFAULT: string = '#FFFFFFFF'
export const SUBTITLE_BOTTOM_OFFSET_DEFAULT: number = 0
export const SUBTITLE_OUTLINE_ENABLED_DEFAULT: boolean = true
export const SUBTITLE_TIME_OFFSET_MS_DEFAULT: number = 0

const SUPPORTED_FONT_SIZES: number[] = [16, 18, 20, 22, 24]
const SUPPORTED_BOTTOM_OFFSETS: number[] = [0, 32, 64, 96]
const SUPPORTED_TIME_OFFSETS: number[] = [-1000, -500, 0, 500, 1000]

function nearestSupported(value: number, supported: number[], fallback: number): number {
  let closest: number = fallback
  let distance: number = Number.MAX_VALUE
  for (let index = 0; index < supported.length; index++) {
    const nextDistance = Math.abs(value - supported[index])
    if (nextDistance < distance) {
      closest = supported[index]
      distance = nextDistance
    }
  }
  return closest
}

export function normalizeSubtitleFontSize(value: number): number {
  return nearestSupported(value, SUPPORTED_FONT_SIZES, SUBTITLE_FONT_SIZE_DEFAULT)
}

export function normalizeSubtitleBottomOffset(value: number): number {
  return nearestSupported(value, SUPPORTED_BOTTOM_OFFSETS, SUBTITLE_BOTTOM_OFFSET_DEFAULT)
}

export function normalizeSubtitleTimeOffsetMs(value: number): number {
  return nearestSupported(value, SUPPORTED_TIME_OFFSETS, SUBTITLE_TIME_OFFSET_MS_DEFAULT)
}
