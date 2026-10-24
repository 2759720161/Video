import { fileIo } from '@kit.CoreFileKit'
import { buffer } from '@kit.ArkTS'
import { PlaybackStream } from '../../core/playback/PlaybackStream'
import { CatStreamCachePolicy } from './CatStreamCachePolicy'

class StreamEntry {
  key: string = ''
  savedAt: number = 0
  validUntil: number = 0
  stream: PlaybackStream = new PlaybackStream()
  sourceProxyPath: string = ''
}

/** Private per-subscription file; URLs and credentials must never be logged. */
export class CatPlaybackStreamCache {
  private static readonly MAX_CHARS: number = 512 * 1024
  private static epoch: number = 0
  static revision(): number { return CatPlaybackStreamCache.epoch }
  private static path(root: string): string { return root + '/playback-streams.json' }

  private static read(root: string): StreamEntry[] {
    if (!root) return []
    try {
      const path = CatPlaybackStreamCache.path(root)
      if (!fileIo.accessSync(path) || fileIo.statSync(path).size > CatPlaybackStreamCache.MAX_CHARS * 4) return []
      const text = fileIo.readTextSync(path)
      if (text.length > CatPlaybackStreamCache.MAX_CHARS) return []
      const entries = JSON.parse(text) as StreamEntry[]
      if (!Array.isArray(entries)) return []
      return entries.slice(-12).filter((entry: StreamEntry): boolean => entry !== null && typeof entry === 'object' &&
        typeof entry.key === 'string' && /^[a-f0-9]{64}$/.test(entry.key) &&
        Number.isFinite(entry.savedAt) && Date.now() >= entry.savedAt && Number.isFinite(entry.validUntil) &&
        entry.validUntil <= entry.savedAt + CatStreamCachePolicy.MAX_TTL_MS && Date.now() + 30000 < entry.validUntil &&
        entry.stream !== null && typeof entry.stream === 'object' && typeof entry.stream.url === 'string' &&
        CatStreamCachePolicy.remote(entry.stream.url) && CatStreamCachePolicy.headers(entry.stream.headers) !== null &&
        typeof entry.stream.referer === 'string' && typeof entry.stream.userAgent === 'string' &&
        !/[\r\n]/.test(entry.stream.referer + entry.stream.userAgent))
    } catch (_) { return [] }
  }

  private static write(root: string, entries: StreamEntry[]): boolean {
    try {
      while (entries.length > 1 && (entries.length > 12 || JSON.stringify(entries).length > CatPlaybackStreamCache.MAX_CHARS)) entries.shift()
      const text = JSON.stringify(entries)
      if (text.length > CatPlaybackStreamCache.MAX_CHARS) return false
      const path = CatPlaybackStreamCache.path(root); const temporary = path + '.pending'
      const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        if (fileIo.writeSync(file.fd, text, { encoding: 'utf-8' }) !== buffer.byteLength(text, 'utf-8')) return false
      } finally { fileIo.closeSync(file) }
      fileIo.renameSync(temporary, path); return true
    } catch (_) { return false }
  }

  static get(root: string, key: string, proxyBase: string = ''): PlaybackStream | null {
    const entry = CatPlaybackStreamCache.read(root).find((value: StreamEntry) => value.key === key)
    if (entry === undefined) return null
    const stream = CatStreamCachePolicy.copy(entry.stream)
    stream.expiresAt = entry.validUntil; stream.reused = true
    if (proxyBase.length > 0) return CatStreamCachePolicy.restoreProxy(stream, entry.sourceProxyPath, proxyBase)
    return stream
  }

  static put(root: string, key: string, stream: PlaybackStream, revision: number): boolean {
    if (!root || revision !== CatPlaybackStreamCache.epoch || !/^[a-f0-9]{64}$/.test(key)) return false
    const reusable = CatStreamCachePolicy.reusable(stream)
    if (reusable === null) return false
    const entry = new StreamEntry(); entry.key = key; entry.savedAt = Date.now()
    entry.validUntil = CatStreamCachePolicy.validUntil(reusable, entry.savedAt); entry.stream = reusable
    entry.sourceProxyPath = CatStreamCachePolicy.sourceProxyPath(stream)
    if (entry.validUntil <= entry.savedAt + 30000) return false
    const entries = CatPlaybackStreamCache.read(root).filter((value: StreamEntry) => value.key !== key)
    entries.push(entry); return CatPlaybackStreamCache.write(root, entries)
  }

  static drop(root: string, key: string): void {
    if (!root) return
    CatPlaybackStreamCache.epoch++
    CatPlaybackStreamCache.write(root, CatPlaybackStreamCache.read(root).filter((entry: StreamEntry) => entry.key !== key))
  }

  static invalidate(root: string): void {
    CatPlaybackStreamCache.epoch++
    if (!root) return
    try { const path = CatPlaybackStreamCache.path(root); if (fileIo.accessSync(path)) fileIo.unlinkSync(path) } catch (_) {}
  }
}
