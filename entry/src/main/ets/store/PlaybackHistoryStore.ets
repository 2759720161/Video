import { relationalStore } from '@kit.ArkData'
import { RdbManager } from './RdbManager'
import { RdbConstants } from '../constants/RdbConstants'
import { PlaybackHistoryRecord } from '../models/PlaybackHistoryRecord'
import { PlaybackHistoryChangeSignal } from './PlaybackHistoryChangeSignal'

/** 统一继续观看缓存；本地专属字幕和文件 URI 仍由 LocalVideoHistoryStore 管理。 */
export class PlaybackHistoryStore {
  private static mutationTail: Promise<void> = Promise.resolve()
  private rdbManager: RdbManager = RdbManager.getInstance()

  async getAll(): Promise<PlaybackHistoryRecord[]> {
    // External readers must observe all mutations submitted before the read.
    // Mutation code uses getAllInternal() to avoid waiting on its own queue.
    await PlaybackHistoryStore.mutationTail
    return this.getAllInternal()
  }

  private async getAllInternal(): Promise<PlaybackHistoryRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_PLAYBACK_HISTORY)
    predicates.orderByDesc(RdbConstants.COL_LAST_PLAYED_AT)
    return this.parse(await this.rdbManager.query(predicates))
  }

  async get(sourceId: string, mediaId: string): Promise<PlaybackHistoryRecord | null> {
    const normalizedSourceId = PlaybackHistoryStore.normalizeText(sourceId)
    const normalizedMediaId = PlaybackHistoryStore.normalizeText(mediaId)
    if (normalizedSourceId.length === 0 || normalizedMediaId.length === 0) return null
    await PlaybackHistoryStore.mutationTail
    return this.getInternal(normalizedSourceId, normalizedMediaId)
  }

  private async getInternal(sourceId: string, mediaId: string): Promise<PlaybackHistoryRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_PLAYBACK_HISTORY)
    predicates.equalTo(RdbConstants.COL_SOURCE_ID, sourceId)
    predicates.equalTo(RdbConstants.COL_MEDIA_ID, mediaId)
    const records = this.parse(await this.rdbManager.query(predicates))
    return records.length > 0 ? records[0] : null
  }

  async upsert(record: PlaybackHistoryRecord): Promise<number> {
    const snapshot = PlaybackHistoryStore.copyRecord(record)
    return PlaybackHistoryStore.enqueueMutation<number>(() => this.upsertInternal(snapshot))
  }

  private async upsertInternal(record: PlaybackHistoryRecord): Promise<number> {
    const sourceId = PlaybackHistoryStore.normalizeText(record.sourceId)
    const mediaId = PlaybackHistoryStore.normalizeText(record.mediaId)
    if (sourceId.length === 0 || mediaId.length === 0) return -1
    record.sourceId = sourceId
    record.mediaId = mediaId
    record.title = PlaybackHistoryStore.normalizeText(record.title)
    record.subtitle = PlaybackHistoryStore.normalizeText(record.subtitle)
    record.artwork = PlaybackHistoryStore.normalizeText(record.artwork)
    record.contextJson = PlaybackHistoryStore.normalizeText(record.contextJson)
    record.positionMs = Number.isFinite(record.positionMs) ? Math.max(0, Math.floor(record.positionMs)) : 0
    record.durationMs = Number.isFinite(record.durationMs) ? Math.max(0, Math.floor(record.durationMs)) : 0
    if (record.durationMs > 0) record.positionMs = Math.min(record.positionMs, record.durationMs)
    const now = Date.now()
    const values: relationalStore.ValuesBucket = {
      source_id: sourceId, media_id: mediaId, title: record.title,
      subtitle: record.subtitle, artwork: record.artwork, position_ms: record.positionMs,
      duration_ms: record.durationMs, last_played_at: now, context_json: record.contextJson,
      updated_at: now
    }
    const existing = await this.getInternal(sourceId, mediaId)
    if (existing !== null) {
      if (record.title.length === 0 && existing.title.length > 0) values.title = existing.title
      if (record.subtitle.length === 0 && existing.subtitle.length > 0) values.subtitle = existing.subtitle
      if (record.artwork.length === 0 && existing.artwork.length > 0) values.artwork = existing.artwork
      if (record.durationMs <= 0 && existing.durationMs > 0) {
        record.durationMs = existing.durationMs
        values.duration_ms = existing.durationMs
      }
      if (record.durationMs > 0) {
        record.positionMs = Math.min(record.positionMs, record.durationMs)
        values.position_ms = record.positionMs
      }
      if (record.contextJson.length === 0 && existing.contextJson.length > 0) {
        values.context_json = existing.contextJson
      }
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_PLAYBACK_HISTORY)
      predicates.equalTo(RdbConstants.COL_ID, existing.id)
      const rows = await this.rdbManager.update(RdbConstants.TABLE_PLAYBACK_HISTORY, values, predicates)
      if (rows > 0) PlaybackHistoryChangeSignal.notifyChanged()
      return rows
    }
    values.created_at = now
    const id = await this.rdbManager.insert(RdbConstants.TABLE_PLAYBACK_HISTORY, values)
    if (id > 0) PlaybackHistoryChangeSignal.notifyChanged()
    return id
  }

  async deleteById(id: number): Promise<number> {
    return PlaybackHistoryStore.enqueueMutation<number>(() => this.deleteByIdInternal(id))
  }

  private async deleteByIdInternal(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_PLAYBACK_HISTORY)
    predicates.equalTo(RdbConstants.COL_ID, id)
    const rows = await this.rdbManager.delete(predicates)
    if (rows > 0) PlaybackHistoryChangeSignal.notifyChanged()
    return rows
  }

  async deleteBySourceId(sourceId: string): Promise<number> {
    return PlaybackHistoryStore.enqueueMutation<number>(() => this.deleteBySourceIdInternal(sourceId))
  }

  private async deleteBySourceIdInternal(sourceId: string): Promise<number> {
    const normalizedSourceId = PlaybackHistoryStore.normalizeText(sourceId)
    if (normalizedSourceId.length === 0) return 0
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_PLAYBACK_HISTORY)
    predicates.equalTo(RdbConstants.COL_SOURCE_ID, normalizedSourceId)
    const rows = await this.rdbManager.delete(predicates)
    if (rows > 0) PlaybackHistoryChangeSignal.notifyChanged()
    return rows
  }

  async clearAll(): Promise<number> {
    return PlaybackHistoryStore.enqueueMutation<number>(() => this.clearAllInternal())
  }

  private async clearAllInternal(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_PLAYBACK_HISTORY)
    const rows = await this.rdbManager.delete(predicates)
    if (rows > 0) PlaybackHistoryChangeSignal.notifyChanged()
    return rows
  }

  /** 将历史表的读改写和删除串行化，避免并发上报互相覆盖。 */
  private static enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = PlaybackHistoryStore.mutationTail.then(operation, operation)
    PlaybackHistoryStore.mutationTail = result.then(() => {}, () => {})
    return result
  }

  private static copyRecord(record: PlaybackHistoryRecord): PlaybackHistoryRecord {
    const copy = new PlaybackHistoryRecord()
    copy.id = record.id
    copy.sourceId = record.sourceId
    copy.mediaId = record.mediaId
    copy.title = record.title
    copy.subtitle = record.subtitle
    copy.artwork = record.artwork
    copy.positionMs = record.positionMs
    copy.durationMs = record.durationMs
    copy.lastPlayedAt = record.lastPlayedAt
    copy.contextJson = record.contextJson
    copy.createdAt = record.createdAt
    copy.updatedAt = record.updatedAt
    return copy
  }

  private parse(resultSet: relationalStore.ResultSet): PlaybackHistoryRecord[] {
    const records: PlaybackHistoryRecord[] = []
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new PlaybackHistoryRecord()
          record.id = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_ID))
          record.sourceId = PlaybackHistoryStore.normalizeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_SOURCE_ID)))
          record.mediaId = PlaybackHistoryStore.normalizeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_MEDIA_ID)))
          record.title = PlaybackHistoryStore.normalizeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_TITLE)))
          record.subtitle = PlaybackHistoryStore.normalizeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_SUBTITLE)))
          record.artwork = PlaybackHistoryStore.normalizeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_ARTWORK)))
          const positionMs = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS))
          const durationMs = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS))
          const lastPlayedAt = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_LAST_PLAYED_AT))
          record.positionMs = Number.isFinite(positionMs) ? Math.max(0, positionMs) : 0
          record.durationMs = Number.isFinite(durationMs) && durationMs > 0 ? durationMs : 0
          if (record.durationMs > 0) record.positionMs = Math.min(record.positionMs, record.durationMs)
          record.lastPlayedAt = Number.isFinite(lastPlayedAt) && lastPlayedAt > 0 ? lastPlayedAt : 0
          record.contextJson = PlaybackHistoryStore.normalizeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_CONTEXT_JSON)))
          const createdAt = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_CREATED_AT))
          const updatedAt = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_UPDATED_AT))
          record.createdAt = Number.isFinite(createdAt) && createdAt > 0 ? createdAt : 0
          record.updatedAt = Number.isFinite(updatedAt) && updatedAt > 0 ? updatedAt : 0
          if (record.sourceId.length > 0 && record.mediaId.length > 0) {
            records.push(record)
          }
        } while (resultSet.goToNextRow())
      }
    } finally {
      resultSet.close()
    }
    return records
  }

  private readString(resultSet: relationalStore.ResultSet, index: number): string {
    try {
      const value = resultSet.getString(index)
      return typeof value === 'string' ? value : ''
    } catch (_) {
      return ''
    }
  }

  private readLong(resultSet: relationalStore.ResultSet, index: number): number {
    try {
      const value = resultSet.getLong(index)
      return Number.isFinite(value) ? value : 0
    } catch (_) {
      return 0
    }
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
