import { HomeCarouselLayout } from './HomeCarouselLayout'
import { HomeCarouselMotion } from './HomeCarouselMotion'

/** Column-major Txy * P * Tz * Ry * S. Translation and camera distance are physical pixels. */
export class HomeCarouselProjection {
  static matrixValues(position: number, viewportWidth: number, pixelsPerVp: number): number[] {
    const unit = Number.isFinite(pixelsPerVp) && pixelsPerVp > 0 ? pixelsPerVp : 1
    const width = HomeCarouselLayout.cardWidth(viewportWidth)
    const perspective = HomeCarouselLayout.perspectiveVp(viewportWidth) * unit
    const angle = HomeCarouselMotion.angle(position) * Math.PI / 180
    const scale = HomeCarouselMotion.scale(position)
    const sine = Math.sin(angle)
    const cosine = Math.cos(angle)
    const x = HomeCarouselMotion.offsetX(position, width, HomeCarouselLayout.GAP) * unit
    const y = HomeCarouselMotion.offsetY(position) * unit
    const z = HomeCarouselMotion.offsetZ(position) * unit
    const q = scale * sine / perspective
    const r = -cosine / perspective
    const w = 1 - z / perspective
    return [scale * cosine + x * q, y * q, -scale * sine, q,
      0, scale, 0, 0,
      sine + x * r, y * r, cosine, r,
      x * w, y * w, z, w]
  }
}
