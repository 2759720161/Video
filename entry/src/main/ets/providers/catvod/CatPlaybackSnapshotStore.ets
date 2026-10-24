import { fileIo } from '@kit.CoreFileKit'
import { buffer } from '@kit.ArkTS'
import { CatVodVideo } from './CatVodModels'
import { CatArtwork } from './CatArtwork'

class PlaybackSnapshot {
  key: string = ''
  savedAt: number = 0
  detail: CatVodVideo | null = null
  variants: Record<string, string> = {}
  requiresLive: boolean = false
}

/** Private, bounded metadata snapshots. Resolved streams and native initialization are never persisted. */
export class CatPlaybackSnapshotStore {
  private static readonly TTL_MS: number = 30 * 60 * 1000
  private static readonly MAX_CHARS: number = 2 * 1024 * 1024
  private static epoch: number = 0

  static revision(): number { return CatPlaybackSnapshotStore.epoch }
  private static path(root: string): string { return root + '/playback-metadata.json' }

  private static poster(value: string): string {
    const protectedImage = value.match(/^http:\/\/127\.0\.0\.1:\d+\/__video_artwork\?url=([^&]+)$/)
    if (protectedImage !== null) {
      try {
        const original = decodeURIComponent(protectedImage[1])
        return CatArtwork.needsHeaders(original) ? original : ''
      } catch (_) { return '' }
    }
    return /^(?:js2p:|https?:\/\/(?:localhost|127\.|\[::1\]))/i.test(value) ? '' : value
  }

  private static read(root: string): PlaybackSnapshot[] {
    if (root.length === 0) return []
    try {
      const path = CatPlaybackSnapshotStore.path(root)
      if (!fileIo.accessSync(path) || fileIo.statSync(path).size > CatPlaybackSnapshotStore.MAX_CHARS * 4) return []
      const text = fileIo.readTextSync(path)
      if (text.length > CatPlaybackSnapshotStore.MAX_CHARS) return []
      const raw = JSON.parse(text) as PlaybackSnapshot[]
      if (!Array.isArray(raw)) return []
      return raw.slice(-6).filter((entry: PlaybackSnapshot) => entry !== null &&
        typeof entry === 'object' && typeof entry.key === 'string' && /^[a-f0-9]{64}$/.test(entry.key) &&
        Number.isFinite(entry.savedAt) && Date.now() >= entry.savedAt &&
        Date.now() - entry.savedAt < CatPlaybackSnapshotStore.TTL_MS &&
        CatPlaybackSnapshotStore.valid(entry.detail))
    } catch (_) { return [] }
  }

  private static valid(video: CatVodVideo | null): boolean {
    if (video === null || typeof video !== 'object' || Array.isArray(video) ||
      typeof video.id !== 'string' || typeof video.name !== 'string' || !video.name.trim() ||
      typeof video.poster !== 'string' || !Array.isArray(video.roads)) return false
    for (let i = 0; i < video.roads.length; i++) {
      const road = video.roads[i]
      if (road === null || typeof road !== 'object' || typeof road.id !== 'string' ||
        typeof road.name !== 'string' || typeof road.spiderKey !== 'string' || !Array.isArray(road.episodes)) return false
      for (let j = 0; j < road.episodes.length; j++) {
        const episode = road.episodes[j]
        if (episode === null || typeof episode !== 'object' || typeof episode.name !== 'string' ||
          typeof episode.url !== 'string' || episode.url.length === 0 || !Number.isSafeInteger(episode.occurrence)) return false
        // Local proxy URLs are tied to a dead runtime after process termination.
        if (/^(?:js2p:|https?:\/\/(?:localhost|127\.|\[::1\]))/i.test(episode.url)) return false
      }
    }
    return true
  }

  static get(root: string, key: string, videoId: string): CatVodVideo | null {
    const entry = CatPlaybackSnapshotStore.read(root).find((value: PlaybackSnapshot) => value.key === key)
    return entry?.detail?.id === videoId ? entry.detail : null
  }

  static preferred(root: string, key: string, mediaId: string): string {
    const entry = CatPlaybackSnapshotStore.read(root).find((value: PlaybackSnapshot) => value.key === key)
    const variants = entry?.variants
    if (variants === null || typeof variants !== 'object' || Array.isArray(variants)) return ''
    const value = variants[mediaId]
    return typeof value === 'string' ? value : ''
  }

  static requiresLive(root: string, key: string): boolean {
    return CatPlaybackSnapshotStore.read(root).find((entry: PlaybackSnapshot) => entry.key === key)?.requiresLive === true
  }

  static markRequiresLive(root: string, key: string): void {
    const entry = CatPlaybackSnapshotStore.read(root).find((value: PlaybackSnapshot) => value.key === key)
    if (entry?.detail !== null && entry?.detail !== undefined) {
      CatPlaybackSnapshotStore.put(root, key, entry.detail, CatPlaybackSnapshotStore.revision(), '', '', true)
    }
  }

  static put(root: string, key: string, video: CatVodVideo, revision: number,
    mediaId: string = '', variantId: string = '', requiresLive: boolean = false): boolean {
    if (!root || revision !== CatPlaybackSnapshotStore.epoch || !CatPlaybackSnapshotStore.valid(video)) return false
    try {
      const entries = CatPlaybackSnapshotStore.read(root)
      const previous = entries.find((value: PlaybackSnapshot) => value.key === key)
      // Recording a preference must not resurrect an expired disk snapshot from
      // an in-memory copy, or move metadata into a newly changed login profile.
      if (mediaId.length > 0 && previous === undefined) return false
      const entry = new PlaybackSnapshot(); entry.key = key
      const metadataOnly = mediaId.length > 0 || requiresLive
      entry.savedAt = metadataOnly && previous !== undefined ? previous.savedAt : Date.now()
      entry.requiresLive = requiresLive || previous?.requiresLive === true
      const metadata = metadataOnly && previous?.detail !== null && previous?.detail !== undefined ? previous.detail : video
      entry.detail = JSON.parse(JSON.stringify(metadata)) as CatVodVideo
      entry.detail.poster = CatPlaybackSnapshotStore.poster(metadata.poster)
      if (previous?.variants !== null && typeof previous?.variants === 'object' && !Array.isArray(previous.variants)) {
        entry.variants = previous.variants
      }
      if (mediaId.length > 0 && variantId.length > 0) entry.variants[mediaId] = variantId
      const keys = Object.keys(entry.variants)
      if (keys.length > 64) {
        const bounded: Record<string, string> = {}
        for (let i = keys.length - 64; i < keys.length; i++) bounded[keys[i]] = entry.variants[keys[i]]
        entry.variants = bounded
      }
      const retained = entries.filter((value: PlaybackSnapshot) => value.key !== key)
      retained.push(entry)
      while (retained.length > 1 && (retained.length > 6 || JSON.stringify(retained).length > CatPlaybackSnapshotStore.MAX_CHARS)) retained.shift()
      const text = JSON.stringify(retained)
      if (text.length > CatPlaybackSnapshotStore.MAX_CHARS) return false
      const path = CatPlaybackSnapshotStore.path(root)
      const temporary = path + '.pending'
      const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        if (fileIo.writeSync(file.fd, text, { encoding: 'utf-8' }) !== buffer.byteLength(text, 'utf-8')) throw new Error('缓存写入不完整')
      } finally { fileIo.closeSync(file) }
      fileIo.renameSync(temporary, path)
      return true
    } catch (_) { return false }
  }

  static invalidate(root: string): void {
    CatPlaybackSnapshotStore.epoch++
    if (!root) return
    try {
      const path = CatPlaybackSnapshotStore.path(root)
      if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
    } catch (_) {}
  }
}
