import { common } from '@kit.AbilityKit'
import { PlaybackStream } from '../../core/playback/PlaybackStream'
import { CatNodeAddress, CatNodeRuntime, CatNodeSite } from './CatNodeRuntime'
import { CatVodCodec } from './CatVodCodec'
import { CatVodCategory, CatVodEpisode, CatVodPage, CatVodRoad, CatVodVideo } from './CatVodModels'
import type { CatVodDataSource } from './CatVodModels'

export class CatNodeClient implements CatVodDataSource {
  private context: common.Context
  private key: string
  private md5Url: string
  private legacyKey: string
  private initialized: Promise<void> | null = null
  private session: CatNodeAddress | null = null
  private home: CatVodPage | null = null
  constructor(context: common.Context, key: string, md5Url: string = '', legacyKey: string = '') {
    this.context = context; this.key = key; this.md5Url = md5Url; this.legacyKey = legacyKey
  }

  getSiteKey(): string { return this.key }

  private async init(): Promise<void> {
    const session = await CatNodeRuntime.ensure(this.context, this.md5Url)
    if (this.session !== session) {
      this.session = session
      this.initialized = null
      this.home = null
    }
    if (this.initialized !== null) return this.initialized
    this.initialized = this.initialize()
    try { await this.initialized } catch (error) {
      this.initialized = null; throw new Error(error instanceof Error ? error.message : '来源初始化失败')
    }
  }
  private async initialize(): Promise<void> {
    const sites = await CatNodeRuntime.sites(this.context, this.md5Url)
    const site = sites.find((value: CatNodeSite) => value.key === this.key)
    if (site === undefined) throw new Error('所选猫源已不可用，请重新选择来源')
    const params: Record<string, Object> = { 'ext': site.ext }
    await this.call('init', params)
  }
  private async call(route: string, body: Record<string, Object>): Promise<string> {
    const address = await CatNodeRuntime.ensure(this.context, this.md5Url)
    const text = await CatNodeRuntime.request(address.baseUrl() + '/spider/' + encodeURIComponent(this.key) + '/' + route, body)
    const value = JSON.parse(text) as Object
    return typeof value === 'string' ? value : JSON.stringify(value)
  }
  private async parsePage(text: string): Promise<CatVodPage> {
    const page = CatVodCodec.parse(text, true)
    const base = (await CatNodeRuntime.ensure(this.context, this.md5Url)).baseUrl()
    for (let i = 0; i < page.videos.length; i++) {
      const video = page.videos[i]
      if (this.md5Url.length > 0) video.id = 'catnode:' + encodeURIComponent(this.key) + ':' + encodeURIComponent(video.id)
      for (let r = 0; r < video.roads.length; r++) video.roads[r].spiderKey = this.key
      if (video.poster.startsWith('js2p://_WEB_')) video.poster = base + video.poster.substring('js2p://_WEB_'.length)
      else if (video.poster.startsWith('/') && !video.poster.startsWith('//')) video.poster = base + video.poster
    }
    return page
  }
  async categories(): Promise<CatVodCategory[]> {
    await this.init()
    const params: Record<string, Object> = { 'filter': true }
    this.home = await this.parsePage(await this.call('home', params))
    return this.home.categories
  }
  async page(categoryId: string, keyword: string, page: number): Promise<CatVodPage> {
    await this.init()
    if (keyword.trim().length > 0) {
      const params: Record<string, Object> = { 'wd': keyword.trim(), 'page': page, 'pg': page, 'quick': false }
      return this.parsePage(await this.call('search', params))
    }
    if (this.home === null) await this.categories()
    if (categoryId.length === 0 && page === 1 && (this.home?.videos.length ?? 0) > 0) return this.home as CatVodPage
    const id = categoryId || this.home?.categories[0]?.id || ''
    if (id.length === 0) throw new Error('该来源没有可浏览的分类，请尝试搜索')
    const extend: Record<string, Object> = {}
    const params: Record<string, Object> = { 'id': id, 'page': page, 'pg': page, 'filter': true, 'extend': extend }
    return this.parsePage(await this.call('category', params))
  }
  async detail(videoId: string): Promise<CatVodVideo | null> {
    let key = this.key
    let rawId = videoId
    if (videoId.startsWith('catnode:')) {
      const parts = videoId.split(':')
      if (parts.length !== 3) throw new Error('Cat 订阅作品标识无效')
      key = decodeURIComponent(parts[1]); rawId = decodeURIComponent(parts[2])
    } else if (this.legacyKey.length > 0) key = this.legacyKey
    if (key !== this.key) {
      const video = await new CatNodeClient(this.context, key, this.md5Url).detail(
        this.md5Url.length > 0 ? 'catnode:' + encodeURIComponent(key) + ':' + encodeURIComponent(rawId) : rawId)
      if (video !== null && !videoId.startsWith('catnode:')) video.id = videoId
      return video
    }
    await this.init()
    const ids: string[] = [rawId]
    const params: Record<string, Object> = { 'id': ids }
    const result = await this.parsePage(await this.call('detail', params))
    const expected = this.md5Url.length > 0 ? 'catnode:' + encodeURIComponent(key) + ':' + encodeURIComponent(rawId) : rawId
    const video = result.videos.find((value: CatVodVideo) => value.id === expected) ?? null
    // Preserve pre-subscription history identifiers while routing them through
    // their original spider; all newly listed items use namespaced identities.
    if (video !== null && !videoId.startsWith('catnode:')) video.id = videoId
    return video
  }

  async resolve(road: CatVodRoad, episode: CatVodEpisode): Promise<PlaybackStream> {
    if ((road.spiderKey ?? '').length > 0 && road.spiderKey !== this.key) {
      return new CatNodeClient(this.context, road.spiderKey, this.md5Url).resolve(road, episode)
    }
    await this.init()
    const flags: string[] = [road.name]
    const params: Record<string, Object> = { 'flag': road.name, 'id': episode.url, 'flags': flags }
    const raw = CatVodCodec.object(JSON.parse(await this.call('play', params)) as Object)
    if (raw === null) throw new Error('来源没有返回播放地址')
    const address = await CatNodeRuntime.ensure(this.context, this.md5Url)
    const value = raw['url']
    const candidates = Array.isArray(value) ? value as Object[] : [value ?? '']
    let url = ''
    for (let i = 0; i < candidates.length; i++) {
      let candidate = CatVodCodec.text(candidates[i])
      if (candidate.startsWith('js2p://_WEB_')) candidate = address.baseUrl() + candidate.substring('js2p://_WEB_'.length)
      else if (candidate.startsWith('/')) candidate = address.baseUrl() + candidate
      if (CatVodCodec.isPlayableUrl(candidate)) { url = candidate; break }
    }
    if (url.length === 0) throw new Error('该来源暂未返回可播放地址')
    if ((raw['parse'] === true || raw['jx'] === true || CatVodCodec.text(raw['parse']) === '1' || CatVodCodec.text(raw['jx']) === '1') &&
      !/\.(m3u8|mp4|mkv|webm|mp3|flac|aac)$/i.test(url.split(/[?#]/)[0])) {
      throw new Error('该线路需要网页解析，当前版本暂未支持，请选择其他线路')
    }
    const stream = new PlaybackStream()
    stream.url = url
    let header = raw['header'] ?? raw['headers']
    if (typeof header === 'string' && header.trim().startsWith('{')) header = JSON.parse(header) as Object
    const headers = CatVodCodec.object(header)
    if (headers !== null) {
      const keys = Object.keys(headers)
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i]
        const content = CatVodCodec.text(headers[key])
        if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(key) || /[\r\n]/.test(content)) throw new Error('来源返回了无效请求头')
        stream.headers[key] = content
        if (key.toLowerCase() === 'referer') stream.referer = content
        if (key.toLowerCase() === 'user-agent') stream.userAgent = content
      }
    }
    return stream
  }
}
