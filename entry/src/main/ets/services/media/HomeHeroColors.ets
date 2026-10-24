/** Preserve the cover's chroma, with lightness bounds for the theme's normal text. */
export class HomeHeroColors {
  /** Separate nearby cover tones without changing their hue or the persisted source palette. */
  static distinguish(tones: string[]): string[] {
    const ordered = Array.from(new Set(tones.filter((tone: string) => /^#[0-9a-f]{6}$/i.test(tone))
      .map((tone: string) => tone.toLowerCase())))
    ordered.sort((first: string, second: string) =>
      HomeHeroColors.brightness(first) - HomeHeroColors.brightness(second) || first.localeCompare(second))
    const assigned: Map<string, string> = new Map()
    for (let i = 0; i < ordered.length; i++) {
      const tone = ordered[i]
      const peers = ordered.slice(0, i).filter((other: string) => HomeHeroColors.near(tone, other))
      let chosen = tone
      let best = HomeHeroColors.separation(chosen, peers, assigned)
      for (let step = 1; peers.length > 0 && best < 1 && step <= 12; step++) {
        const candidate = HomeHeroColors.blend(tone, '#ffffff', step * 0.05)
        const score = HomeHeroColors.separation(candidate, peers, assigned)
        if (score > best) { chosen = candidate; best = score }
      }
      assigned.set(tone, chosen)
    }
    return tones.map((tone: string) => assigned.get(tone.toLowerCase()) ?? '')
  }

  private static separation(tone: string, peers: string[], assigned: Map<string, string>): number {
    let score = 1
    for (let i = 0; i < peers.length; i++) {
      const other = assigned.get(peers[i]) ?? peers[i]
      score = Math.min(score,
        HomeHeroColors.distance(HomeHeroColors.surface(tone, 0xfff2f2f2),
          HomeHeroColors.surface(other, 0xfff2f2f2)) / (22 * 22),
        HomeHeroColors.distance(HomeHeroColors.surface(tone, 0xff121212),
          HomeHeroColors.surface(other, 0xff121212)) / (18 * 18))
    }
    return score
  }

  private static near(first: string, second: string): boolean {
    const a = HomeHeroColors.rgb(first)
    const b = HomeHeroColors.rgb(second)
    if (Math.max(...a) - Math.min(...a) < 24 || Math.max(...b) - Math.min(...b) < 24) return false
    const hue = Math.abs(HomeHeroColors.hue(a) - HomeHeroColors.hue(b))
    if (Math.min(hue, 360 - hue) > 10 || HomeHeroColors.distance(first, second) > 64 * 64) return false
    return HomeHeroColors.distance(HomeHeroColors.surface(first, 0xfff2f2f2),
      HomeHeroColors.surface(second, 0xfff2f2f2)) < 22 * 22 ||
      HomeHeroColors.distance(HomeHeroColors.surface(first, 0xff121212),
        HomeHeroColors.surface(second, 0xff121212)) < 18 * 18
  }

  private static brightness(tone: string): number {
    const rgb = HomeHeroColors.rgb(tone)
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
  }

  private static hue(rgb: number[]): number {
    const max = Math.max(...rgb)
    const delta = max - Math.min(...rgb)
    if (delta === 0) return 0
    const sector = max === rgb[0] ? (rgb[1] - rgb[2]) / delta :
      (max === rgb[1] ? (rgb[2] - rgb[0]) / delta + 2 : (rgb[0] - rgb[1]) / delta + 4)
    return ((sector * 60) % 360 + 360) % 360
  }

  private static rgb(tone: string): number[] {
    return [parseInt(tone.substring(1, 3), 16), parseInt(tone.substring(3, 5), 16),
      parseInt(tone.substring(5, 7), 16)]
  }

  private static distance(first: string, second: string): number {
    const a = HomeHeroColors.rgb(first)
    const b = HomeHeroColors.rgb(second)
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2
  }

  static blend(first: string, second: string, progress: number): string {
    const a = /^#[0-9a-f]{6}$/i.test(first)
    const b = /^#[0-9a-f]{6}$/i.test(second)
    const amount = Number.isFinite(progress) ? Math.max(0, Math.min(1, progress)) : 0
    if (amount === 0) return a ? first : ''
    if (amount === 1) return b ? second : ''
    if (!a || !b) return a ? first : (b ? second : '')
    let result = '#'
    for (let i = 1; i < 7; i += 2) {
      const value = Math.round(parseInt(first.substring(i, i + 2), 16) * (1 - amount) +
        parseInt(second.substring(i, i + 2), 16) * amount)
      result += value.toString(16).padStart(2, '0')
    }
    return result
  }

  static surface(tone: string, base: number): string {
    if (!/^#[0-9a-f]{6}$/i.test(tone) || base === 0) return ''
    const color = parseInt(tone.substring(1), 16)
    const red = (color >> 16) & 255
    const green = (color >> 8) & 255
    const blue = color & 255
    const baseRed = (base >> 16) & 255
    const baseGreen = (base >> 8) & 255
    const baseBlue = base & 255
    const dark = (0.2126 * baseRed + 0.7152 * baseGreen + 0.0722 * baseBlue) < 128
    const strength = dark ? 0.50 : 0.42
    const channels = [baseRed * (1 - strength) + red * strength,
      baseGreen * (1 - strength) + green * strength,
      baseBlue * (1 - strength) + blue * strength]
    const max = Math.max(...channels)
    const min = Math.min(...channels)
    // Correct the whole color. Clipping channels separately can turn different hues into one gray.
    const scale = dark && max > 88 ? 88 / max : 1
    const lift = !dark && min < 168 ? (168 - min) / (255 - min) : 0
    return '#' + channels.map((value: number) =>
      HomeHeroColors.channel(dark ? value * scale : value + (255 - value) * lift)).join('')
  }

  private static channel(value: number): string {
    return Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, '0')
  }
}
