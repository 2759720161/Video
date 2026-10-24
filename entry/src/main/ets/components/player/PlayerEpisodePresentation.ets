import { PlaybackQueueItem } from '../../core/playback/PlaybackQueueItem'

/** Presentation only: stable queue indices are never changed by sorting the panel. */
export class PlayerEpisodePresentation {
  static indices(length: number, reversed: boolean): number[] {
    const indices: number[] = []
    for (let i = 0; i < length; i++) indices.push(reversed ? length - 1 - i : i)
    return indices
  }

  static label(item: PlaybackQueueItem): string { return item.subtitle.trim() || item.title.trim() }

  static withVariant(item: PlaybackQueueItem, variantId: string, positionMs: number): PlaybackQueueItem {
    const copy = new PlaybackQueueItem()
    copy.sourceId = item.sourceId; copy.mediaId = item.mediaId; copy.title = item.title; copy.subtitle = item.subtitle
    copy.artwork = item.artwork; copy.artworkRef = item.artworkRef
    copy.positionMs = PlaybackQueueItem.normalizePositionMs(positionMs); copy.durationMs = item.durationMs
    copy.startFromBeginning = false; copy.variantId = variantId; copy.variants = item.variants.slice()
    copy.trackSelection = null
    return copy
  }
}
