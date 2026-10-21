import { common } from '@kit.AbilityKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { PlaybackStream } from '../../core/playback/PlaybackStream'
import { CatVodProvider } from './CatVodProvider'
import { CatVodSourceConfig } from './CatVodSourceConfig'
import { CatVodEpisode, CatVodRoad } from './CatVodModels'
import { CatVodCodec } from './CatVodCodec'
import { CatNodeClient } from './CatNodeClient'
import { CatNodeSourceConfig, CatNodeSubscriptionCodec } from './CatNodeSubscription'
import { CatNodeRuntime, CatNodeSite } from './CatNodeRuntime'
import { MediaSourceStore } from '../../store/MediaSourceStore'

export class CatNodeProvider extends CatVodProvider {
  private nodeClient: CatNodeClient
  private nodeSource: MediaSourceInstance
  private nodeContext: common.UIAbilityContext
  private nodeConfig: CatNodeSourceConfig
  constructor(source: MediaSourceInstance, client: CatNodeClient, context: common.UIAbilityContext, config: CatNodeSourceConfig) {
    super(source, client, new CatVodSourceConfig())
    this.nodeClient = client; this.nodeSource = source; this.nodeContext = context; this.nodeConfig = config
  }
  static async create(source: MediaSourceInstance, context: common.UIAbilityContext | null): Promise<CatNodeProvider> {
    if (context === null) throw new Error('猫源运行环境不可用')
    const config = CatNodeSubscriptionCodec.decode(source.configJson)
    if (config.md5Url.length === 0) throw new Error('请编辑 Cat 订阅并填写 index.js.md5 地址')
    config.md5Url = CatNodeSubscriptionCodec.normalizeUrl(config.md5Url)
    const sites = await CatNodeRuntime.sites(context, config.md5Url)
    const selected = sites.find((site: CatNodeSite) => site.key === config.spiderKey) ?? sites[0]
    config.spiderKey = selected.key
    return new CatNodeProvider(source, new CatNodeClient(context, selected.key, config.md5Url, config.legacySpiderKey), context, config)
  }
  async sites(): Promise<CatNodeSite[]> { return CatNodeRuntime.sites(this.nodeContext, this.nodeConfig.md5Url) }
  getSiteKey(): string { return this.nodeClient.getSiteKey() }
  async selectSite(key: string): Promise<void> {
    const sites = await this.sites()
    if (!sites.some((site: CatNodeSite) => site.key === key)) throw new Error('该来源已不可用')
    const current = await MediaSourceStore.getById(this.nodeSource.id)
    if (current === null) throw new Error('Cat 订阅已删除')
    const config = CatNodeSubscriptionCodec.decode(current.configJson)
    config.spiderKey = key
    current.configJson = JSON.stringify(config)
    await MediaSourceStore.update(current)
  }
  protected async resolveEpisode(road: CatVodRoad, episode: CatVodEpisode): Promise<PlaybackStream> {
    return this.nodeClient.resolve(road, episode)
  }
}
