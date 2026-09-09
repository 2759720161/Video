import type { PlaybackResolver } from './PlaybackResolver'
import type { PlaybackQueueItem } from './PlaybackQueueItem'
import type { PlaybackSession } from './PlaybackSession'
import type { PlaybackReporter } from './PlaybackReporter'
import type { MediaProvider } from '../../providers/base/MediaProvider'

/** 将 Provider 的播放能力适配为会话管理器需要的 Resolver，避免页面承担类型桥接。 */
export class ProviderPlaybackResolver implements PlaybackResolver {
  private provider: MediaProvider

  constructor(provider: MediaProvider) { this.provider = provider }

  async resolve(item: PlaybackQueueItem): Promise<PlaybackSession> {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error('播放队列项无效')
    }
    const session = await this.provider.resolve(item)
    if (session === null || typeof session !== 'object' || Array.isArray(session) ||
      session.media === null || typeof session.media !== 'object' || Array.isArray(session.media) ||
      session.stream === null || typeof session.stream !== 'object' || Array.isArray(session.stream)) {
      throw new Error('Provider 返回的播放会话无效')
    }
    const sessionSourceId = ProviderPlaybackResolver.normalizeText(session.media.sourceId)
    const sessionMediaId = ProviderPlaybackResolver.normalizeText(session.media.mediaId)
    const itemSourceId = ProviderPlaybackResolver.normalizeText(item.sourceId)
    const itemMediaId = ProviderPlaybackResolver.normalizeText(item.mediaId)
    if (sessionSourceId !== itemSourceId || sessionMediaId !== itemMediaId) {
      throw new Error('Provider 返回的播放会话身份不匹配')
    }
    return session
  }

  async refreshQueue(session: PlaybackSession): Promise<PlaybackQueueItem[]> {
    const queue = await this.provider.refreshQueue(session)
    const sourceId = ProviderPlaybackResolver.normalizeText(session.media.sourceId)
    const currentMediaId = ProviderPlaybackResolver.normalizeText(session.media.mediaId)
    const filtered: PlaybackQueueItem[] = []
    const seen: Record<string, boolean> = {}
    const sourceQueue: PlaybackQueueItem[] = Array.isArray(queue) ? queue : []
    for (let i = 0; i < sourceQueue.length; i++) {
      const item = sourceQueue[i]
      if (item === null || typeof item !== 'object' || Array.isArray(item)) continue
      const itemSourceId = ProviderPlaybackResolver.normalizeText(item.sourceId)
      const itemMediaId = ProviderPlaybackResolver.normalizeText(item.mediaId)
      if (itemSourceId !== sourceId || itemMediaId.length === 0 || seen[itemMediaId] === true) continue
      item.sourceId = sourceId
      item.mediaId = itemMediaId
      seen[itemMediaId] = true
      filtered.push(item)
    }
    if (filtered.findIndex((item: PlaybackQueueItem) => item.mediaId === currentMediaId) < 0) {
      return this.sanitizeFallbackQueue(session.queue, sourceId)
    }
    return filtered
  }

  createReporterForSession(session: PlaybackSession): PlaybackReporter | null {
    return this.provider.createReporterForSession(session)
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private sanitizeFallbackQueue(queue: PlaybackQueueItem[], sourceId: string): PlaybackQueueItem[] {
    const result: PlaybackQueueItem[] = []
    const seen: Record<string, boolean> = {}
    const sourceQueue: PlaybackQueueItem[] = Array.isArray(queue) ? queue : []
    for (let i = 0; i < sourceQueue.length; i++) {
      const item = sourceQueue[i]
      if (item === null || typeof item !== 'object' || Array.isArray(item)) continue
      const itemSourceId = ProviderPlaybackResolver.normalizeText(item.sourceId)
      const itemMediaId = ProviderPlaybackResolver.normalizeText(item.mediaId)
      if (itemSourceId !== sourceId || itemMediaId.length === 0 || seen[itemMediaId] === true) continue
      item.sourceId = sourceId
      item.mediaId = itemMediaId
      seen[itemMediaId] = true
      result.push(item)
    }
    return result
  }
}
