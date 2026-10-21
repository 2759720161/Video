import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'

/** Cache colors, not decoded images; concurrent requests for one cover share a task. */
export class HomeHeroPalette {
  private static readonly cache: Map<string, string> = new Map()
  private static readonly pending: Map<string, Promise<string>> = new Map()
  private static readonly CACHE_LIMIT: number = 32

  static async resolve(artwork: string): Promise<string> {
    const url = artwork.trim()
    if (!/^https?:\/\/\S+$/i.test(url)) return ''
    const cached = HomeHeroPalette.cache.get(url)
    if (cached !== undefined) return cached
    const pending = HomeHeroPalette.pending.get(url)
    if (pending !== undefined) return pending
    const task = HomeHeroPalette.extract(url)
    HomeHeroPalette.pending.set(url, task)
    try {
      const color = await task
      if (color.length > 0) {
        HomeHeroPalette.cache.set(url, color)
        if (HomeHeroPalette.cache.size > HomeHeroPalette.CACHE_LIMIT) {
          const oldest = Array.from(HomeHeroPalette.cache.keys())[0]
          if (oldest !== undefined) HomeHeroPalette.cache.delete(oldest)
        }
      }
      return color
    } finally {
      HomeHeroPalette.pending.delete(url)
    }
  }

  private static async extract(url: string): Promise<string> {
    let request: http.HttpRequest | null = null
    let source: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      request = http.createHttp()
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000, readTimeout: 10000, maxLimit: 5 * 1024 * 1024
      })
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer) || response.result.byteLength === 0) return ''
      source = image.createImageSource(response.result)
      pixelMap = await source.createPixelMap({ desiredSize: { width: 64, height: 64 } })
      const picker = await effectKit.createColorPicker(pixelMap)
      // Averaging a colorful poster can produce gray. Prefer a substantial colored region.
      try {
        const colors = picker.getTopProportionColors(5)
        for (let i = 0; i < colors.length; i++) {
          const candidate = colors[i]
          if (candidate === null || candidate.alpha < 128) continue
          const max = Math.max(candidate.red, candidate.green, candidate.blue)
          const min = Math.min(candidate.red, candidate.green, candidate.blue)
          if (max - min >= 24 && max >= 60 && min <= 210) return HomeHeroPalette.hex(candidate)
        }
      } catch (_) {}
      const color = await picker.getMainColor()
      if (color.alpha === 0) return ''
      return HomeHeroPalette.hex(color)
    } catch (_) {
      return ''
    } finally {
      if (pixelMap !== null) { try { await pixelMap.release() } catch (_) {} }
      if (source !== null) { try { await source.release() } catch (_) {} }
      if (request !== null) { try { request.destroy() } catch (_) {} }
    }
  }

  private static hex(color: effectKit.Color): string {
    return '#' + HomeHeroPalette.channel(color.red) + HomeHeroPalette.channel(color.green) +
      HomeHeroPalette.channel(color.blue)
  }

  private static channel(value: number): string {
    return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0')
  }
}
