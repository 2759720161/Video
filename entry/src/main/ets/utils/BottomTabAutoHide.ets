export const PREFS_KEY_BOTTOM_TAB_AUTO_HIDE: string = 'bottomTabAutoHide'
export const PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION: string = 'bottomTabShowAnimation'
export const BOTTOM_TAB_ANIMATION_TOKEN_KEY: string = 'bottomTabAnimationToken'
export const BOTTOM_TAB_ANIMATION_HIDDEN_KEY: string = 'bottomTabAnimationHidden'
export const BOTTOM_TAB_AUTO_HIDE_DEFAULT: boolean = false
export const BOTTOM_TAB_SHOW_ANIMATION_DEFAULT: boolean = true
export const BOTTOM_TAB_HIDE_EXTRA_DISTANCE: number = 18
export const BOTTOM_TAB_BAR_HEIGHT: number = 66
export const BOTTOM_TAB_BAR_BOTTOM_MARGIN: number = 24
export const BOTTOM_TAB_SNAP_THRESHOLD_RATIO: number = 0.35
export const BOTTOM_TAB_SCROLL_DELTA_THRESHOLD: number = 1.5
export const BOTTOM_TAB_OPACITY_MIN: number = 0.4
export const BOTTOM_TAB_OPACITY_FADE_START_RATIO: number = 0.3

export function clampBottomTabOffset(value: number, maxValue: number): number {
  if (value < 0) {
    return 0
  }
  if (value > maxValue) {
    return maxValue
  }
  return value
}

export function resolveBottomTabOffset(
  currentScrollY: number,
  lastScrollY: number,
  currentOffset: number,
  maxOffset: number
): number {
  if (currentScrollY <= 0) {
    return 0
  }
  const delta = currentScrollY - lastScrollY
  if (Math.abs(delta) < BOTTOM_TAB_SCROLL_DELTA_THRESHOLD) {
    return currentOffset
  }
  return clampBottomTabOffset(currentOffset + delta, maxOffset)
}

export function getBottomTabHideDistance(bottomSafeHeight: number): number {
  return bottomSafeHeight + BOTTOM_TAB_BAR_HEIGHT + BOTTOM_TAB_BAR_BOTTOM_MARGIN + BOTTOM_TAB_HIDE_EXTRA_DISTANCE
}

export function resolveBottomTabOffsetByDelta(deltaY: number, currentOffset: number, maxOffset: number): number {
  if (Math.abs(deltaY) < BOTTOM_TAB_SCROLL_DELTA_THRESHOLD) {
    return currentOffset
  }
  return clampBottomTabOffset(currentOffset + deltaY, maxOffset)
}

export function resolveBottomTabSnapTarget(currentOffset: number, maxOffset: number): number {
  if (maxOffset <= 0) {
    return 0
  }
  return currentOffset >= maxOffset * BOTTOM_TAB_SNAP_THRESHOLD_RATIO ? maxOffset : 0
}

export function resolveBottomTabOpacity(currentOffset: number, maxOffset: number): number {
  if (maxOffset <= 0 || currentOffset <= 0) {
    return 1
  }
  const fadeStart = maxOffset * BOTTOM_TAB_OPACITY_FADE_START_RATIO
  if (currentOffset <= fadeStart) {
    return 1
  }
  const progress = (currentOffset - fadeStart) / (maxOffset - fadeStart)
  return 1 - progress * (1 - BOTTOM_TAB_OPACITY_MIN)
}

export function requestBottomTabAnimation(hidden: boolean): void {
  const currentHidden = AppStorage.get<boolean>(BOTTOM_TAB_ANIMATION_HIDDEN_KEY)
  if (currentHidden === hidden) {
    return
  }
  AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_HIDDEN_KEY, hidden)
  const token = Date.now() * (hidden ? 1 : -1)
  AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_TOKEN_KEY, token)
}
