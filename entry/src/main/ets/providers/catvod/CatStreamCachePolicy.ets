import { buffer } from '@kit.ArkTS'
import { PlaybackStream } from '../../core/playback/PlaybackStream'

/** Capability-based stream recovery; never reuses a dead localhost port. */
export class CatStreamCachePolicy {
  static readonly UNKNOWN_TTL_MS: number = 15 * 60 * 1000
  static readonly MAX_TTL_MS: number = 2 * 60 * 60 * 1000

  static remote(value: string): boolean {
    return /^https?:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(value) &&
      !/^https?:\/\/(?:localhost\b|127\.|\[::1\]|0\.0\.0\.0\b)/i.test(value) && !/[\r\n\\]/.test(value)
  }

  static headers(value: Object | undefined): Record<string, string> | null {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return null
    const raw = value as Record<string, Object>
    const keys = Object.keys(raw)
    if (keys.length > 64) return null
    const result: Record<string, string> = {}
    for (const key of keys) {
      const text = raw[key]
      if (typeof text !== 'string' || text.length > 32768 || /[\r\n]/.test(text) || !/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(key)) return null
      result[key] = text
    }
    return result
  }

  static copy(stream: PlaybackStream): PlaybackStream {
    const result = new PlaybackStream()
    result.url = stream.url; result.headers = JSON.parse(JSON.stringify(stream.headers)) as Record<string, string>
    result.referer = stream.referer; result.userAgent = stream.userAgent; result.expiresAt = stream.expiresAt
    result.audioTrackOrdinal = stream.audioTrackOrdinal; result.subtitleTrackOrdinal = stream.subtitleTrackOrdinal
    return result
  }

  static reusable(stream: PlaybackStream): PlaybackStream | null {
    if (stream.isLocalFile || stream.proxy.length > 0) return null
    let result = CatStreamCachePolicy.copy(stream)
    if (!CatStreamCachePolicy.remote(result.url)) {
      // Some source proxies serialize a complete upstream request in a pst ticket.
      // Recover that request, not the proxy's UUID or previous listening port.
      const ticket = result.url.match(/^http:\/\/127\.0\.0\.1:\d+\/[^#]*[?&]pst=([^&#]+)(?:&[^#]*)?$/)
      if (ticket === null || ticket[1].length > 128 * 1024) return null
      try {
        const encoded = decodeURIComponent(ticket[1]).replace(/-/g, '+').replace(/_/g, '/')
        const payload = JSON.parse(buffer.from(encoded, 'base64').toString('utf-8')) as Record<string, Object>
        if (payload === null || typeof payload !== 'object' || Array.isArray(payload) ||
          typeof payload['url'] !== 'string' || !CatStreamCachePolicy.remote(payload['url'] as string)) return null
        const headers = CatStreamCachePolicy.headers(payload['headers'])
        if (headers === null) return null
        result = new PlaybackStream(); result.url = payload['url'] as string; result.headers = headers
        result.expiresAt = stream.expiresAt
        result.audioTrackOrdinal = stream.audioTrackOrdinal; result.subtitleTrackOrdinal = stream.subtitleTrackOrdinal
        for (const name of Object.keys(headers)) {
          if (name.toLowerCase() === 'referer') result.referer = headers[name]
          if (name.toLowerCase() === 'user-agent') result.userAgent = headers[name]
        }
      } catch (_) { return null }
    }
    if (CatStreamCachePolicy.headers(result.headers) === null || /[\r\n]/.test(result.referer + result.userAgent)) return null
    return result
  }

  /** Keep only self-contained source proxy routes; no listening port is persisted. */
  static sourceProxyPath(stream: PlaybackStream): string {
    if (CatStreamCachePolicy.reusable(stream) === null) return ''
    const route = stream.url.match(/^http:\/\/127\.0\.0\.1:\d+(\/spider\/[^?#\s]+\/proxy\/[^?#\s]+\?pst=[^#\s]+)$/)
    return route !== null && !/[\\\r\n]/.test(route[1]) ? route[1] : ''
  }

  static restoreProxy(stream: PlaybackStream, path: string, base: string): PlaybackStream | null {
    if (!/^http:\/\/127\.0\.0\.1:[1-9]\d{0,4}$/.test(base) || Number(base.split(':')[2]) > 65535 ||
      typeof path !== 'string' || path.length > 192 * 1024) return null
    const local = new PlaybackStream()
    local.url = base + path
    if (CatStreamCachePolicy.sourceProxyPath(local) !== path) return null
    const upstream = CatStreamCachePolicy.reusable(local)
    if (upstream === null || upstream.url !== stream.url ||
      JSON.stringify(upstream.headers) !== JSON.stringify(stream.headers)) return null
    local.expiresAt = stream.expiresAt; local.reused = stream.reused
    local.audioTrackOrdinal = stream.audioTrackOrdinal; local.subtitleTrackOrdinal = stream.subtitleTrackOrdinal
    return local
  }

  static epoch(value: Object | undefined): number {
    const number = typeof value === 'number' || typeof value === 'string' ? Number(value) : 0
    if (!Number.isSafeInteger(number) || number < 1000000000) return 0
    return number < 100000000000 ? number * 1000 : number
  }

  static expires(raw: Record<string, Object>, url: string): number {
    const candidates = ['expiresAt', 'expireAt', 'expire_at', 'expires_at', 'expires']
      .map((key: string): number => CatStreamCachePolicy.epoch(raw[key])).filter((value: number): boolean => value > 0)
    const query = url.match(/[?&](?:Expires|expires|expire_at)=([0-9]+)(?:&|$)/)
    if (query !== null) {
      const timestamp = CatStreamCachePolicy.epoch(query[1])
      if (timestamp > 0) candidates.push(timestamp)
    }
    return candidates.length > 0 ? Math.min(...candidates) : 0
  }

  static validUntil(stream: PlaybackStream, now: number): number {
    const explicit = stream.expiresAt > 0 ? stream.expiresAt : CatStreamCachePolicy.expires({}, stream.url)
    return Math.min(now + CatStreamCachePolicy.MAX_TTL_MS, explicit > 0 ? explicit : now + CatStreamCachePolicy.UNKNOWN_TTL_MS)
  }
}
