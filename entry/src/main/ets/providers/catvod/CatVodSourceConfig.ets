import { CatVodCodec } from './CatVodCodec'

export const CATVOD_DEFAULT_API: string = 'http://caiji.dyttzyapi.com/api.php/provide/vod/'
export const CATVOD_DEFAULT_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

export class CatVodSourceConfig {
  apiUrl: string = CATVOD_DEFAULT_API
  userAgent: string = CATVOD_DEFAULT_AGENT
  referer: string = ''
}

export class CatVodSourceConfigCodec {
  static decode(text: string): CatVodSourceConfig | null {
    try {
      const raw = CatVodCodec.object(JSON.parse(text) as Object)
      if (raw === null || typeof raw['apiUrl'] !== 'string') return null
      const config = new CatVodSourceConfig()
      config.apiUrl = CatVodCodec.text(raw['apiUrl'])
      config.userAgent = CatVodCodec.text(raw['userAgent']) || CATVOD_DEFAULT_AGENT
      config.referer = CatVodCodec.text(raw['referer'])
      return CatVodSourceConfigCodec.normalize(config) ? config : null
    } catch (_) { return null }
  }

  static normalize(config: CatVodSourceConfig): boolean {
    config.apiUrl = config.apiUrl.trim()
    config.userAgent = config.userAgent.trim() || CATVOD_DEFAULT_AGENT
    config.referer = config.referer.trim()
    if (!CatVodCodec.isHttpUrl(config.apiUrl) || config.apiUrl.includes('#') ||
      /\.(?:js|md5)(?:\?|$)/i.test(config.apiUrl)) return false
    if (/[\r\n]/.test(config.userAgent) || /[\r\n]/.test(config.referer)) return false
    return config.referer.length === 0 || CatVodCodec.isHttpUrl(config.referer)
  }

  static encode(config: CatVodSourceConfig): string {
    return JSON.stringify(config)
  }

  /** 保留来源自定义参数，同时替换分页、搜索与详情参数。 */
  static requestUrl(config: CatVodSourceConfig, params: Record<string, string>): string {
    const separator = config.apiUrl.indexOf('?')
    const base = separator >= 0 ? config.apiUrl.substring(0, separator) : config.apiUrl
    const retained: string[] = []
    const reserved = ['ac', 'pg', 't', 'wd', 'ids']
    const existing = separator >= 0 ? config.apiUrl.substring(separator + 1).split('&') : []
    for (let i = 0; i < existing.length; i++) {
      if (existing[i].length === 0) continue
      const rawKey = existing[i].split('=')[0]
      let key = rawKey
      try { key = decodeURIComponent(rawKey) } catch (_) {}
      if (!reserved.includes(key)) retained.push(existing[i])
    }
    const keys = Object.keys(params)
    for (let i = 0; i < keys.length; i++) retained.push(encodeURIComponent(keys[i]) + '=' + encodeURIComponent(params[keys[i]]))
    return base + '?' + retained.join('&')
  }
}
