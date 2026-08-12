import { LocalVideoRecord } from './LocalVideoRecord'

/** Serializable route payload for a temporary local playback queue. */
export class PlaybackQueueItem {
  uri: string = ''
  name: string = ''
  size: number = 0
  positionMs: number = 0
  durationMs: number = 0

  static fromRecord(record: LocalVideoRecord): PlaybackQueueItem {
    const item = new PlaybackQueueItem()
    item.uri = record.fileUri
    item.name = record.fileName
    item.size = record.fileSize
    item.positionMs = record.positionMs
    item.durationMs = record.durationMs
    return item
  }
}

export namespace PlaybackQueueCodec {
  export function encode(records: LocalVideoRecord[]): string {
    const items: PlaybackQueueItem[] = []
    for (let i = 0; i < records.length; i++) {
      if (records[i].fileUri.length > 0) {
        items.push(PlaybackQueueItem.fromRecord(records[i]))
      }
    }
    return JSON.stringify(items)
  }

  export function decode(raw: string): PlaybackQueueItem[] {
    if (raw.length === 0) {
      return []
    }
    try {
      const values = JSON.parse(raw) as Array<Record<string, Object>>
      const items: PlaybackQueueItem[] = []
      for (let i = 0; i < values.length; i++) {
        const value = values[i]
        if (typeof value['uri'] !== 'string' || value['uri'].length === 0) {
          continue
        }
        const item = new PlaybackQueueItem()
        item.uri = value['uri'] as string
        item.name = typeof value['name'] === 'string' ? value['name'] as string : ''
        item.size = typeof value['size'] === 'number' ? value['size'] as number : 0
        item.positionMs = typeof value['positionMs'] === 'number' ? value['positionMs'] as number : 0
        item.durationMs = typeof value['durationMs'] === 'number' ? value['durationMs'] as number : 0
        items.push(item)
      }
      return items
    } catch (_err) {
      return []
    }
  }
}
