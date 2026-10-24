import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HomeHeroColors } from './HomeHeroColors'
import { HomeHeroPaletteStore } from './HomeHeroPaletteStore'
import { HomeHeroImageTone } from './HomeHeroImageTone'

/** Cache colors, not decoded images; concurrent requests for one cover share a task. */
export class HomeHeroPalette {
  private static readonly cache: Map<string, string> = new Map()
  private static readonly pending: Map<string, Promise<string>> = new Map()
  private static readonly CACHE_LIMIT: number = 32
  private static requestId: number = 0
  private static distinctionKey: string = ''
  private static displayTones: string[] = []

  static peek(artwork: string): string { return HomeHeroPalette.cache.get(artwork.trim()) ?? '' }

  static at(artworks: string[], position: number, failed: Set<string>): string {
    if (artworks.length === 0 || !Number.isFinite(position)) return ''
    const center = ((position % artworks.length) + artworks.length) % artworks.length
    const index = Math.floor(center)
    const tones = artworks.map((url: string) => failed.has(url) ? '' : HomeHeroPalette.peek(url))
    const key = JSON.stringify(tones)
    if (key !== HomeHeroPalette.distinctionKey) {
      HomeHeroPalette.displayTones = HomeHeroColors.distinguish(tones)
      HomeHeroPalette.distinctionKey = key
    }
    return HomeHeroColors.blend(HomeHeroPalette.displayTones[index],
      HomeHeroPalette.displayTones[(index + 1) % artworks.length], center - index)
  }

  static async warm(artworks: string[], onReady: () => void, position: number = 0,
    isCurrent: () => boolean = () => true, samples: string[] = artworks): Promise<void> {
    if (artworks.length === 0) return
    const selected = Number.isFinite(position) ? Math.floor(position) : 0
    const index = ((selected % artworks.length) + artworks.length) % artworks.length
    const ordered = [artworks[index], artworks[(index + 1) % artworks.length],
      artworks[(index + artworks.length - 1) % artworks.length], ...artworks]
    const urls = Array.from(new Set(ordered.filter((url: string) => url.length > 0)))
    let cursor = 0
    const worker = async (): Promise<void> => {
      while (cursor < urls.length && isCurrent()) {
        const url = urls[cursor++]
        await HomeHeroPalette.resolve(url, samples[artworks.indexOf(url)] || url)
        if (isCurrent()) onReady()
      }
    }
    await Promise.all([worker(), worker(), worker()])
  }

  static async resolve(artwork: string, sample: string = artwork): Promise<string> {
    const url = artwork.trim()
    if (!/^https?:\/\/\S+$/i.test(url)) return ''
    const cached = HomeHeroPalette.cache.get(url)
    if (cached !== undefined) return cached
    const pending = HomeHeroPalette.pending.get(url)
    if (pending !== undefined) return pending
    const requestId = ++HomeHeroPalette.requestId
    const startedAt = Date.now()
    hilog.info(0, 'HomeHeroPalette', 'begin id=%{public}d', requestId)
    const task = HomeHeroPalette.restoreOrExtract(url, sample, requestId)
    HomeHeroPalette.pending.set(url, task)
    try {
      const color = await task
      hilog.info(0, 'HomeHeroPalette', 'ready id=%{public}d elapsedMs=%{public}d success=%{public}d tone=%{public}s',
        requestId, Date.now() - startedAt, color.length > 0 ? 1 : 0, color)
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

  private static async restoreOrExtract(url: string, sample: string, requestId: number): Promise<string> {
    let key = ''
    try {
      key = await HomeHeroPaletteStore.identity(url)
      const stored = await HomeHeroPaletteStore.get(key)
      if (stored.length > 0) {
        hilog.info(0, 'HomeHeroPalette', 'restored id=%{public}d', requestId)
        return stored
      }
    } catch (_) {}
    const color = await HomeHeroPalette.extract(/^https?:\/\/\S+$/i.test(sample) ? sample : url, requestId)
    if (color.length > 0 && key.length > 0) HomeHeroPaletteStore.put(key, color)
    return color
  }

  private static async extract(url: string, requestId: number): Promise<string> {
    let request: http.HttpRequest | null = null
    let source: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      request = http.createHttp()
      const downloadStartedAt = Date.now()
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000, readTimeout: 10000, maxLimit: 5 * 1024 * 1024
      })
      hilog.info(0, 'HomeHeroPalette',
        'downloaded id=%{public}d elapsedMs=%{public}d bytes=%{public}d status=%{public}d',
        requestId, Date.now() - downloadStartedAt,
        response.result instanceof ArrayBuffer ? response.result.byteLength : 0, response.responseCode)
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer) || response.result.byteLength === 0) return ''
      source = image.createImageSource(response.result)
      pixelMap = await source.createPixelMap({ desiredSize: { width: 64, height: 64 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888 })
      try {
        const info = await pixelMap.getImageInfo()
        const bytes = pixelMap.getPixelBytesNumber()
        const expected = info.size.width * info.size.height * 4
        if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 ||
          !Number.isInteger(expected) || expected <= 0 || bytes < expected || bytes > 256 * 256 * 4 ||
          (info.alphaType !== image.AlphaType.PREMUL && info.alphaType !== image.AlphaType.UNPREMUL &&
            info.alphaType !== image.AlphaType.OPAQUE)) throw new Error('Unsupported pixel layout')
        const buffer = new ArrayBuffer(bytes)
        await pixelMap.readPixelsToBuffer(buffer)
        const sample = HomeHeroImageTone.analyze(new Uint8Array(buffer, 0, expected),
          info.alphaType === image.AlphaType.PREMUL, info.alphaType === image.AlphaType.OPAQUE)
        hilog.info(0, 'HomeHeroPalette',
          'sampled id=%{public}d mode=pixels blackPct=%{public}d accentPct=%{public}d tone=%{public}s',
          requestId, Math.round(sample.blackShare * 100), Math.round(sample.accentShare * 100), sample.tone)
        return sample.tone
      } catch (_) {}
      const picker = await effectKit.createColorPicker(pixelMap)
      const color = await picker.getMainColor()
      if (color.alpha === 0) return ''
      const tone = HomeHeroPalette.hex(color)
      hilog.info(0, 'HomeHeroPalette', 'sampled id=%{public}d mode=main tone=%{public}s', requestId, tone)
      return tone
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
