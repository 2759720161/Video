/** Preserve the cover's chroma, with lightness bounds for the theme's normal text. */
export class HomeHeroColors {
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
    return '#' + HomeHeroColors.channel(baseRed, red, strength, dark) +
      HomeHeroColors.channel(baseGreen, green, strength, dark) +
      HomeHeroColors.channel(baseBlue, blue, strength, dark)
  }

  private static channel(base: number, tone: number, strength: number, dark: boolean): string {
    const value = base * (1 - strength) + tone * strength
    // Avoid a dark cover turning the light page gray, or a white cover washing out the dark page.
    const bounded = dark ? Math.min(88, value) : Math.max(168, value)
    return Math.round(bounded).toString(16).padStart(2, '0')
  }
}
