import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { DanmakuItem } from '../../models/DanmakuItem'
import { FileStore } from '../../store/FileStore'
import { DanmakuCacheIndexStore } from './DanmakuCacheIndexStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuCacheStore')

const DANMAKU_CACHE_VERSION = 1
const DANMAKU_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000

class DanmakuCacheEntry {
  c: string = ''
  t: number = 0
  color: string = '#FFFFFF'
  fs: number = 25
  type: number = 0
  source: string = 'DanDan'
}

class DanmakuCachePayload {
  version: number = DANMAKU_CACHE_VERSION
  episodeId: number = 0
  updatedAt: number = 0
  count: number = 0
  items: DanmakuCacheEntry[] = []
}

export class DanmakuCacheSummary {
  fileCount: number = 0
  totalBytes: number = 0
  expiredCount: number = 0
}

export class DanmakuCacheStore {
  private static instance: DanmakuCacheStore | null = null
  private readonly cacheDirName: string = 'danmaku_cache'
  private cacheIndexStore: DanmakuCacheIndexStore = DanmakuCacheIndexStore.getInstance()

  private constructor() {}

  static getInstance(): DanmakuCacheStore {
    if (DanmakuCacheStore.instance === null) {
      DanmakuCacheStore.instance = new DanmakuCacheStore()
    }
    return DanmakuCacheStore.instance
  }

  async get(episodeId: number, sourceId: number = -1, episodeUrl: string = ''): Promise<DanmakuItem[] | null> {
    if (episodeId <= 0) {
      return null
    }

    if (sourceId >= 0 && episodeUrl.length > 0) {
      const index = await this.cacheIndexStore.getCacheIndex(episodeId, sourceId, episodeUrl)
      if (index !== null) {
        const items = await this.readPhysicalCache(episodeId)
        if (items !== null) {
          return items
        }
        await this.cacheIndexStore.clearCacheIndex(episodeId, sourceId, episodeUrl)
        logger.info('缓存索引命中但物理文件无效，已清除索引: episodeId=%{public}d', episodeId)
      }
    }

    const items = await this.readPhysicalCache(episodeId)
    if (items !== null && sourceId >= 0 && episodeUrl.length > 0) {
      this.cacheIndexStore.saveCacheIndex(episodeId, sourceId, episodeUrl).catch((_err: Error) => {})
    }
    return items
  }

  async put(episodeId: number, items: DanmakuItem[], sourceId: number = -1, episodeUrl: string = ''): Promise<void> {
    if (episodeId <= 0 || items.length === 0) {
      return
    }

    try {
      const payload = new DanmakuCachePayload()
      payload.episodeId = episodeId
      payload.updatedAt = Date.now()
      payload.count = items.length
      payload.items = this.toCacheEntries(items)

      const path = this.getCachePath(episodeId)
      this.writeUtf8(path, JSON.stringify(payload))
      logger.info('写入弹幕磁盘缓存: episodeId=%{public}d, count=%{public}d', episodeId, items.length)
      if (sourceId >= 0 && episodeUrl.length > 0) {
        this.cacheIndexStore.saveCacheIndex(episodeId, sourceId, episodeUrl).catch((_err: Error) => {})
      }
    } catch (err) {
      logger.warn('写入弹幕磁盘缓存失败: episodeId=%{public}d, err=%{public}s',
        episodeId, err instanceof Error ? err.message : String(err))
    }
  }

  async delete(episodeId: number): Promise<void> {
    if (episodeId <= 0) {
      return
    }
    this.deleteByPath(this.getCachePath(episodeId))
  }

  async getSummary(): Promise<DanmakuCacheSummary> {
    const summary = new DanmakuCacheSummary()
    const dirPath = this.getCacheDirPath()
    try {
      if (!fs.accessSync(dirPath)) {
        return summary
      }
      const fileNames: string[] = fs.listFileSync(dirPath)
      for (let i = 0; i < fileNames.length; i++) {
        const fileName = fileNames[i]
        if (!fileName.endsWith('.json')) {
          continue
        }
        const filePath = `${dirPath}/${fileName}`
        const stat = fs.statSync(filePath)
        summary.fileCount += 1
        summary.totalBytes += stat.size
        try {
          const payload = JSON.parse(this.readUtf8(filePath)) as DanmakuCachePayload
          if (!this.isPayloadFresh(payload)) {
            summary.expiredCount += 1
          }
        } catch (_err) {
          summary.expiredCount += 1
        }
      }
    } catch (err) {
      logger.warn('统计弹幕缓存失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return summary
  }

  async clearAll(): Promise<void> {
    const dirPath = this.getCacheDirPath()
    try {
      if (!fs.accessSync(dirPath)) {
        return
      }
      const fileNames: string[] = fs.listFileSync(dirPath)
      for (let i = 0; i < fileNames.length; i++) {
        const filePath = `${dirPath}/${fileNames[i]}`
        try {
          fs.unlinkSync(filePath)
        } catch (_err) {
        }
      }
      logger.info('弹幕磁盘缓存已清理')
    } catch (err) {
      logger.warn('清理弹幕缓存失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  async clearExpired(): Promise<number> {
    const dirPath = this.getCacheDirPath()
    let removed = 0
    try {
      if (!fs.accessSync(dirPath)) {
        return removed
      }
      const fileNames: string[] = fs.listFileSync(dirPath)
      for (let i = 0; i < fileNames.length; i++) {
        const fileName = fileNames[i]
        if (!fileName.endsWith('.json')) {
          continue
        }
        const filePath = `${dirPath}/${fileName}`
        try {
          const payload = JSON.parse(this.readUtf8(filePath)) as DanmakuCachePayload
          if (!this.isPayloadFresh(payload)) {
            this.deleteByPath(filePath)
            removed++
          }
        } catch (_err) {
          this.deleteByPath(filePath)
          removed++
        }
      }
      logger.info('过期弹幕缓存已清理: count=%{public}d', removed)
    } catch (err) {
      logger.warn('清理过期弹幕缓存失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return removed
  }

  private async readPhysicalCache(episodeId: number): Promise<DanmakuItem[] | null> {
    const path = this.getCachePath(episodeId)
    try {
      if (!fs.accessSync(path)) {
        return null
      }

      const jsonStr = this.readUtf8(path)
      const payload = JSON.parse(jsonStr) as DanmakuCachePayload
      if (!this.isPayloadValid(payload, episodeId)) {
        this.deleteByPath(path)
        return null
      }

      const items: DanmakuItem[] = []
      const sourceItems = payload.items
      for (let i = 0; i < sourceItems.length; i++) {
        const entry = sourceItems[i]
        if (entry.c.length === 0 || entry.t < 0) {
          continue
        }
        items.push(new DanmakuItem(entry.c, entry.t, entry.color, entry.fs, entry.type, entry.source ?? 'DanDan'))
      }

      if (items.length === 0) {
        this.deleteByPath(path)
        return null
      }

      logger.info('命中弹幕磁盘缓存: episodeId=%{public}d, count=%{public}d', episodeId, items.length)
      return items
    } catch (err) {
      logger.warn('读取弹幕磁盘缓存失败: episodeId=%{public}d, err=%{public}s',
        episodeId, err instanceof Error ? err.message : String(err))
      this.deleteByPath(path)
      return null
    }
  }

  private toCacheEntries(items: DanmakuItem[]): DanmakuCacheEntry[] {
    const entries: DanmakuCacheEntry[] = []
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      const entry = new DanmakuCacheEntry()
      entry.c = item.content
      entry.t = item.timeMs
      entry.color = item.color
      entry.fs = item.fontSize
      entry.type = item.type
      entry.source = item.source
      entries.push(entry)
    }
    return entries
  }

  private isPayloadValid(payload: DanmakuCachePayload, episodeId: number): boolean {
    if (payload === null || payload === undefined) {
      return false
    }
    if (payload.version !== DANMAKU_CACHE_VERSION || payload.episodeId !== episodeId) {
      return false
    }
    if (!this.isPayloadFresh(payload)) {
      return false
    }
    if (payload.items === null || payload.items === undefined || payload.items.length === 0) {
      return false
    }
    return true
  }

  private isPayloadFresh(payload: DanmakuCachePayload): boolean {
    return payload !== null && payload !== undefined &&
      payload.updatedAt > 0 && Date.now() - payload.updatedAt <= DANMAKU_CACHE_TTL_MS
  }

  private readUtf8(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
    try {
      const stat = fs.statSync(path)
      const buf = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buf)
      const textDecoder = util.TextDecoder.create('utf-8')
      return textDecoder.decodeToString(new Uint8Array(buf))
    } finally {
      fs.closeSync(file)
    }
  }

  private writeUtf8(path: string, content: string): void {
    const dirPath = path.substring(0, path.lastIndexOf('/'))
    if (!fs.accessSync(dirPath)) {
      fs.mkdirSync(dirPath, true)
    }
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
    try {
      fs.writeSync(file.fd, content)
    } finally {
      fs.closeSync(file)
    }
  }

  private deleteByPath(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path)
      }
    } catch (_err) {
    }
  }

  private getCachePath(episodeId: number): string {
    return `${this.getCacheDirPath()}/${episodeId}.json`
  }

  private getCacheDirPath(): string {
    const cacheDir = FileStore.getInstance().getCacheDir()
    return `${cacheDir}/${this.cacheDirName}`
  }
}
