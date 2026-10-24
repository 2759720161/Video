import { common } from '@kit.AbilityKit'
import { MediaItem } from '../core/media/MediaItem'
import { PlaybackQueueItem } from '../core/playback/PlaybackQueueItem'
import { PlaybackSession } from '../core/playback/PlaybackSession'
import { PlaybackQueueGroup } from '../core/playback/PlaybackQueueGroup'
import { ProviderPlaybackResolver } from '../core/playback/ProviderPlaybackResolver'
import type { MediaProvider } from '../providers/base/MediaProvider'
import { ProviderRegistry } from '../providers/base/ProviderRegistry'
import { PlaybackSessionManager } from './PlaybackSessionManager'
import { Logger } from '../utils/Logger'

const logger = new Logger('ProviderPlaybackLaunch')

/** 通用来源播放入口：页面只提供 MediaItem，Provider 负责解析流和上报器。 */
export class ProviderPlaybackLauncher {
  static async open(uiContext: UIContext, item: MediaItem, items: MediaItem[] = [item],
    startFromBeginning: boolean = false): Promise<void> {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) throw new Error('媒体来源或媒体标识无效')
    const sourceId = ProviderPlaybackLauncher.normalizeText(item.sourceId)
    const mediaId = ProviderPlaybackLauncher.normalizeText(item.id)
    if (sourceId.length === 0 || mediaId.length === 0) throw new Error('媒体来源或媒体标识无效')
    const provider = await ProviderRegistry.get(sourceId,
      uiContext.getHostContext() as common.UIAbilityContext)
    if (provider === null) throw new Error('媒体源不可用或已停用')
    await ProviderPlaybackLauncher.openWithProvider(uiContext, provider, item, items, startFromBeginning)
  }

  /** 供本地临时文件等已持有 Provider 状态的入口复用统一会话启动流程。 */
  static async openWithProvider(uiContext: UIContext, provider: MediaProvider, item: MediaItem,
    items: MediaItem[] = [item], startFromBeginning: boolean = false, replace: boolean = false,
    canOpen: () => boolean = () => true, allowVariantFallback: boolean = false): Promise<void> {
    ProviderPlaybackLauncher.checkCurrent(canOpen)
    if (item === null || typeof item !== 'object' || Array.isArray(item)) throw new Error('媒体来源或媒体标识无效')
    const sourceId = ProviderPlaybackLauncher.normalizeText(item.sourceId)
    const mediaId = ProviderPlaybackLauncher.normalizeText(item.id)
    if (sourceId.length === 0 || mediaId.length === 0 || provider.getSourceId() !== sourceId) {
      throw new Error('媒体来源或媒体标识无效')
    }
    let queue = ProviderPlaybackLauncher.createQueue(sourceId, item, items, startFromBeginning)
    let index = queue.findIndex((value: PlaybackQueueItem) => value.mediaId === mediaId)
    const selected = queue[index >= 0 ? index : 0]
    selected.allowVariantFallback = allowVariantFallback
    const started = Date.now()
    logger.info('stage=resolve begin')
    const session = await provider.resolvePlayback(selected)
    logger.info('stage=resolve done elapsedMs=%{public}d', Date.now() - started)
    ProviderPlaybackLauncher.checkCurrent(canOpen)
    if (session === null || typeof session !== 'object' ||
      session.media === null || typeof session.media !== 'object' || Array.isArray(session.media) ||
      session.stream === null || typeof session.stream !== 'object' || Array.isArray(session.stream)) {
      throw new Error('Provider 返回的播放会话无效')
    }
    if (ProviderPlaybackLauncher.normalizeText(session.media.sourceId) !== sourceId ||
      ProviderPlaybackLauncher.normalizeText(session.media.mediaId) !== selected.mediaId) {
      throw new Error('Provider 返回的播放会话身份不匹配')
    }
    queue = ProviderPlaybackLauncher.preparedQueue(session, queue, selected)
    index = queue.findIndex((value: PlaybackQueueItem) => value.mediaId === mediaId)
    session.queue = queue
    session.queueIndex = index >= 0 ? index : 0
    const reporter = provider.createReporterForSession(session)
    const manager = PlaybackSessionManager.getInstance()
    const sessionId = manager.create(session, reporter === null ? undefined : reporter,
      new ProviderPlaybackResolver(provider))
    try {
      ProviderPlaybackLauncher.checkCurrent(canOpen)
      logger.info('stage=navigate begin')
      if (replace) {
        await uiContext.getRouter().replaceUrl({ url: 'pages/player/PlayerPage', params: ProviderPlaybackLauncher.routeParams(sessionId, selected) })
      } else {
        await uiContext.getRouter().pushUrl({ url: 'pages/player/PlayerPage', params: ProviderPlaybackLauncher.routeParams(sessionId, selected) })
      }
      logger.info('stage=navigate done')
    } catch (err) {
      manager.release(sessionId)
      throw new Error(err instanceof Error ? err.message : '打开播放页面失败')
    }
  }

  static async openById(uiContext: UIContext, sourceId: string, mediaId: string,
    positionMs: number = 0, startFromBeginning: boolean = false, canOpen: () => boolean = () => true): Promise<void> {
    const normalizedSourceId = ProviderPlaybackLauncher.normalizeText(sourceId)
    const normalizedMediaId = ProviderPlaybackLauncher.normalizeText(mediaId)
    if (normalizedSourceId.length === 0 || normalizedMediaId.length === 0) {
      throw new Error('媒体来源或媒体标识无效')
    }
    let stage = 'provider'
    const started = Date.now()
    try {
      ProviderPlaybackLauncher.checkCurrent(canOpen)
      logger.info('stage=provider begin')
      const provider = await ProviderRegistry.get(normalizedSourceId,
        uiContext.getHostContext() as common.UIAbilityContext)
      ProviderPlaybackLauncher.checkCurrent(canOpen)
      if (provider === null) throw new Error('媒体源不可用或已停用')
      logger.info('stage=provider done elapsedMs=%{public}d', Date.now() - started)
      stage = 'item'; logger.info('stage=item begin')
      const itemStarted = Date.now()
      const item = await provider.getItem(normalizedMediaId)
      ProviderPlaybackLauncher.checkCurrent(canOpen)
      if (item === null || !item.playable) throw new Error('历史媒体不存在或不可播放，请打开详情重新选择分集')
      logger.info('stage=item done elapsedMs=%{public}d', Date.now() - itemStarted)
      item.positionMs = PlaybackQueueItem.normalizePositionMs(positionMs)
      // Reuse the provider that prepared this history item and its scoped detail cache.
      stage = 'playback'
      await ProviderPlaybackLauncher.openWithProvider(uiContext, provider, item, [item], startFromBeginning, false, canOpen, true)
      logger.info('stage=history done elapsedMs=%{public}d', Date.now() - started)
    } catch (error) {
      logger.warn('history_open_failed stage=%{public}s elapsedMs=%{public}d current=%{public}s',
        stage, Date.now() - started, String(canOpen()))
      throw new Error(error instanceof Error ? error.message : '无法继续播放，请重试')
    }
  }

  private static preparedQueue(session: PlaybackSession, fallback: PlaybackQueueItem[],
    selected: PlaybackQueueItem): PlaybackQueueItem[] {
    if (!Array.isArray(session.episodeGroups)) return fallback
    const group = session.episodeGroups.find((value: PlaybackQueueGroup) => value !== null &&
      typeof value === 'object' && !Array.isArray(value) && value.id === selected.variantId)
    if (group === undefined || !Array.isArray(group.items)) return fallback
    const queue: PlaybackQueueItem[] = []
    const ids: Set<string> = new Set()
    for (let i = 0; i < group.items.length; i++) {
      const item = group.items[i]
      if (item === null || typeof item !== 'object' || Array.isArray(item) ||
        typeof item.mediaId !== 'string' || item.sourceId !== selected.sourceId || item.mediaId.trim().length === 0 ||
        item.variantId !== selected.variantId || ids.has(item.mediaId)) continue
      ids.add(item.mediaId)
      queue.push(item.mediaId === selected.mediaId ? selected : item)
    }
    return ids.has(selected.mediaId) ? queue : fallback
  }

  private static checkCurrent(canOpen: () => boolean): void {
    if (!canOpen()) throw new Error('播放准备已取消')
  }

  private static createQueue(sourceId: string, current: MediaItem, items: MediaItem[],
    startFromBeginning: boolean): PlaybackQueueItem[] {
    const queue: PlaybackQueueItem[] = []
    const ids: Record<string, boolean> = {}
    const currentId = ProviderPlaybackLauncher.normalizeText(current.id)
    const sourceItems: MediaItem[] = Array.isArray(items) ? items : []
    for (let i = 0; i < sourceItems.length; i++) {
      const value = sourceItems[i]
      if (value === null || typeof value !== 'object' || Array.isArray(value)) continue
      const valueId = ProviderPlaybackLauncher.normalizeText(value.id)
      if (!value.playable || ProviderPlaybackLauncher.normalizeText(value.sourceId) !== sourceId ||
        valueId.length === 0) continue
      const key = sourceId + '\u0000' + valueId
      if (ids[key] === true) continue
      ids[key] = true
      queue.push(ProviderPlaybackLauncher.toQueueItem(sourceId, valueId === currentId ? current : value,
        startFromBeginning && valueId === currentId))
    }
    if (queue.findIndex((value: PlaybackQueueItem) => value.mediaId === currentId) < 0) {
      queue.push(ProviderPlaybackLauncher.toQueueItem(sourceId, current, startFromBeginning))
    }
    return queue
  }

  private static toQueueItem(sourceId: string, item: MediaItem, startFromBeginning: boolean = false): PlaybackQueueItem {
    const queueItem = new PlaybackQueueItem()
    queueItem.sourceId = sourceId
    queueItem.mediaId = ProviderPlaybackLauncher.normalizeText(item.id)
    queueItem.title = ProviderPlaybackLauncher.normalizeText(item.title)
    queueItem.subtitle = ProviderPlaybackLauncher.normalizeText(item.subtitle)
    queueItem.artwork = ProviderPlaybackLauncher.normalizeText(item.poster)
    queueItem.artworkRef = ProviderPlaybackLauncher.normalizeText(item.artworkRef)
    queueItem.durationMs = PlaybackQueueItem.normalizeDurationMs(item.durationMs)
    const normalizedPositionMs = PlaybackQueueItem.normalizePositionMs(item.positionMs)
    queueItem.positionMs = queueItem.durationMs > 0
      ? Math.min(normalizedPositionMs, queueItem.durationMs) : normalizedPositionMs
    queueItem.variantId = ProviderPlaybackLauncher.normalizeText(item.variantId)
    queueItem.trackSelection = item.trackSelection
    for (let i = 0; i < item.variants.length; i++) {
      const variant = item.variants[i]
      if (variant !== null && typeof variant === 'object' && variant.id.trim().length > 0) {
        queueItem.variants.push(variant)
      }
    }
    queueItem.startFromBeginning = startFromBeginning
    return queueItem
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static routeParams(sessionId: string, item: PlaybackQueueItem): Record<string, Object> {
    return {
      'sessionId': sessionId,
      'sourceId': item.sourceId,
      'mediaId': item.mediaId,
      'variantId': item.variantId,
      'positionMs': item.positionMs
    }
  }
}
