import { PlaybackSession } from '../core/playback/PlaybackSession'
import { PlaybackQueueItem } from '../core/playback/PlaybackQueueItem'
import { PlaybackSubtitle } from '../core/playback/PlaybackSubtitle'
import type { PlaybackReporter } from '../core/playback/PlaybackReporter'
import type { PlaybackResolver } from '../core/playback/PlaybackResolver'
import { PlaybackReportController } from '../core/playback/PlaybackReportController'

/**
 * 只管理进程内的启动会话和对应 reporter，不承担 Now Playing 或媒体控制。
 * PiP 接管期间保留会话；最终播放所有者退出后调用 release。
 */
export class PlaybackSessionManager {
  private static instance: PlaybackSessionManager | null = null
  private sessions: Map<string, PlaybackSession> = new Map()
  private reporters: Map<string, PlaybackReporter> = new Map()
  private nextId: number = 0
  private resolvers: Map<string, PlaybackResolver> = new Map()
  private reportControllers: Map<string, PlaybackReportController> = new Map()

  private constructor() {}

  static getInstance(): PlaybackSessionManager {
    if (PlaybackSessionManager.instance === null) {
      PlaybackSessionManager.instance = new PlaybackSessionManager()
    }
    return PlaybackSessionManager.instance
  }

  /** 注册一次；重复 ID 不能覆盖另一段播放及其 reporter。 */
  create(session: PlaybackSession, reporter?: PlaybackReporter, resolver?: PlaybackResolver): string {
    PlaybackSessionManager.normalizeSession(session)
    const requestedId = PlaybackSessionManager.trimString(session.id)
    const id = requestedId.length > 0 ? requestedId : this.createId()
    if (this.sessions.has(id)) {
      throw new Error('Playback session already exists: ' + id)
    }
    session.id = id
    this.sessions.set(id, session)
    if (reporter !== undefined) {
      this.reporters.set(id, reporter)
      this.reportControllers.set(id, new PlaybackReportController(reporter))
    }
    if (resolver !== undefined) this.resolvers.set(id, resolver)
    return id
  }

  /** 返回活动会话引用；更新流、队列或进度后调用 update。 */
  get(sessionId: string): PlaybackSession | null {
    return this.sessions.get(PlaybackSessionManager.trimString(sessionId)) ?? null
  }

  getReporter(sessionId: string): PlaybackReporter | null {
    return this.reporters.get(PlaybackSessionManager.trimString(sessionId)) ?? null
  }

  getResolver(sessionId: string): PlaybackResolver | null {
    return this.resolvers.get(PlaybackSessionManager.trimString(sessionId)) ?? null
  }

  getReportController(sessionId: string): PlaybackReportController | null {
    return this.reportControllers.get(PlaybackSessionManager.trimString(sessionId)) ?? null
  }

  /** 切换队列媒体时替换独立的来源上报器，旧 controller 必须已完成 stopped。 */
  replaceReporter(sessionId: string, reporter: PlaybackReporter | null): void {
    const id = PlaybackSessionManager.trimString(sessionId)
    if (!this.sessions.has(id)) throw new Error('Playback session is not active: ' + id)
    if (reporter === null) {
      this.reporters.delete(id)
      this.reportControllers.delete(id)
      return
    }
    this.reporters.set(id, reporter)
    this.reportControllers.set(id, new PlaybackReportController(reporter))
  }

  /** 不允许迟到的异步更新复活已释放的会话。 */
  update(session: PlaybackSession): void {
    PlaybackSessionManager.normalizeSession(session)
    session.id = PlaybackSessionManager.trimString(session.id)
    if (session.id.length === 0) throw new Error('Playback session ID cannot be empty')
    if (!this.sessions.has(session.id)) {
      throw new Error('Playback session is not active: ' + session.id)
    }
    this.sessions.set(session.id, session)
  }

  /** 幂等释放；调用方应先完成 stopped 上报。 */
  release(sessionId: string): void {
    const normalizedId = PlaybackSessionManager.trimString(sessionId)
    this.sessions.delete(normalizedId)
    this.reporters.delete(normalizedId)
    this.resolvers.delete(normalizedId)
    this.reportControllers.delete(normalizedId)
  }

  private createId(): string {
    let id: string = ''
    do {
      this.nextId += 1
      id = 'play_' + Date.now() + '_' + this.nextId
    } while (this.sessions.has(id))
    return id
  }

  /** Provider 输出进入全局会话表前统一验证公共身份，避免无效会话污染播控状态。 */
  private static normalizeSession(session: PlaybackSession): void {
    if (session === null || typeof session !== 'object' || Array.isArray(session) ||
      session.media === null || typeof session.media !== 'object' || Array.isArray(session.media) ||
      session.stream === null || typeof session.stream !== 'object' || Array.isArray(session.stream)) {
      throw new Error('Playback session structure is invalid')
    }
    session.media.sourceId = PlaybackSessionManager.trimString(session.media.sourceId)
    session.media.mediaId = PlaybackSessionManager.trimString(session.media.mediaId)
    session.media.title = PlaybackSessionManager.trimString(session.media.title)
    session.media.subtitle = PlaybackSessionManager.trimString(session.media.subtitle)
    session.media.artwork = PlaybackSessionManager.trimString(session.media.artwork)
    session.stream.url = PlaybackSessionManager.trimString(session.stream.url)
    if (session.media.sourceId.length === 0 || session.media.mediaId.length === 0) {
      throw new Error('Playback session media identity cannot be empty')
    }
    if (session.stream.url.length === 0) {
      throw new Error('Playback session stream URL cannot be empty')
    }
    PlaybackSessionManager.normalizeStream(session)
    session.media.durationMs = PlaybackSessionManager.normalizeDuration(session.media.durationMs)
    session.durationMs = PlaybackSessionManager.normalizeDuration(session.durationMs)
    if (session.durationMs <= 0 && session.media.durationMs > 0) {
      session.durationMs = session.media.durationMs
    }
    if (session.media.durationMs <= 0 && session.durationMs > 0) {
      session.media.durationMs = session.durationMs
    }
    session.startPositionMs = PlaybackSessionManager.normalizePosition(session.startPositionMs, session.durationMs)
    PlaybackSessionManager.normalizeQueue(session)
    PlaybackSessionManager.normalizeSubtitles(session)
  }

  /** 流元数据进入播放器前统一清理，避免请求头和临时地址状态跨层漂移。 */
  private static normalizeStream(session: PlaybackSession): void {
    const stream = session.stream
    const headers: Record<string, string> = {}
    const sourceHeaders = stream.headers as Record<string, Object>
    const keys = sourceHeaders !== null && typeof sourceHeaders === 'object' && !Array.isArray(sourceHeaders)
      ? Object.keys(sourceHeaders) : []
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim()
      const value = sourceHeaders[keys[i]]
      if (key.length > 0 && typeof value === 'string' && value.trim().length > 0) headers[key] = value.trim()
    }
    stream.headers = headers
    stream.referer = PlaybackSessionManager.trimString(stream.referer)
    stream.userAgent = PlaybackSessionManager.trimString(stream.userAgent)
    stream.proxy = PlaybackSessionManager.trimString(stream.proxy)
    stream.localFileSize = Number.isFinite(stream.localFileSize) && stream.localFileSize > 0
      ? Math.floor(stream.localFileSize) : 0
    stream.expiresAt = Number.isFinite(stream.expiresAt) && stream.expiresAt > 0
      ? Math.floor(stream.expiresAt) : 0
  }

  private static normalizeQueue(session: PlaybackSession): void {
    const queue: PlaybackQueueItem[] = []
    const seenMediaIds: Record<string, boolean> = {}
    let currentIndex = -1
    const sourceQueue: PlaybackQueueItem[] = Array.isArray(session.queue) ? session.queue : []
    for (let index = 0; index < sourceQueue.length; index++) {
      const item = sourceQueue[index]
      if (item === null || typeof item !== 'object' || Array.isArray(item)) continue
      item.sourceId = PlaybackSessionManager.trimString(item.sourceId)
      item.mediaId = PlaybackSessionManager.trimString(item.mediaId)
      if (item.sourceId !== session.media.sourceId || item.mediaId.length === 0 ||
        seenMediaIds[item.mediaId] === true) {
        continue
      }
      item.title = PlaybackSessionManager.trimString(item.title)
      item.subtitle = PlaybackSessionManager.trimString(item.subtitle)
      item.artwork = PlaybackSessionManager.trimString(item.artwork)
      item.variantId = PlaybackSessionManager.trimString(item.variantId)
      seenMediaIds[item.mediaId] = true
      item.durationMs = PlaybackSessionManager.normalizeDuration(item.durationMs)
      item.positionMs = PlaybackSessionManager.normalizePosition(item.positionMs, item.durationMs)
      if (item.sourceId === session.media.sourceId && item.mediaId === session.media.mediaId) {
        currentIndex = queue.length
      }
      queue.push(item)
    }
    session.queue = queue
    if (currentIndex < 0) {
      const current = new PlaybackQueueItem()
      current.sourceId = session.media.sourceId
      current.mediaId = session.media.mediaId
      current.title = session.media.title
      current.subtitle = session.media.subtitle
      current.artwork = session.media.artwork
      current.durationMs = session.durationMs
      current.positionMs = session.startPositionMs
      session.queue.push(current)
      currentIndex = session.queue.length - 1
    }
    session.queueIndex = currentIndex
    const current = session.queue[currentIndex]
    current.durationMs = session.durationMs > 0 ? session.durationMs : current.durationMs
    current.positionMs = PlaybackSessionManager.normalizePosition(session.startPositionMs, current.durationMs)
  }

  /** Provider 字幕进入公共会话前统一清理，避免空候选或空白请求头阻断后续候选。 */
  private static normalizeSubtitles(session: PlaybackSession): void {
    const subtitles: PlaybackSubtitle[] = []
    const sourceSubtitles: PlaybackSubtitle[] = Array.isArray(session.subtitles) ? session.subtitles : []
    for (let i = 0; i < sourceSubtitles.length; i++) {
      const subtitle = sourceSubtitles[i]
      if (subtitle === null || typeof subtitle !== 'object' || Array.isArray(subtitle)) continue
      subtitle.id = PlaybackSessionManager.trimString(subtitle.id)
      subtitle.displayName = PlaybackSessionManager.trimString(subtitle.displayName)
      subtitle.url = PlaybackSessionManager.trimString(subtitle.url)
      if (subtitle.url.length === 0) continue
      const headers: Record<string, string> = {}
      const sourceHeaders = subtitle.headers as Record<string, Object>
      const keys = sourceHeaders !== null && typeof sourceHeaders === 'object' && !Array.isArray(sourceHeaders)
        ? Object.keys(sourceHeaders) : []
      for (let j = 0; j < keys.length; j++) {
        const key = keys[j].trim()
        const value = sourceHeaders[keys[j]]
        if (key.length > 0 && typeof value === 'string' && value.trim().length > 0) headers[key] = value.trim()
      }
      subtitle.headers = headers
      subtitles.push(subtitle)
    }
    session.subtitles = subtitles
  }

  private static normalizeDuration(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0
  }

  private static normalizePosition(value: number, durationMs: number): number {
    const positionMs = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0
    return durationMs > 0 ? Math.min(positionMs, durationMs) : positionMs
  }

  private static trimString(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
