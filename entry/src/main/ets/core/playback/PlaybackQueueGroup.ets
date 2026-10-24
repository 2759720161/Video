import { PlaybackQueueItem } from './PlaybackQueueItem'

/** Provider-supplied episode groups; the player never parses source-specific context. */
export class PlaybackQueueGroup {
  id: string = ''
  name: string = ''
  items: PlaybackQueueItem[] = []
}
