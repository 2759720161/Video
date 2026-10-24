export class HomeHeroToneSample {
  tone: string = ''
  blackShare: number = 0
  accentShare: number = 0
}

class HeroHueBucket {
  weight: number = 0
  red: number = 0
  green: number = 0
  blue: number = 0
}

/** Measure the entire thumbnail; a small bright patch must not replace a mostly dark poster. */
export class HomeHeroImageTone {
  static analyze(pixels: Uint8Array, premultiplied: boolean = false, opaque: boolean = false): HomeHeroToneSample {
    const result = new HomeHeroToneSample()
    if (pixels.length === 0 || pixels.length % 4 !== 0) return result
    const buckets: HeroHueBucket[] = []
    for (let i = 0; i < 12; i++) buckets.push(new HeroHueBucket())
    let weight = 0
    let red = 0
    let green = 0
    let blue = 0
    let black = 0
    for (let i = 0; i < pixels.length; i += 4) {
      const alpha = opaque ? 255 : pixels[i + 3]
      if (alpha === 0) continue
      const amount = alpha / 255
      const scale = premultiplied ? 255 / alpha : 1
      const r = Math.min(255, pixels[i] * scale)
      const g = Math.min(255, pixels[i + 1] * scale)
      const b = Math.min(255, pixels[i + 2] * scale)
      weight += amount; red += r * amount; green += g * amount; blue += b * amount
      const max = Math.max(r, g, b)
      const delta = max - Math.min(r, g, b)
      if (max < 48) black += amount
      if (delta < 24 || max < 48) continue
      const sector = max === r ? (g - b) / delta : (max === g ? (b - r) / delta + 2 : (r - g) / delta + 4)
      const hue = ((sector * 60) % 360 + 360) % 360
      const bucket = buckets[Math.floor(((hue + 15) % 360) / 30)]
      bucket.weight += amount; bucket.red += r * amount; bucket.green += g * amount; bucket.blue += b * amount
    }
    if (weight === 0) return result
    red /= weight; green /= weight; blue /= weight
    const ranked = buckets.sort((first: HeroHueBucket, second: HeroHueBucket) => second.weight - first.weight)
    const accent = ranked[0]
    const boost = Math.min(0.5, (accent.weight - ranked[1].weight) / weight)
    if (accent.weight > 0) {
      red = red * (1 - boost) + accent.red / accent.weight * boost
      green = green * (1 - boost) + accent.green / accent.weight * boost
      blue = blue * (1 - boost) + accent.blue / accent.weight * boost
    }
    result.blackShare = black / weight
    result.accentShare = accent.weight / weight
    // Keep a subtle hue on black-heavy artwork, while fully colored artwork retains its color.
    const chroma = 1 - result.blackShare * 0.8
    const gray = red * 0.2126 + green * 0.7152 + blue * 0.0722
    result.tone = '#' + HomeHeroImageTone.channel(gray + (red - gray) * chroma) +
      HomeHeroImageTone.channel(gray + (green - gray) * chroma) +
      HomeHeroImageTone.channel(gray + (blue - gray) * chroma)
    return result
  }

  private static channel(value: number): string {
    return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0')
  }
}
