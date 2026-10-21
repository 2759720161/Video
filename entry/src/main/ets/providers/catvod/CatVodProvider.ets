import type { MediaProvider } from '../base/MediaProvider'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaItem, MediaItemType } from '../../core/media/MediaItem'
import { MediaSection } from '../../core/media/MediaSection'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'
import { ProviderHealth } from '../../core/media/ProviderHealth'
import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'
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

export class CatVodProvider implements MediaProvider {
  private source: MediaSourceInstance
  private client: CatVodDataSource
  private config: CatVodSourceConfig

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
  getDetail(videoId: string): Promise<CatVodVideo | null> { return this.client.detail(videoId) }

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
      const video = await this.client.detail(parentId.substring(4))
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
    const identity = CatVodCodec.identity(itemId)
    if (identity === null) return null
    const video = await this.client.detail(identity.videoId)
    if (video === null) return null
    for (let i = 0; i < video.roads.length; i++) {
      const episode = CatVodCodec.findEpisode(video.roads[i], identity)
      if (episode !== null) return this.episodeItem(video, video.roads[i], episode)
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

  async resolvePlayback(item: PlaybackQueueItem): Promise<PlaybackSession> {
    const identity = CatVodCodec.identity(item.mediaId)
    if (item.sourceId !== this.source.id || identity === null) throw new Error('媒体来源或分集标识无效')
    const video = await this.client.detail(identity.videoId)
    if (video === null) throw new Error('该作品已不可用')
    const eligible = video.roads.filter((road: CatVodRoad) => CatVodCodec.findEpisode(road, identity) !== null)
    const road = item.variantId.length > 0 ? eligible.find((value: CatVodRoad) => value.id === item.variantId) :
      eligible.find((value: CatVodRoad) => value.name.toLowerCase().includes('m3u8')) ?? eligible[0]
    if (road === undefined) throw new Error('所选线路已没有这一集，请重新选择线路')
    const episode = CatVodCodec.findEpisode(road, identity)
    if (episode === null) throw new Error('该分集已不可用')
    item.variantId = road.id
    item.variants = this.variants(video, identity)
    const session = new PlaybackSession()
    session.media.sourceId = this.source.id; session.media.mediaId = item.mediaId
    session.media.title = video.name; session.media.subtitle = episode.name; session.media.artwork = video.poster
    session.stream = await this.resolveEpisode(road, episode)
    let position = PlaybackQueueItem.normalizePositionMs(item.positionMs)
    if (!item.startFromBeginning && position <= 0) {
      try { position = (await new PlaybackHistoryStore().get(this.source.id, item.mediaId))?.positionMs ?? 0 } catch (_) {}
    }
    session.startPositionMs = item.startFromBeginning ? 0 : PlaybackQueueItem.normalizePositionMs(position)
    session.durationMs = PlaybackQueueItem.normalizeDurationMs(item.durationMs)
    session.media.durationMs = session.durationMs
    session.contextJson = JSON.stringify({ videoId: video.id, roadId: road.id })
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
    const video = await this.client.detail(identity.videoId)
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
