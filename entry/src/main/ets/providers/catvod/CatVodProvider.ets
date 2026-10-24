import type { MediaProvider } from '../base/MediaProvider'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaItem, MediaItemType } from '../../core/media/MediaItem'
import { MediaSection } from '../../core/media/MediaSection'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { ProviderHealth } from '../../core/media/ProviderHealth'
import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
import { PlaybackQueueGroup } from '../../core/playback/PlaybackQueueGroup'
import { PlaybackSession } from '../../core/playback/PlaybackSession'
import { PlaybackStream } from '../../core/playback/PlaybackStream'
import { PlaybackVariant } from '../../core/playback/PlaybackVariant'
import { PlaybackHistoryReporter } from '../../core/playback/PlaybackHistoryReporter'
import type { PlaybackReporter } from '../../core/playback/PlaybackReporter'
import { PlaybackHistoryStore } from '../../store/PlaybackHistoryStore'
import type { CatVodDataSource } from './CatVodModels'
import { CatVodEpisode, CatVodEpisodeIdentity, CatVodRoad, CatVodVideo } from './CatVodModels'
import { CatVodCodec } from './CatVodCodec'
import { CatVodClient } from './CatVodClient'
import { CatVodSourceConfig, CatVodSourceConfigCodec } from './CatVodSourceConfig'
import { CatPlaybackPreparationCache } from './CatPlaybackPreparationCache'
import { Logger } from '../../utils/Logger'

const preparationLogger = new Logger('CatPlaybackPrepare')

export class CatVodProvider implements MediaProvider {
  private source: MediaSourceInstance
  private client: CatVodDataSource
  private config: CatVodSourceConfig
  private preparedVideo: CatVodVideo | null = null
  private preparedItemId: string = ''
  private preparedAt: number = 0

  constructor(source: MediaSourceInstance, client: CatVodDataSource, config: CatVodSourceConfig) {
    this.source = source; this.client = client; this.config = config
  }

  static async fromSource(source: MediaSourceInstance): Promise<CatVodProvider> {
    const config = CatVodSourceConfigCodec.decode(source.configJson)
    if (config === null) throw new Error('猫源配置无效')
    return new CatVodProvider(source, new CatVodClient(config), config)
  }

  getSourceId(): string { return this.source.id }
  hasCapability(capability: ProviderCapability): boolean {
    return [ProviderCapability.HOME, ProviderCapability.BROWSE, ProviderCapability.SEARCH,
      ProviderCapability.DETAIL, ProviderCapability.RESUME, ProviderCapability.VARIANT, ProviderCapability.ARTWORK].includes(capability)
  }

  getClient(): CatVodDataSource { return this.client }
  protected async preparationScope(): Promise<Object> { return CatPlaybackPreparationCache.defaultScope }
  protected usesPreparationCache(): boolean { return false }

  protected preparationKey(mediaId: string): string {
    return JSON.stringify([this.source.id, this.source.providerType, this.source.configJson, this.source.updatedAt, mediaId])
  }

  async getDetail(videoId: string, forceRefresh: boolean = false,
    onStatus: (status: string) => void = () => {}, requireLive: boolean = false): Promise<CatVodVideo | null> {
    if (!this.usesPreparationCache()) return this.client.detail(videoId)
    const scope = await this.preparationScope()
    return CatPlaybackPreparationCache.detail(scope, this.preparationKey(videoId), videoId,
      (report: (status: string) => void) => this.loadDetail(videoId, forceRefresh, report, requireLive), forceRefresh,
      (status: string) => {
        preparationLogger.info('detail_prepare status=%{public}s', status)
        onStatus(status)
      }, requireLive)
  }

  protected async loadDetail(videoId: string, _force: boolean, _trace: (status: string) => void,
    _requireLive: boolean = false): Promise<CatVodVideo | null> {
    return this.client.detail(videoId)
  }

  protected async rememberDetailRecovery(_videoId: string): Promise<void> {}

  protected async preferredVariant(itemId: string, _video: CatVodVideo): Promise<string> {
    return CatPlaybackPreparationCache.preferredVariant(this.preparationKey(itemId))
  }

  protected async rememberVariant(item: PlaybackQueueItem, _video: CatVodVideo, road: CatVodRoad): Promise<void> {
    CatPlaybackPreparationCache.rememberVariant(this.preparationKey(item.mediaId), road.id)
  }

  static defaultRoad(video: CatVodVideo): CatVodRoad | null {
    // 与原包天堂采集的优先策略一致；名称匹配只决定默认线路，不用于分集对齐。
    return video.roads.find((road: CatVodRoad) => road.name.toLowerCase().includes('m3u8')) ?? video.roads[0] ?? null
  }

  async getHome(): Promise<MediaSection[]> {
    const section = new MediaSection()
    section.title = this.source.name
    section.items = (await this.client.page('', '', 1)).videos.map((video: CatVodVideo) => this.videoItem(video))
    return [section]
  }

  async getChildren(parentId: string): Promise<MediaItem[]> {
    if (parentId.startsWith('vod:')) {
      const video = await this.getDetail(parentId.substring(4))
      const road = video === null ? null : CatVodProvider.defaultRoad(video)
      return video === null || road === null ? [] : this.episodeItems(video, road.id)
    }
    if (parentId.startsWith('category:')) {
      const page = await this.client.page(parentId.substring(9), '', 1)
      return page.videos.map((video: CatVodVideo) => this.videoItem(video))
    }
    const categories = await this.client.categories()
    return categories.map((category): MediaItem => {
      const item = new MediaItem()
      item.sourceId = this.source.id; item.id = 'category:' + category.id; item.title = category.name
      item.type = MediaItemType.COLLECTION; item.browsable = true
      return item
    })
  }

  async search(keyword: string): Promise<MediaItem[]> {
    if (keyword.trim().length === 0) return []
    return (await this.client.page('', keyword, 1)).videos.map((video: CatVodVideo) => this.videoItem(video))
  }

  async getItem(itemId: string): Promise<MediaItem | null> {
    this.preparedVideo = null; this.preparedItemId = ''
    const identity = CatVodCodec.identity(itemId)
    if (identity === null) return null
    const video = await this.getDetail(identity.videoId)
    if (video === null) return null
    const preferred = await this.preferredVariant(itemId, video)
    const roads = video.roads.slice().sort((a: CatVodRoad, b: CatVodRoad): number =>
      a.id === preferred ? -1 : b.id === preferred ? 1 : 0)
    for (let i = 0; i < roads.length; i++) {
      const episode = CatVodCodec.findEpisode(roads[i], identity)
      if (episode !== null) {
        const item = this.episodeItem(video, roads[i], episode)
        if (!this.usesPreparationCache()) {
          this.preparedVideo = video; this.preparedItemId = item.id; this.preparedAt = Date.now()
        }
        return item
      }
    }
    return null
  }

  async getResumeItems(limit: number = 0): Promise<MediaItem[]> {
    const records = await new PlaybackHistoryStore().getAll()
    const result: MediaItem[] = []
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      if (record.sourceId !== this.source.id || CatVodCodec.identity(record.mediaId) === null ||
        (record.durationMs > 0 && record.positionMs / record.durationMs >= 0.995)) continue
      const item = new MediaItem()
      item.sourceId = this.source.id; item.id = record.mediaId; item.title = record.title
      item.subtitle = record.subtitle; item.poster = record.artwork; item.positionMs = record.positionMs
      item.durationMs = record.durationMs; item.playable = true; item.type = MediaItemType.EPISODE
      result.push(item)
      if (limit > 0 && result.length >= limit) break
    }
    return result
  }

  async testConnection(): Promise<ProviderHealth> {
    const health = new ProviderHealth()
    const started = Date.now()
    try {
      await this.client.categories()
      health.ok = true; health.message = '来源连接正常'
    } catch (err) { health.message = err instanceof Error ? err.message : '来源连接失败' }
    health.latencyMs = Date.now() - started
    return health
  }

  videoItem(video: CatVodVideo): MediaItem {
    const item = new MediaItem()
    item.sourceId = this.source.id; item.id = 'vod:' + video.id; item.title = video.name
    item.poster = video.poster; item.overview = video.overview; item.subtitle = video.remarks
    item.year = video.year; item.type = MediaItemType.SERIES; item.browsable = true
    return item
  }

  episodeItems(video: CatVodVideo, roadId: string): MediaItem[] {
    const road = video.roads.find((value: CatVodRoad) => value.id === roadId)
    return road === undefined ? [] : road.episodes.map((episode: CatVodEpisode) => this.episodeItem(video, road, episode))
  }

  async resolvePlayback(item: PlaybackQueueItem, forceFresh: boolean = false,
    preparedStream: PlaybackStream | null = null): Promise<PlaybackSession> {
    const identity = CatVodCodec.identity(item.mediaId)
    if (item.sourceId !== this.source.id || identity === null) throw new Error('媒体来源或分集标识无效')
    let cached = false
    let diskCached = false
    const age = Date.now() - this.preparedAt
    const prepared = !forceFresh && !this.usesPreparationCache() && this.preparedItemId === item.mediaId &&
      age >= 0 && age <= 10000 ? this.preparedVideo : null
    this.preparedVideo = null; this.preparedItemId = ''
    const video = prepared ?? await this.getDetail(identity.videoId, forceFresh, (status: string) => {
      if (status === 'hit' || status === 'disk_hit') cached = true
      if (status === 'disk_hit') diskCached = true
    })
    if (video === null) throw new Error('该作品已不可用')
    const eligible = video.roads.filter((road: CatVodRoad) => CatVodCodec.findEpisode(road, identity) !== null)
    let road = item.variantId.length > 0 ? eligible.find((value: CatVodRoad) => value.id === item.variantId) :
      eligible.find((value: CatVodRoad) => value.name.toLowerCase().includes('m3u8')) ?? eligible[0]
    if (road === undefined) {
      if (cached && !forceFresh) return this.resolvePlayback(item, true)
      throw new Error('所选线路已没有这一集，请重新选择线路')
    }
    let episode = CatVodCodec.findEpisode(road, identity)
    if (episode === null) throw new Error('该分集已不可用')
    const session = new PlaybackSession()
    session.media.sourceId = this.source.id; session.media.mediaId = item.mediaId
    try { session.stream = preparedStream ?? await this.resolveEpisode(road, episode) }
    catch (error) {
      const message = error instanceof Error ? error.message : ''
      const stale = /\b404\b|\b410\b|(?:resource|share|file|token).*(?:expired|not found|invalid)|(?:资源|分享|文件|分集).*(?:失效|过期|不存在)/i.test(message)
      const empty = /播放地址为空|(?:未返回|没有返回)(?:可播放|播放)地址|(?:playback|play|stream)\s*(?:url|address).*\bempty\b/i.test(message)
      if (cached && !forceFresh && (stale || (diskCached && empty))) {
        preparationLogger.info('detail_prepare status=retry_fresh')
        const failedVariant = road.id
        const recovered = await this.resolvePlayback(item, true)
        if (diskCached && empty && item.variantId === failedVariant) await this.rememberDetailRecovery(identity.videoId)
        return recovered
      }
      const fallback = this.usesPreparationCache() && item.allowVariantFallback && empty ?
        eligible.find((value: CatVodRoad) => value.id !== road?.id) : undefined
      const nextEpisode = fallback === undefined ? null : CatVodCodec.findEpisode(fallback, identity)
      if (fallback === undefined || nextEpisode === null) throw new Error(error instanceof Error ? error.message : '来源播放解析失败')
      preparationLogger.info('playback_recovery action=alternate_variant reason=empty_address')
      try { session.stream = await this.resolveEpisode(fallback, nextEpisode) }
      catch (nextError) {
        preparationLogger.warn('playback_recovery result=failed')
        throw new Error(nextError instanceof Error ? nextError.message : '来源播放解析失败')
      }
      road = fallback; episode = nextEpisode
      preparationLogger.info('playback_recovery result=resolved')
    }
    item.variantId = road.id
    item.variants = this.variants(video, identity)
    session.media.title = video.name; session.media.subtitle = episode.name; session.media.artwork = video.poster
    await this.rememberVariant(item, video, road)
    let position = PlaybackQueueItem.normalizePositionMs(item.positionMs)
    if (!item.startFromBeginning && position <= 0) {
      try { position = (await new PlaybackHistoryStore().get(this.source.id, item.mediaId))?.positionMs ?? 0 } catch (_) {}
    }
    session.startPositionMs = item.startFromBeginning ? 0 : PlaybackQueueItem.normalizePositionMs(position)
    session.durationMs = PlaybackQueueItem.normalizeDurationMs(item.durationMs)
    session.media.durationMs = session.durationMs
    session.contextJson = JSON.stringify({ videoId: video.id, roadId: road.id })
    session.episodeGroups = this.episodeGroups(video)
    return session
  }

  protected async resolveEpisode(_road: CatVodRoad, episode: CatVodEpisode): Promise<PlaybackStream> {
    if (!CatVodCodec.isPlayableUrl(episode.url)) throw new Error('该分集没有可直接播放的地址')
    const stream = new PlaybackStream()
    stream.url = episode.url; stream.userAgent = this.config.userAgent; stream.referer = this.config.referer
    return stream
  }

  async refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]> {
    if (session.media.sourceId !== this.source.id) return []
    const identity = CatVodCodec.identity(session.media.mediaId)
    if (identity === null) return []
    const video = await this.getDetail(identity.videoId)
    if (video === null) return session.queue
    const current = session.queue.find((item: PlaybackQueueItem) => item.mediaId === session.media.mediaId)
    const selectedId = current?.variantId ?? ''
    const road = selectedId.length > 0 ? video.roads.find((value: CatVodRoad) => value.id === selectedId) : video.roads[0]
    if (road === undefined || CatVodCodec.findEpisode(road, identity) === null) return session.queue
    return this.episodeItems(video, road.id).map((media: MediaItem): PlaybackQueueItem => {
      const item = new PlaybackQueueItem()
      item.sourceId = this.source.id; item.mediaId = media.id; item.title = video.name
      item.subtitle = media.subtitle; item.artwork = media.poster; item.variantId = road.id; item.variants = media.variants
      const old = session.queue.find((value: PlaybackQueueItem) => value.mediaId === item.mediaId)
      if (old !== undefined) { item.positionMs = old.positionMs; item.durationMs = old.durationMs }
      return item
    })
  }

  createReporterForSession(session: PlaybackSession): PlaybackReporter | null {
    return session.media.sourceId === this.source.id ? new PlaybackHistoryReporter(session.media) : null
  }

  private episodeGroups(video: CatVodVideo): PlaybackQueueGroup[] {
    return video.roads.map((road: CatVodRoad): PlaybackQueueGroup => {
      const group = new PlaybackQueueGroup()
      group.id = road.id; group.name = road.name
      group.items = this.episodeItems(video, road.id).map((media: MediaItem): PlaybackQueueItem => {
        const item = new PlaybackQueueItem()
        item.sourceId = this.source.id; item.mediaId = media.id; item.title = media.title
        item.subtitle = media.subtitle; item.artwork = media.poster
        item.variantId = road.id; item.variants = media.variants
        return item
      })
      return group
    })
  }

  private episodeItem(video: CatVodVideo, road: CatVodRoad, episode: CatVodEpisode): MediaItem {
    const item = new MediaItem()
    item.sourceId = this.source.id; item.id = CatVodCodec.episodeId(video.id, episode); item.title = video.name
    item.subtitle = episode.name; item.poster = video.poster; item.type = MediaItemType.EPISODE; item.playable = true
    item.variantId = road.id
    const identity = new CatVodEpisodeIdentity()
    identity.videoId = video.id; identity.name = episode.name; identity.occurrence = episode.occurrence
    item.variants = this.variants(video, identity)
    return item
  }

  private variants(video: CatVodVideo, identity: CatVodEpisodeIdentity): PlaybackVariant[] {
    return video.roads.filter((road: CatVodRoad) => CatVodCodec.findEpisode(road, identity) !== null)
      .map((road: CatVodRoad): PlaybackVariant => {
        const variant = new PlaybackVariant()
        variant.id = road.id; variant.name = road.name
        return variant
      })
  }
}
