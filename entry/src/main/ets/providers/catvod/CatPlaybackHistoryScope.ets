import { CatVodCodec } from './CatVodCodec'

/** Subscription ID isolates accounts; the encoded catalog key isolates sites within a subscription. */
export class CatPlaybackHistoryScope {
  static matches(mediaId: string, key: string, legacyKey: string = ''): boolean {
    if (key.length === 0) return true
    const identity = CatVodCodec.identity(mediaId)
    if (identity === null) return false
    if (!identity.videoId.startsWith('catnode:')) return legacyKey.length > 0 && legacyKey === key
    const parts = identity.videoId.split(':')
    if (parts.length !== 3) return false
    try { return decodeURIComponent(parts[1]) === key } catch (_) { return false }
  }
}
