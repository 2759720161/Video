import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuCacheIndex')

export class DanmakuCacheIndexRecord {
  episodeId: number = 0
  sourceId: number = -1
  episodeUrlHash: string = ''
  updatedAt: number = 0
}

const CACHE_INDEX_KEY_PREFIX: string = 'dm_cache_bind_'
const CACHE_INDEX_INDEX_PREFIX: string = 'dm_cache_idx_'

function computeEpisodeUrlHash(value: string): string {
  let hash: number = 0
  for (let index = 0; index < value.length; index++) {
    hash = ((hash << 5) - hash + value.charCodeAt(index)) | 0
  }
  return String(value.length) + '_' + String(hash >>> 0)
}

export class DanmakuCacheIndexStore {
  private static instance: DanmakuCacheIndexStore | null = null

  private constructor() {}

  static getInstance(): DanmakuCacheIndexStore {
    if (DanmakuCacheIndexStore.instance === null) {
      DanmakuCacheIndexStore.instance = new DanmakuCacheIndexStore()
    }
    return DanmakuCacheIndexStore.instance
  }

  async getCacheIndex(episodeId: number, sourceId: number, episodeUrl: string): Promise<DanmakuCacheIndexRecord | null> {
    try {
      const key: string = this.buildCacheIndexKey(episodeId, sourceId, episodeUrl)
      const prefsKey: string = CACHE_INDEX_KEY_PREFIX + key
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const jsonStr: string = await prefs.getString(prefsKey, '')
      if (jsonStr.length === 0) {
        return null
      }
      return this.parseCacheIndexRecord(jsonStr)
    } catch (_err) {
      logger.warn('getCacheIndex failed: episodeId=%{public}d sourceId=%{public}d', episodeId, sourceId)
      return null
    }
  }

  async saveCacheIndex(episodeId: number, sourceId: number, episodeUrl: string): Promise<void> {
    try {
      const urlHash: string = computeEpisodeUrlHash(episodeUrl)
      const record: DanmakuCacheIndexRecord = new DanmakuCacheIndexRecord()
      record.episodeId = episodeId
      record.sourceId = sourceId
      record.episodeUrlHash = urlHash
      record.updatedAt = Date.now()
      const key: string = this.buildCacheIndexKey(episodeId, sourceId, episodeUrl)
      const prefsKey: string = CACHE_INDEX_KEY_PREFIX + key
      const jsonStr: string = JSON.stringify(record)
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      await prefs.setString(prefsKey, jsonStr)
      await this.addToCacheIndexIndex(sourceId, urlHash, key)
      logger.info('缓存索引保存: %{public}s', key)
    } catch (_err) {
      logger.warn('saveCacheIndex failed: episodeId=%{public}d sourceId=%{public}d', episodeId, sourceId)
    }
  }

  async clearCacheIndex(episodeId: number, sourceId: number, episodeUrl: string): Promise<boolean> {
    try {
      const key: string = this.buildCacheIndexKey(episodeId, sourceId, episodeUrl)
      const prefsKey: string = CACHE_INDEX_KEY_PREFIX + key
      const urlHash: string = computeEpisodeUrlHash(episodeUrl)
      await PreferencesStore.getInstance().delete(prefsKey)
      await this.removeFromCacheIndexIndex(sourceId, urlHash, key)
      logger.info('缓存索引清除: %{public}s', key)
      return true
    } catch (_err) {
      logger.warn('clearCacheIndex failed: episodeId=%{public}d sourceId=%{public}d', episodeId, sourceId)
      return false
    }
  }

  async clearCacheIndexByPlaybackRecord(sourceId: number, episodeUrl: string): Promise<void> {
    if (sourceId < 0 || episodeUrl.length === 0) {
      return
    }
    try {
      const urlHash: string = computeEpisodeUrlHash(episodeUrl)
      const indexKey: string = `${CACHE_INDEX_INDEX_PREFIX}${sourceId}_${urlHash}`
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const indexJson: string = await prefs.getString(indexKey, '')
      if (indexJson.length === 0) {
        logger.info('按播放记录清理缓存索引: 无索引记录 sourceId=%{public}d urlHash=%{public}s', sourceId, urlHash)
        return
      }
      const keys: string[] = this.parseIndexEntries(indexJson)
      let removedCount: number = 0
      for (let i = 0; i < keys.length; i++) {
        const prefsKey: string = CACHE_INDEX_KEY_PREFIX + keys[i]
        try {
          await prefs.delete(prefsKey)
          removedCount++
        } catch (_delErr) {
          logger.warn('删除缓存索引key失败: %{public}s', keys[i])
        }
      }
      await prefs.delete(indexKey)
      logger.info('按播放记录清理缓存索引: sourceId=%{public}d urlHash=%{public}s, removed=%{public}d',
        sourceId, urlHash, removedCount)
    } catch (_err) {
      logger.warn('clearCacheIndexByPlaybackRecord failed: sourceId=%{public}d', sourceId)
    }
  }

  private async addToCacheIndexIndex(sourceId: number, urlHash: string, cacheKey: string): Promise<void> {
    try {
      const indexKey: string = `${CACHE_INDEX_INDEX_PREFIX}${sourceId}_${urlHash}`
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const existingJson: string = await prefs.getString(indexKey, '')
      let keys: string[] = existingJson.length > 0 ? this.parseIndexEntries(existingJson) : []
      let alreadyExists: boolean = false
      for (let i = 0; i < keys.length; i++) {
        if (keys[i] === cacheKey) {
          alreadyExists = true
          break
        }
      }
      if (!alreadyExists) {
        keys.push(cacheKey)
        await prefs.setString(indexKey, JSON.stringify(keys))
      }
    } catch (_err) {
      logger.warn('addToCacheIndexIndex failed')
    }
  }

  private async removeFromCacheIndexIndex(sourceId: number, urlHash: string, cacheKey: string): Promise<void> {
    try {
      const indexKey: string = `${CACHE_INDEX_INDEX_PREFIX}${sourceId}_${urlHash}`
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const existingJson: string = await prefs.getString(indexKey, '')
      if (existingJson.length === 0) {
        return
      }
      let keys: string[] = this.parseIndexEntries(existingJson)
      let writeIndex = 0
      for (let i = 0; i < keys.length; i++) {
        if (keys[i] !== cacheKey) {
          if (writeIndex !== i) {
            keys[writeIndex] = keys[i]
          }
          writeIndex++
        }
      }
      if (writeIndex < keys.length) {
        keys.length = writeIndex
      }
      if (keys.length === 0) {
        await prefs.delete(indexKey)
      } else {
        await prefs.setString(indexKey, JSON.stringify(keys))
      }
    } catch (_err) {
      logger.warn('removeFromCacheIndexIndex failed')
    }
  }

  private parseIndexEntries(jsonStr: string): string[] {
    try {
      const arr: Object[] = JSON.parse(jsonStr) as Object[]
      const result: string[] = []
      for (let i = 0; i < arr.length; i++) {
        const item: string = arr[i] as string
        if (item.length > 0) {
          result.push(item)
        }
      }
      return result
    } catch (_err) {
      return []
    }
  }

  private buildCacheIndexKey(episodeId: number, sourceId: number, episodeUrl: string): string {
    const urlHash: string = computeEpisodeUrlHash(episodeUrl)
    return `${episodeId}_${sourceId}_${urlHash}`
  }

  private parseCacheIndexRecord(jsonStr: string): DanmakuCacheIndexRecord {
    const record: DanmakuCacheIndexRecord = new DanmakuCacheIndexRecord()
    try {
      const obj: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>
      if (obj['episodeId'] !== undefined && typeof obj['episodeId'] === 'number') {
        record.episodeId = obj['episodeId'] as number
      }
      if (obj['sourceId'] !== undefined && typeof obj['sourceId'] === 'number') {
        record.sourceId = obj['sourceId'] as number
      }
      if (obj['episodeUrlHash'] !== undefined && typeof obj['episodeUrlHash'] === 'string') {
        record.episodeUrlHash = obj['episodeUrlHash'] as string
      }
      if (obj['updatedAt'] !== undefined && typeof obj['updatedAt'] === 'number') {
        record.updatedAt = obj['updatedAt'] as number
      }
    } catch (_err) {
      logger.warn('parseCacheIndexRecord failed, using defaults')
    }
    return record
  }
}
