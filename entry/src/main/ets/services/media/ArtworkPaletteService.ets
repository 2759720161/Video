import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { common } from '@kit.AbilityKit'

/** Normalized colors and readability parameters derived from one artwork. */
export class ArtworkVisualProfile {
  primaryColor: string = '#202020'
  secondaryColor: string = '#101010'
  accentColor: string = '#404040'
  luminance: number = 0
  saturation: number = 0
  artworkDark: boolean = true
  ambientOpacity: number = 0.30
  scrimOpacity: number = 0.50
}

class ArtworkHsl {
  h: number = 0
  s: number = 0
  l: number = 0
}

/** Low-resolution artwork analysis with an in-memory URL cache. */
export class ArtworkPaletteService {
  private static readonly cache: Map<string, ArtworkVisualProfile> = new Map()
  private static readonly SAMPLE_SIZE: number = 64

  static async resolve(_context: common.UIAbilityContext, artworkUrl: string): Promise<ArtworkVisualProfile> {
    const url = artworkUrl.trim()
    if (url.length === 0) return new ArtworkVisualProfile()
    const cached = ArtworkPaletteService.cache.get(url)
    if (cached !== undefined) return ArtworkPaletteService.copy(cached)

    let request: http.HttpRequest | null = null
    let source: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      request = http.createHttp()
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'image/avif,image/webp,image/jpeg,image/png,*/*' },
        connectTimeout: 8000,
        readTimeout: 12000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
        return new ArtworkVisualProfile()
      }
      source = image.createImageSource(response.result)
      pixelMap = await source.createPixelMap({
        desiredSize: { width: ArtworkPaletteService.SAMPLE_SIZE, height: ArtworkPaletteService.SAMPLE_SIZE }
      })
      const pixelBytes = pixelMap.getPixelBytesNumber()
      if (pixelBytes <= 0) return new ArtworkVisualProfile()
      const buffer = new ArrayBuffer(pixelBytes)
      await pixelMap.readPixelsToBuffer(buffer)
      const profile = ArtworkPaletteService.analyze(new Uint8Array(buffer))
      ArtworkPaletteService.cache.set(url, ArtworkPaletteService.copy(profile))
      return profile
    } catch (_) {
      return new ArtworkVisualProfile()
    } finally {
      if (pixelMap !== null) {
        try { await pixelMap.release() } catch (_) {}
      }
      if (source !== null) {
        try { await source.release() } catch (_) {}
      }
      if (request !== null) request.destroy()
    }
  }

  private static analyze(bytes: Uint8Array): ArtworkVisualProfile {
    const profile = new ArtworkVisualProfile()
    if (bytes.length < 4) return profile
    let red = 0
    let green = 0
    let blue = 0
    let weight = 0
    let vividRed = 32
    let vividGreen = 32
    let vividBlue = 32
    let vividScore = -1
    for (let i = 0; i + 3 < bytes.length; i += 4) {
      const alpha = bytes[i + 3] / 255
      if (alpha < 0.18) continue
      const r = bytes[i]
      const g = bytes[i + 1]
      const b = bytes[i + 2]
      const max = Math.max(r, g, b)
      const min = Math.min(r, g, b)
      const saturation = max <= 0 ? 0 : (max - min) / max
      const pixelWeight = 0.35 + alpha * 0.65
      red += r * pixelWeight
      green += g * pixelWeight
      blue += b * pixelWeight
      weight += pixelWeight
      const score = saturation * (0.35 + max / 255)
      if (score > vividScore) {
        vividScore = score
        vividRed = r
        vividGreen = g
        vividBlue = b
      }
    }
    if (weight <= 0) return profile
    const averageRed = red / weight
    const averageGreen = green / weight
    const averageBlue = blue / weight
    const hsl = ArtworkPaletteService.toHsl(averageRed, averageGreen, averageBlue)
    profile.luminance = ArtworkPaletteService.relativeLuminance(averageRed, averageGreen, averageBlue)
    profile.saturation = hsl.s
    profile.artworkDark = profile.luminance < 0.42
    const vividHsl = ArtworkPaletteService.toHsl(vividRed, vividGreen, vividBlue)
    profile.primaryColor = ArtworkPaletteService.fromHsl(hsl.h, Math.min(0.58, hsl.s * 0.70),
      ArtworkPaletteService.clamp(hsl.l * 0.46, 0.10, 0.30))
    profile.secondaryColor = ArtworkPaletteService.fromHsl(hsl.h, Math.min(0.42, hsl.s * 0.48),
      ArtworkPaletteService.clamp(hsl.l * 0.25, 0.055, 0.18))
    profile.accentColor = ArtworkPaletteService.fromHsl(vividHsl.h, Math.min(0.62, vividHsl.s * 0.76),
      ArtworkPaletteService.clamp(vividHsl.l * 0.58, 0.16, 0.42))
    if (profile.artworkDark) {
      profile.ambientOpacity = profile.saturation > 0.62 ? 0.30 : 0.32
      profile.scrimOpacity = 0.46
    } else {
      profile.ambientOpacity = profile.saturation > 0.62 ? 0.18 : 0.22
      profile.scrimOpacity = 0.62
    }
    return profile
  }

  private static toHsl(red: number, green: number, blue: number): ArtworkHsl {
    const r = red / 255
    const g = green / 255
    const b = blue / 255
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    const lightness = (max + min) / 2
    const delta = max - min
    if (delta <= 0.0001) {
      const gray = new ArtworkHsl()
      gray.l = lightness
      return gray
    }
    const saturation = lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min)
    let hue: number
    if (max === r) hue = ((g - b) / delta + (g < b ? 6 : 0)) / 6
    else if (max === g) hue = ((b - r) / delta + 2) / 6
    else hue = ((r - g) / delta + 4) / 6
    const result = new ArtworkHsl()
    result.h = hue
    result.s = saturation
    result.l = lightness
    return result
  }

  private static fromHsl(hue: number, saturation: number, lightness: number): string {
    if (saturation <= 0.0001) {
      const gray = ArtworkPaletteService.toHex(Math.round(lightness * 255))
      return '#' + gray + gray + gray
    }
    const q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
    const p = 2 * lightness - q
    const red = ArtworkPaletteService.hueToRgb(p, q, hue + 1 / 3)
    const green = ArtworkPaletteService.hueToRgb(p, q, hue)
    const blue = ArtworkPaletteService.hueToRgb(p, q, hue - 1 / 3)
    return '#' + ArtworkPaletteService.toHex(Math.round(red * 255)) +
      ArtworkPaletteService.toHex(Math.round(green * 255)) + ArtworkPaletteService.toHex(Math.round(blue * 255))
  }

  private static hueToRgb(p: number, q: number, value: number): number {
    let t = value
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }

  private static relativeLuminance(red: number, green: number, blue: number): number {
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
  }

  private static clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value))
  }

  private static toHex(value: number): string {
    return Math.max(0, Math.min(255, value)).toString(16).padStart(2, '0')
  }

  private static copy(profile: ArtworkVisualProfile): ArtworkVisualProfile {
    const result = new ArtworkVisualProfile()
    result.primaryColor = profile.primaryColor
    result.secondaryColor = profile.secondaryColor
    result.accentColor = profile.accentColor
    result.luminance = profile.luminance
    result.saturation = profile.saturation
    result.artworkDark = profile.artworkDark
    result.ambientOpacity = profile.ambientOpacity
    result.scrimOpacity = profile.scrimOpacity
    return result
  }
}
