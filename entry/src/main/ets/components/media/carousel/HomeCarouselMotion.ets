/** Swiper keeps its native drag physics; only render properties follow the scroll position. */
export class HomeCarouselMotion {
  static readonly INTERACTION_PAUSE_MS: number = 3000
  static readonly AUTO_DURATION_MS: number = 720
  static readonly DRAG_DURATION_MS: number = 420
  static readonly TAP_DURATION_MS: number = HomeCarouselMotion.AUTO_DURATION_MS
  static slotCount(count: number): number {
    if (!Number.isInteger(count) || count < 1) return 0
    // Swiper cannot report per-page scroll while the same page is visible at both edges.
    // Distinct render slots keep small catalogs loopable without duplicating provider data.
    return count === 1 ? 1 : Math.ceil(6 / count) * count
  }

  static itemIndex(slot: number, count: number): number {
    return count > 0 && Number.isFinite(slot) ? ((Math.trunc(slot) % count) + count) % count : 0
  }

  static anchor(index: number, count: number): number {
    return (HomeCarouselMotion.slotCount(count) > count ? count : 0) + HomeCarouselMotion.itemIndex(index, count)
  }

  static relative(slot: number, selected: number, count: number): number {
    if (count < 2 || !Number.isFinite(slot) || !Number.isFinite(selected)) return 0
    let value = ((slot - selected) % count + count) % count
    if (value > count / 2) value -= count
    return value
  }

  static centerFromSample(index: number, position: number, length: number, gap: number, count: number): number {
    if (!Number.isInteger(index) || index < 0 || index >= count || count < 2 || !Number.isFinite(position) ||
      !Number.isFinite(length) || length <= 0 || !Number.isFinite(gap) || gap < 0) return NaN
    // ArkUI reports startPos / itemLength; adjacent pages are itemLength + itemSpace apart.
    const center = index - position * length / (length + gap)
    return ((center % count) + count) % count
  }

  static position(value: number): number {
    return Number.isFinite(value) ? Math.max(-2, Math.min(2, value)) : 0
  }

  static eased(value: number): number {
    const progress = Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    // Zero first and second derivatives at both ends keep pose acceleration continuous.
    // This only shapes render properties; never ease the shared scroll/background clock again.
    return progress * progress * progress * (progress * (progress * 6 - 15) + 10)
  }

  static distance(position: number): number { return HomeCarouselMotion.eased(Math.abs(HomeCarouselMotion.position(position))) }
  static outerDistance(position: number): number { return HomeCarouselMotion.eased(Math.abs(HomeCarouselMotion.position(position)) - 1) }
  static poseDistance(position: number): number {
    const distance = HomeCarouselMotion.distance(position)
    return distance * (2 - distance)
  }

  /** Clear the two crossing faces before their paint order changes; no extra settling animation. */
  static handoff(position: number): number {
    const value = Math.min(1, Math.abs(HomeCarouselMotion.position(position)))
    const product = value * (1 - value)
    return 256 * product * product * product * product
  }

  static angle(position: number): number {
    const value = HomeCarouselMotion.position(position)
    return (value < 0 ? 1 : -1) * (40 * HomeCarouselMotion.poseDistance(value) + 6 * HomeCarouselMotion.outerDistance(value))
  }
  static scale(position: number): number {
    return 1 - 0.16 * HomeCarouselMotion.poseDistance(position) - 0.04 * HomeCarouselMotion.outerDistance(position)
  }
  static opacity(position: number): number {
    // Keep overlapping faces opaque. Only fade the remote slots outside the three-poster composition.
    return 1 - HomeCarouselMotion.outerDistance(position)
  }
  static shadeOpacity(position: number): number {
    return 0.28 * HomeCarouselMotion.poseDistance(position) + 0.08 * HomeCarouselMotion.outerDistance(position)
  }
  static offsetX(position: number, width: number, gap: number): number {
    const value = Number.isFinite(position) ? position : 0
    const direction = value < 0 ? -1 : 1
    // Native centers are p*(width+gap). Remove the gap and pull adjacent centers to +/-0.62 width.
    // The midpoint clearance is part of the same continuous scroll pose, never a second animation.
    return -value * gap - direction * width * (0.38 * HomeCarouselMotion.distance(value) +
      0.38 * HomeCarouselMotion.outerDistance(value) - 0.105 * HomeCarouselMotion.handoff(value))
  }
  static offsetY(position: number): number {
    return 12 * HomeCarouselMotion.poseDistance(position) + 2 * HomeCarouselMotion.outerDistance(position)
  }
  static offsetZ(position: number): number {
    return -40 * HomeCarouselMotion.poseDistance(position) - 24 * HomeCarouselMotion.outerDistance(position)
  }
  static depth(position: number): number { return Math.round(1000 * (2 - Math.abs(HomeCarouselMotion.position(position)))) }
  static focusWeight(position: number): number { return 1 - HomeCarouselMotion.distance(position) }
  static captionWeight(position: number): number {
    return 1 - HomeCarouselMotion.eased(Math.abs(HomeCarouselMotion.position(position)) / 0.58)
  }
  static subtitleWeight(position: number): number {
    return 1 - HomeCarouselMotion.eased(Math.abs(HomeCarouselMotion.position(position)) / 0.46)
  }
  static captionOffset(position: number): number {
    return (position < 0 ? -1 : 1) * HomeCarouselMotion.distance(position) * 6
  }

  static nearestSlot(index: number, selected: number, count: number): number {
    const slots = HomeCarouselMotion.slotCount(count)
    if (slots < 2) return 0
    let nearest = HomeCarouselMotion.itemIndex(index, count)
    for (let slot = nearest + count; slot < slots; slot += count) {
      if (Math.abs(HomeCarouselMotion.relative(slot, selected, slots)) <
        Math.abs(HomeCarouselMotion.relative(nearest, selected, slots))) nearest = slot
    }
    return nearest
  }
}
