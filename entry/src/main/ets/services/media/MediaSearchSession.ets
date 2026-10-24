import { common } from '@kit.AbilityKit'
import { ProviderRegistry } from '../../providers/base/ProviderRegistry'
import { EmbyProvider } from '../../providers/emby/EmbyProvider'
import { EmbyItem } from '../../providers/emby/EmbyModels'
import { CatVodProvider } from '../../providers/catvod/CatVodProvider'
import { CatNodeProvider } from '../../providers/catvod/CatNodeProvider'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { CatNodeRequestControl } from '../../providers/catvod/CatNodeRequestControl'
import { CatVodVideo } from '../../providers/catvod/CatVodModels'
import type { CatVodDataSource } from '../../providers/catvod/CatVodModels'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { MediaSearchItem, MediaSearchPage, MediaSearchPresentation } from './MediaSearchPresentation'

/** Each search uses one explicit directory, independently of the home directory. */
export class MediaSearchSession {
  scopeName: string = ''
  historyKey: string = ''
  isEmby: boolean = false
  scopeKey: string = ''
  scopes: CatNodeSite[] = []
  canSearch: boolean = true
  private sourceId: string = ''
  private client: CatVodDataSource | null = null
  private provider: EmbyProvider | CatVodProvider

  constructor(provider: EmbyProvider | CatVodProvider) { this.provider = provider }

  static async open(sourceId: string, context: common.UIAbilityContext): Promise<MediaSearchSession> {
    const source = await MediaSourceStore.getById(sourceId)
    if (source === null || !source.enabled) throw new Error('搜索来源不可用')
    const provider = await ProviderRegistry.get(sourceId, context)
    if (!(provider instanceof EmbyProvider) && !(provider instanceof CatVodProvider)) throw new Error('该来源不支持搜索')
    const session = new MediaSearchSession(provider)
    session.sourceId = sourceId
    session.isEmby = provider instanceof EmbyProvider
    session.scopeName = source.name
    let siteKey = ''
    if (provider instanceof CatNodeProvider) {
      siteKey = provider.getSiteKey()
      const sites = await provider.sites()
      session.scopes = sites.filter((site: CatNodeSite) => site.searchable !== false && site.indexOnly !== true)
      session.canSearch = session.scopes.some((site: CatNodeSite) => site.key === siteKey)
      session.scopeName = sites.find((site: CatNodeSite) => site.key === siteKey)?.name ?? source.name
    }
    session.historyKey = 'media_search_history_v1:' + encodeURIComponent(sourceId) + ':' + encodeURIComponent(siteKey)
    session.scopeKey = siteKey
    return session
  }

  forScope(key: string, control: CatNodeRequestControl | null = null): MediaSearchSession {
    if (key === this.scopeKey && control === null) return this
    const site = this.scopes.find((value: CatNodeSite) => value.key === key)
    if (!(this.provider instanceof CatNodeProvider) || site === undefined) throw new Error('搜索目录不可用')
    const session = new MediaSearchSession(this.provider)
    session.sourceId = this.sourceId; session.scopes = this.scopes; session.scopeKey = key; session.scopeName = site.name
    session.canSearch = true
    session.historyKey = 'media_search_history_v1:' + encodeURIComponent(this.sourceId) + ':' + encodeURIComponent(key)
    session.client = this.provider.searchClient(key, control)
    return session
  }

  async search(keyword: string, page: number = 1): Promise<MediaSearchPage> {
    const word = MediaSearchPresentation.normalize(keyword)
    const result = new MediaSearchPage()
    if (word.length === 0) return result
    if (!this.canSearch) throw new Error('当前目录不提供搜索，请选择其他目录')
    if (!Number.isInteger(page) || page < 1) throw new Error('搜索页码无效')
    const provider = this.provider
    if (provider instanceof EmbyProvider) {
      if (page !== 1) throw new Error('当前服务不支持继续加载搜索结果')
      const items = await provider.searchRaw(word)
      result.items = items.map((item: EmbyItem) => {
        const value = new MediaSearchItem()
        value.id = item.id; value.title = item.name; value.subtitle = item.subtitle()
        value.overview = item.overview; value.year = item.productionYear
        value.artworkUrl = provider.imageUrlFor(item, 360); value.sourceName = this.scopeName; value.embyItem = item
        return value
      })
    } else {
      const data = await (this.client ?? provider.getClient()).page('', word, page)
      if (data.page !== page) throw new Error('来源未返回请求的搜索分页')
      result.page = data.page; result.pageCount = data.pageCount
      result.items = data.videos.map((item: CatVodVideo) => {
        const value = new MediaSearchItem()
        value.id = item.id; value.title = item.name; value.year = item.year
        value.subtitle = [item.year > 0 ? String(item.year) : '', item.remarks].filter((part: string) => part.length > 0).join(' · ')
        value.overview = item.overview; value.artworkUrl = item.poster; value.sourceName = this.scopeName
        return value
      })
    }
    result.items = MediaSearchPresentation.merge([], result.items)
    return result
  }
}
