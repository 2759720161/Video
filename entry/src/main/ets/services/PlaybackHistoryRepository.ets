import { common } from '@kit.AbilityKit'
import { LocalVideoRecord } from '../models/LocalVideoRecord'
import { PlaybackHistoryRecord } from '../models/PlaybackHistoryRecord'
import { PlaybackHistoryViewItem } from '../models/PlaybackHistoryViewItem'
import { LocalVideoHistoryStore } from '../store/LocalVideoHistoryStore'
import { PlaybackHistoryStore } from '../store/PlaybackHistoryStore'
import { LocalPlaybackIdentity } from '../providers/local/LocalPlaybackIdentity'
import { ArtworkResolver } from './ArtworkResolver'

/** 聚合本地扩展历史和统一来源历史，向页面提供稳定的展示模型。 */
export class PlaybackHistoryRepository {
  private readonly localStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private readonly remoteStore: PlaybackHistoryStore = new PlaybackHistoryStore()

  async getAll(): Promise<PlaybackHistoryViewItem[]> {
    const localRecords = await this.localStore.getAll()
    const remoteRecords = await this.remoteStore.getAll()
    const result: PlaybackHistoryViewItem[] = []
    const localKeys: Record<string, boolean> = {}
    for (let i = 0; i < localRecords.length; i++) {
      const item = this.fromLocal(localRecords[i])
      if (item.key.length === 0) continue
      localKeys[item.mediaId] = true
      result.push(item)
    }
    for (let i = 0; i < remoteRecords.length; i++) {
      const record = remoteRecords[i]
      if (record.sourceId === 'local' && localKeys[record.mediaId] === true) continue
      const item = this.fromRemote(record)
      if (item.key.length > 0) result.push(item)
    }
    result.sort((left: PlaybackHistoryViewItem, right: PlaybackHistoryViewItem) =>
      right.lastPlayedAt - left.lastPlayedAt)
    return result
  }

  async getContinueWatching(limit: number = 0): Promise<PlaybackHistoryViewItem[]> {
    const all = await this.getAll()
    const result: PlaybackHistoryViewItem[] = []
    for (let i = 0; i < all.length; i++) {
      if (all[i].completed) continue
      result.push(all[i])
      if (limit > 0 && result.length >= limit) break
    }
    return result
  }

  async delete(item: PlaybackHistoryViewItem): Promise<void> {
    if (item.localRecordId > 0) await this.localStore.deleteById(item.localRecordId)
    if (item.remoteRecordId > 0) await this.remoteStore.deleteById(item.remoteRecordId)
  }

  async clear(): Promise<void> {
    await this.localStore.clearAll()
    await this.remoteStore.clearAll()
  }

  /** 由稳定 ArtworkRef 解析本次运行时图片地址，解析失败保留占位图。 */
  async resolveArtwork(items: PlaybackHistoryViewItem[], context: common.UIAbilityContext | null): Promise<void> {
    if (!Array.isArray(items)) return
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.sourceId === 'local') {
        item.artworkUrl = item.artworkRef
        continue
      }
      if (item.artworkRef.length === 0 || context === null) continue
      try {
        item.artworkUrl = await ArtworkResolver.resolve(item.sourceId, item.mediaId, item.artworkRef, context)
      } catch (_) {
        item.artworkUrl = ''
      }
    }
  }

  private fromLocal(record: LocalVideoRecord): PlaybackHistoryViewItem {
    const item = new PlaybackHistoryViewItem()
    item.sourceId = 'local'
    item.mediaId = PlaybackHistoryRepository.text(record.fileKey)
    if (item.mediaId.length === 0) item.mediaId = LocalPlaybackIdentity.fromRecord(record)
    item.key = item.mediaId.length > 0 ? 'local:' + item.mediaId : ''
    item.title = PlaybackHistoryRepository.text(record.fileName)
    item.artworkRef = PlaybackHistoryRepository.text(record.coverUri)
    item.artworkUrl = item.artworkRef
    item.positionMs = PlaybackHistoryRepository.number(record.positionMs)
    item.durationMs = PlaybackHistoryRepository.number(record.durationMs)
    item.lastPlayedAt = PlaybackHistoryRepository.number(record.lastPlayedAt)
    item.localRecordId = record.id
    item.completed = PlaybackHistoryRepository.isCompleted(item.positionMs, item.durationMs)
    return item
  }

  private fromRemote(record: PlaybackHistoryRecord): PlaybackHistoryViewItem {
    const item = new PlaybackHistoryViewItem()
    item.sourceId = PlaybackHistoryRepository.text(record.sourceId)
    item.mediaId = PlaybackHistoryRepository.text(record.mediaId)
    item.key = item.sourceId.length > 0 && item.mediaId.length > 0
      ? item.sourceId + ':' + item.mediaId : ''
    item.title = PlaybackHistoryRepository.text(record.title)
    item.subtitle = PlaybackHistoryRepository.text(record.subtitle)
    item.artworkRef = PlaybackHistoryRepository.text(record.artworkRef).length > 0
      ? PlaybackHistoryRepository.text(record.artworkRef) : PlaybackHistoryRepository.text(record.artwork)
    item.positionMs = PlaybackHistoryRepository.number(record.positionMs)
    item.durationMs = PlaybackHistoryRepository.number(record.durationMs)
    item.lastPlayedAt = PlaybackHistoryRepository.number(record.lastPlayedAt)
    item.remoteRecordId = record.id
    item.completed = PlaybackHistoryRepository.isCompleted(item.positionMs, item.durationMs)
    return item
  }

  private static isCompleted(positionMs: number, durationMs: number): boolean {
    return durationMs > 0 && positionMs / durationMs >= 0.995
  }

  private static text(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static number(value: number): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0
  }
}
