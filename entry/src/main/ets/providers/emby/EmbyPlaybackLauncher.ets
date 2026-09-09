import { EmbyItem } from './EmbyModels'
import { MediaItem } from '../../core/media/MediaItem'
import { ProviderPlaybackLauncher } from '../../services/ProviderPlaybackLauncher'

export class EmbyPlaybackLauncher {
  static async open(uiContext: UIContext, sourceId: string, item: EmbyItem,
    items: EmbyItem[] = [item]): Promise<void> {
    const normalizedSourceId = EmbyPlaybackLauncher.normalizeText(sourceId)
    if (item === null || typeof item !== 'object' || Array.isArray(item) || normalizedSourceId.length === 0 ||
      EmbyPlaybackLauncher.normalizeText(item.id).length === 0) {
      throw new Error('媒体来源或媒体标识无效')
    }
    const media = EmbyPlaybackLauncher.toMediaItem(normalizedSourceId, item)
    const queue: MediaItem[] = []
    const sourceItems: EmbyItem[] = Array.isArray(items) ? items : []
    for (let i = 0; i < sourceItems.length; i++) {
      const value = sourceItems[i]
      if (value === null || typeof value !== 'object' || Array.isArray(value)) continue
      if (!value.isFolder && EmbyPlaybackLauncher.normalizeText(value.id).length > 0) {
        queue.push(EmbyPlaybackLauncher.toMediaItem(normalizedSourceId, value))
      }
    }
    await ProviderPlaybackLauncher.open(uiContext, media, queue)
  }

  private static toMediaItem(sourceId: string, item: EmbyItem): MediaItem {
    const media = new MediaItem()
    media.sourceId = EmbyPlaybackLauncher.normalizeText(sourceId)
    media.id = EmbyPlaybackLauncher.normalizeText(item.id)
    media.title = item.name
    media.subtitle = item.subtitle()
    media.positionMs = item.resumePositionMs()
    media.durationMs = item.durationMs()
    media.playable = !item.isFolder
    return media
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
