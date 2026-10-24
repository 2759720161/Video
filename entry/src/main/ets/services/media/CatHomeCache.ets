import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'
import { CatArtwork } from '../../providers/catvod/CatArtwork'
import { CatVodCategory, CatVodVideo } from '../../providers/catvod/CatVodModels'
import { CatVodCodec } from '../../providers/catvod/CatVodCodec'
import { PreferencesStore } from '../../store/PreferencesStore'

export class CatHomeSnapshot {
  key: string = ''
  savedAt: number = 0
  complete: boolean = true
  pageCount: number = 1
  siteKey: string = ''
  categoryId: string = ''
  sites: CatNodeSite[] = []
  categories: CatVodCategory[] = []
  videos: CatVodVideo[] = []
}

/** Bounded display-only snapshots. Source configuration is hashed; playback roads and site ext are excluded. */
export class CatHomeCache {
  static readonly FRESH_MS: number = 6 * 60 * 60 * 1000
  private static readonly RETAIN_MS: number = 7 * 24 * 60 * 60 * 1000
  private static readonly STORAGE_KEY: string = 'cat_home_cache_v1'
  private static readonly MAX_CHARS: number = 1024 * 1024
  private static tail: Promise<void> = Promise.resolve()

  static async identity(source: MediaSourceInstance, categoryId: string = ''): Promise<string> {
    const md = cryptoFramework.createMd('SHA256')
    // Keep the overview identity compatible with snapshots saved by earlier versions.
    const identity = categoryId.length === 0 ?
      JSON.stringify([source.id, source.providerType, source.updatedAt, source.configJson]) :
      JSON.stringify([source.id, source.providerType, source.updatedAt, source.configJson, 'category', categoryId])
    await md.update({ data: new util.TextEncoder('utf-8').encodeInto(
      identity) })
    const bytes = (await md.digest()).data
    let key = ''
    for (let i = 0; i < bytes.length; i++) key += bytes[i].toString(16).padStart(2, '0')
    return key
  }

  static fresh(snapshot: CatHomeSnapshot): boolean {
    return snapshot.complete && Date.now() - snapshot.savedAt < CatHomeCache.FRESH_MS
  }

  static async get(source: MediaSourceInstance, categoryId: string = ''): Promise<CatHomeSnapshot | null> {
    try {
      const key = await CatHomeCache.identity(source, categoryId)
      await CatHomeCache.tail
      return (await CatHomeCache.read()).find((value: CatHomeSnapshot) => value.key === key) ?? null
    } catch (_) { return null }
  }

  static async put(source: MediaSourceInstance, snapshot: CatHomeSnapshot): Promise<void> {
    // Capture before yielding: a later page/category mutation must not alter this write.
    const captured = CatHomeCache.decode(JSON.parse(JSON.stringify(snapshot)) as Object)
    if (captured === null) return
    const key = await CatHomeCache.identity(source, captured.categoryId)
    captured.key = key
    const task = CatHomeCache.tail.then(async () => {
      const entries = (await CatHomeCache.read()).filter((value: CatHomeSnapshot) => value.key !== key)
      entries.push(captured)
      while (entries.length > 1 && (entries.length > 8 || JSON.stringify(entries).length > CatHomeCache.MAX_CHARS)) {
        // Visiting many categories must not immediately evict the cold-start overview.
        const category = entries.findIndex((value: CatHomeSnapshot, index: number) =>
          index < entries.length - 1 && value.categoryId.length > 0)
        entries.splice(category >= 0 ? category : 0, 1)
      }
      const text = JSON.stringify(entries)
      if (text.length <= CatHomeCache.MAX_CHARS) await PreferencesStore.getInstance().setStringStrict(CatHomeCache.STORAGE_KEY, text)
    })
    CatHomeCache.tail = task.catch(() => {})
    await CatHomeCache.tail
  }

  private static async read(): Promise<CatHomeSnapshot[]> {
    const raw = await PreferencesStore.getInstance().getStringStrict(CatHomeCache.STORAGE_KEY, '[]')
    if (raw.length > CatHomeCache.MAX_CHARS) return []
    let values: Object
    try { values = JSON.parse(raw) as Object } catch (_) { return [] }
    if (!Array.isArray(values)) return []
    const result: CatHomeSnapshot[] = []
    for (const value of (values as Object[]).slice(-8)) {
      const snapshot = CatHomeCache.decode(value)
      if (snapshot !== null && /^[0-9a-f]{64}$/.test(snapshot.key)) result.push(snapshot)
    }
    return result
  }

  private static decode(raw: Object): CatHomeSnapshot | null {
    const value = CatVodCodec.object(raw)
    if (value === null) return null
    const savedAt = Number(value['savedAt'])
    const pageCount = Number(value['pageCount'])
    if (!Number.isFinite(savedAt) || savedAt <= 0 || savedAt > Date.now() + 60000 ||
      Date.now() - savedAt > CatHomeCache.RETAIN_MS || !Number.isInteger(pageCount) || pageCount < 1 ||
      !Array.isArray(value['categories']) || !Array.isArray(value['videos']) || !Array.isArray(value['sites'])) return null
    const result = new CatHomeSnapshot()
    result.complete = value['complete'] !== false && (value['categories'] as Object[]).length <= 200 &&
      (value['videos'] as Object[]).length <= 200 && (value['sites'] as Object[]).length <= 500
    result.key = CatVodCodec.text(value['key']); result.savedAt = savedAt; result.pageCount = pageCount
    result.siteKey = CatVodCodec.text(value['siteKey']).slice(0, 1024)
    result.categoryId = CatVodCodec.text(value['categoryId']).slice(0, 1024)
    for (const rawCategory of (value['categories'] as Object[]).slice(0, 200)) {
      const item = CatVodCodec.object(rawCategory)
      if (item === null) continue
      const category = new CatVodCategory()
      category.id = CatVodCodec.text(item['id']).slice(0, 1024)
      category.name = CatVodCodec.text(item['name']).slice(0, 256)
      category.parentId = CatVodCodec.text(item['parentId']).slice(0, 1024)
      if (category.id.length > 0 && category.name.length > 0) result.categories.push(category)
    }
    for (const rawVideo of (value['videos'] as Object[]).slice(0, 200)) {
      const item = CatVodCodec.object(rawVideo)
      if (item === null) continue
      const video = new CatVodVideo()
      video.id = CatVodCodec.text(item['id']).slice(0, 8192); video.name = CatVodCodec.text(item['name']).slice(0, 256)
      video.poster = CatVodCodec.text(item['poster']).slice(0, 16384)
      video.searchOnly = item['searchOnly'] === true
      video.remarks = CatVodCodec.text(item['remarks']).slice(0, 512)
      video.overview = CatVodCodec.text(item['overview']).slice(0, 2048)
      const year = Number(item['year']); video.year = Number.isInteger(year) && year > 0 && year < 10000 ? year : 0
      if (video.id.length > 0 && video.name.length > 0) result.videos.push(video)
    }
    for (const rawSite of (value['sites'] as Object[]).slice(0, 500)) {
      const item = CatVodCodec.object(rawSite)
      if (item === null) continue
      const site = new CatNodeSite()
      site.key = CatVodCodec.text(item['key']).slice(0, 1024); site.name = CatVodCodec.text(item['name']).slice(0, 256)
      const type = Number(item['type']); site.type = Number.isInteger(type) && type >= 0 && type < 10 ? type : 3
      site.searchable = item['searchable'] !== false
      site.indexOnly = item['indexOnly'] === true
      if (site.key.length > 0 && !/[\\/?#\u0000-\u001f]/.test(site.key) && site.name.length > 0) result.sites.push(site)
    }
    return result
  }

  static needsProxy(snapshot: CatHomeSnapshot): boolean {
    return snapshot.videos.some((video: CatVodVideo) => snapshot.siteKey.length > 0 ?
      CatArtwork.needsRuntime(video.poster) : /^http:\/\/127\.0\.0\.1:\d+\//.test(video.poster))
  }

  static rebaseArtwork(artwork: string, base: string = ''): string {
    return CatArtwork.resolve(artwork, base)
  }

  static artwork(snapshot: CatHomeSnapshot, base: string = ''): CatVodVideo[] {
    return snapshot.videos.map((item: CatVodVideo) => {
      const video = new CatVodVideo()
      video.id = item.id; video.name = item.name; video.remarks = item.remarks; video.overview = item.overview; video.year = item.year
      video.searchOnly = item.searchOnly || snapshot.sites.some((site: CatNodeSite) => site.key === snapshot.siteKey && site.indexOnly)
      // Directory snapshots use the Node bridge. Native collection snapshots
      // keep their direct URLs without starting an unrelated subscription.
      video.poster = snapshot.siteKey.length > 0 || /^http:\/\/127\.0\.0\.1:\d+\//.test(item.poster) ?
        CatHomeCache.rebaseArtwork(item.poster, base) : item.poster
      return video
    })
  }
}
