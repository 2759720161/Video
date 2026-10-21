import { http } from '@kit.NetworkKit'
import { CatVodCategory, CatVodPage, CatVodVideo } from './CatVodModels'
import type { CatVodDataSource } from './CatVodModels'
import { CatVodCodec } from './CatVodCodec'
import { CatVodSourceConfig, CatVodSourceConfigCodec } from './CatVodSourceConfig'

export class CatVodClient implements CatVodDataSource {
  private config: CatVodSourceConfig
  constructor(config: CatVodSourceConfig) { this.config = config }

  async categories(): Promise<CatVodCategory[]> {
    const params: Record<string, string> = {}
    params['ac'] = 'list'
    return (await this.request(params)).categories
  }

  async page(categoryId: string, keyword: string, page: number): Promise<CatVodPage> {
    const params: Record<string, string> = {}
    params['ac'] = 'detail'
    params['pg'] = String(Number.isFinite(page) ? Math.max(1, Math.floor(page)) : 1)
    if (categoryId.length > 0) params['t'] = categoryId
    if (keyword.trim().length > 0) params['wd'] = keyword.trim()
    return this.request(params)
  }

  async detail(videoId: string): Promise<CatVodVideo | null> {
    const params: Record<string, string> = {}
    params['ac'] = 'detail'; params['ids'] = videoId
    const result = await this.request(params)
    return result.videos.find((video: CatVodVideo) => video.id === videoId) ?? null
  }

  private async request(params: Record<string, string>): Promise<CatVodPage> {
    const request = http.createHttp()
    try {
      const headers: Record<string, string> = { 'User-Agent': this.config.userAgent, 'Accept': 'application/json' }
      if (this.config.referer.length > 0) headers['Referer'] = this.config.referer
      const response = await request.request(CatVodSourceConfigCodec.requestUrl(this.config, params), {
        method: http.RequestMethod.GET, header: headers, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000, readTimeout: 20000, maxLimit: 3 * 1024 * 1024, usingCache: false
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('来源暂不可用（HTTP ' + response.responseCode + '）')
      }
      if (typeof response.result !== 'string') throw new Error('来源返回了无法读取的内容')
      return CatVodCodec.parse(response.result)
    } finally { request.destroy() }
  }
}
