import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../../utils/Logger'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { PlaybackStream } from '../../core/playback/PlaybackStream'
import { CatVodProvider } from './CatVodProvider'
import { CatVodSourceConfig } from './CatVodSourceConfig'
import { CatVodEpisode, CatVodRoad, CatVodVideo } from './CatVodModels'
import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { PlaybackSession } from '../../core/playback/PlaybackSession'
import { CatVodCodec } from './CatVodCodec'
import { CatNodeClient } from './CatNodeClient'
import { CatNodeRequestControl } from './CatNodeRequestControl'
import { CatNodeSourceConfig, CatNodeSubscriptionCodec, CatNodeSubscription } from './CatNodeSubscription'
import { CatNodeRuntime, CatNodeSite } from './CatNodeRuntime'
import { CatNodeConfiguration } from './CatNodeConfiguration'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { CatPlaybackSnapshotStore } from './CatPlaybackSnapshotStore'
import { CatPlaybackPreparationCache } from './CatPlaybackPreparationCache'
import { CatPlaybackStreamCache } from './CatPlaybackStreamCache'
import { CatStreamProbe } from './CatStreamProbe'
import { CatArtwork } from './CatArtwork'
import { MediaItem } from '../../core/media/MediaItem'
import { CatPlaybackHistoryScope } from './CatPlaybackHistoryScope'

const preparationLogger = new Logger('CatPlaybackPrepare')

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
  /** Restore a display session without querying the runtime's catalog during a fresh cache hit. */
  static fromCachedSites(source: MediaSourceInstance, context: common.UIAbilityContext, sites: CatNodeSite[], key: string): CatNodeProvider {
    const config = CatNodeSubscriptionCodec.decode(source.configJson)
    config.md5Url = CatNodeSubscriptionCodec.normalizeUrl(config.md5Url)
    if (key.length === 0 || !sites.some((site: CatNodeSite) => site.key === key) ||
      (config.spiderKey.length > 0 && config.spiderKey !== key)) throw new Error('首页缓存目录已变化')
    config.spiderKey = key
    return new CatNodeProvider(source, new CatNodeClient(context, key, config.md5Url, config.legacySpiderKey), context, config)
  }
  async cachedArtworkBase(): Promise<string> {
    return (await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)).baseUrl()
  }
  async configurationUrl(): Promise<string> {
    return CatNodeConfiguration.pageUrl(await this.cachedArtworkBase())
  }
  getSiteKey(): string { return this.nodeClient.getSiteKey() }
  async getResumeItems(limit: number = 0): Promise<MediaItem[]> {
    const items = (await super.getResumeItems()).filter((item: MediaItem) =>
      CatPlaybackHistoryScope.matches(item.id, this.getSiteKey(), this.nodeConfig.legacySpiderKey))
    return limit > 0 ? items.slice(0, limit) : items
  }
  protected async preparationScope(): Promise<Object> {
    return CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
  }
  protected usesPreparationCache(): boolean { return true }

  private async snapshotKey(videoId: string): Promise<string> {
    const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
    if (!address.dataRoot || !address.bundleSha256) return ''
    const path = address.dataRoot + '/profile.json'
    if (fileIo.accessSync(path) && fileIo.statSync(path).size > 2 * 1024 * 1024) return ''
    const profile = fileIo.accessSync(path) ? fileIo.readTextSync(path) : ''
    const identity = JSON.stringify([this.preparationKey(videoId), address.bundleSha256, profile])
    return CatNodeSubscription.digest(new util.TextEncoder('utf-8').encodeInto(identity), 'SHA256')
  }

  private async streamKey(item: PlaybackQueueItem): Promise<string> {
    const identity = CatVodCodec.identity(item.mediaId)
    if (identity === null || item.sourceId !== this.getSourceId() || !item.variantId) return ''
    const detailKey = await this.snapshotKey(identity.videoId)
    if (!detailKey) return ''
    return CatNodeSubscription.digest(new util.TextEncoder('utf-8').encodeInto(
      JSON.stringify([detailKey, item.mediaId, item.variantId])), 'SHA256')
  }

  private async cachedStream(item: PlaybackQueueItem, probe: boolean): Promise<PlaybackStream | null> {
    try {
      const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
      const key = await this.streamKey(item)
      if (!key) return null
      const cached = CatPlaybackStreamCache.get(address.dataRoot, key)
      if (cached === null || !probe) return cached
      const started = Date.now()
      const proxy = CatPlaybackStreamCache.get(address.dataRoot, key, address.baseUrl())
      let selected = cached
      let transport = 'direct'
      if (proxy !== null) {
        if (await CatStreamProbe.check(proxy)) {
          selected = proxy; transport = 'source_proxy'
        } else {
          preparationLogger.info('stream_cache status=proxy_probe_failed elapsedMs=%{public}d', Date.now() - started)
        }
      }
      const valid = transport === 'source_proxy' || await CatStreamProbe.check(cached)
      if (valid && (await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)) === address &&
        await this.streamKey(item) === key) {
        preparationLogger.info('stream_cache status=hit probeMs=%{public}d transport=%{public}s', Date.now() - started, transport)
        return selected
      }
      CatPlaybackStreamCache.drop(address.dataRoot, key)
      preparationLogger.info('stream_cache status=probe_failed elapsedMs=%{public}d', Date.now() - started)
    } catch (_) { preparationLogger.warn('stream_cache status=unavailable') }
    return null
  }

  protected async loadDetail(videoId: string, force: boolean, trace: (status: string) => void,
    requireLive: boolean = false): Promise<CatVodVideo | null> {
    const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
    if (force) CatPlaybackSnapshotStore.invalidate(address.dataRoot)
    const revision = CatPlaybackSnapshotStore.revision()
    const memoryRevision = CatPlaybackPreparationCache.revision()
    let key = ''
    try { key = await this.snapshotKey(videoId) } catch (_) {}
    if (!force && !requireLive && key.length > 0) {
      const restored = CatPlaybackSnapshotStore.get(address.dataRoot, key, videoId)
      if (restored !== null) {
        restored.poster = CatArtwork.resolve(restored.poster, address.baseUrl())
        trace('disk_hit')
        return restored
      }
    }
    const video = await this.nodeClient.detail(videoId)
    if (video !== null) {
      if ((await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)) === address &&
        memoryRevision === CatPlaybackPreparationCache.revision()) {
        CatPlaybackPreparationCache.markLiveDetail(address, this.preparationKey(videoId))
      }
      try {
        key = await this.snapshotKey(videoId)
        if (key.length > 0 && (await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)) === address) {
          const saved = CatPlaybackSnapshotStore.put(address.dataRoot, key, video, revision)
          preparationLogger.info('detail_snapshot stored=%{public}s', String(saved))
        }
      } catch (_) { preparationLogger.warn('detail_snapshot stored=false reason=storage_unavailable') }
    }
    return video
  }

  /** Opaque playback IDs may depend on state created by detail() in the new source process. */
  private async prepareLivePlayback(item: PlaybackQueueItem, current: () => boolean = () => true,
    inspectStreamCache: boolean = true): Promise<void> {
    if (!current()) return
    if (inspectStreamCache && !item.bypassStreamCache && await this.cachedStream(item, false) !== null) return
    const identity = CatVodCodec.identity(item.mediaId)
    if (identity === null || item.sourceId !== this.getSourceId()) return
    const video = await this.getDetail(identity.videoId)
    if (!current() || video === null) return
    const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
    if (!current() || CatPlaybackPreparationCache.hasLiveDetail(address, this.preparationKey(video.id))) return
    const eligible = video.roads.filter((road: CatVodRoad) => CatVodCodec.findEpisode(road, identity) !== null)
    const road = item.variantId.length > 0 ? eligible.find((value: CatVodRoad) => value.id === item.variantId) :
      eligible.find((value: CatVodRoad) => value.name.toLowerCase().includes('m3u8')) ?? eligible[0]
    const episode = road === undefined ? null : CatVodCodec.findEpisode(road, identity)
    if (episode === null) return
    let needsLive = !CatVodCodec.isHttpUrl(episode.url)
    if (!needsLive) {
      try { needsLive = CatPlaybackSnapshotStore.requiresLive(address.dataRoot, await this.snapshotKey(video.id)) } catch (_) {}
    }
    if (!current() || !needsLive) return
    preparationLogger.info('detail_prepare status=prime_live reason=runtime_state')
    await this.getDetail(video.id, false, () => {}, true)
  }

  async resolvePlayback(item: PlaybackQueueItem, forceFresh: boolean = false): Promise<PlaybackSession> {
    if (!forceFresh && !item.bypassStreamCache) {
      const cached = await this.cachedStream(item, true)
      if (cached !== null) return super.resolvePlayback(item, false, cached)
    }
    if (forceFresh || item.bypassStreamCache) {
      try {
        const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
        const key = await this.streamKey(item)
        if (key) CatPlaybackStreamCache.drop(address.dataRoot, key)
      } catch (_) {}
    }
    const resolutionAddress = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
    const revision = CatPlaybackStreamCache.revision()
    if (!forceFresh) await this.prepareLivePlayback(item, () => true, false)
    const session = await super.resolvePlayback(item, forceFresh)
    if (!session.stream.reused) {
      try {
        const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
        const key = await this.streamKey(item)
        if (key && address === resolutionAddress) preparationLogger.info('stream_cache status=stored success=%{public}s',
          String(CatPlaybackStreamCache.put(address.dataRoot, key, session.stream, revision)))
      } catch (_) { preparationLogger.warn('stream_cache status=write_failed') }
    }
    return session
  }

  /** Metadata only: never invokes play() or creates a player session. */
  async prepareResume(itemId: string, current: () => boolean = () => true): Promise<void> {
    if (!current()) return
    const restored = await this.getItem(itemId)
    if (!current() || restored === null) return
    const item = new PlaybackQueueItem()
    item.sourceId = this.getSourceId(); item.mediaId = restored.id; item.variantId = restored.variantId
    await this.prepareLivePlayback(item, current)
  }

  protected async rememberDetailRecovery(videoId: string): Promise<void> {
    try {
      const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
      const key = await this.snapshotKey(videoId)
      if (key.length > 0) CatPlaybackSnapshotStore.markRequiresLive(address.dataRoot, key)
    } catch (_) {}
  }

  protected async preferredVariant(itemId: string, video: CatVodVideo): Promise<string> {
    const current = await super.preferredVariant(itemId, video)
    if (current.length > 0) return current
    try {
      const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
      const key = await this.snapshotKey(video.id)
      return key.length > 0 ? CatPlaybackSnapshotStore.preferred(address.dataRoot, key, itemId) : ''
    } catch (_) { return '' }
  }

  protected async rememberVariant(item: PlaybackQueueItem, video: CatVodVideo, road: CatVodRoad): Promise<void> {
    await super.rememberVariant(item, video, road)
    const revision = CatPlaybackSnapshotStore.revision()
    try {
      const address = await CatNodeRuntime.ensure(this.nodeContext, this.nodeConfig.md5Url)
      const key = await this.snapshotKey(video.id)
      if (key.length > 0) CatPlaybackSnapshotStore.put(address.dataRoot, key, video, revision, item.mediaId, road.id)
    } catch (_) {}
  }
  // Search can use another directory without changing the saved home directory.
  searchClient(key: string, control: CatNodeRequestControl | null = null): CatNodeClient {
    return new CatNodeClient(this.nodeContext, key, this.nodeConfig.md5Url, '', control)
  }
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
