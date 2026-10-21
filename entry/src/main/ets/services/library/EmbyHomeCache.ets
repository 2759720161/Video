import { EmbyItem } from '../../providers/emby/EmbyModels'
import { EmbyHomeSnapshot, EmbyHomeSection } from './EmbyHomeSnapshot'

export class EmbyHomeCache {
  static decode(raw: string): EmbyHomeSnapshot {
    const value = JSON.parse(raw) as Record<string, Object>
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid home cache')
    const result = new EmbyHomeSnapshot()
    result.timestamp = EmbyHomeCache.cachedNumber(value, 'timestamp')
    result.libraries = EmbyHomeCache.decodeCachedItems(value['libraries'])
    result.resumeItems = EmbyHomeCache.decodeCachedItems(value['resumeItems'])
    result.nextUpItems = EmbyHomeCache.decodeCachedItems(value['nextUpItems'])
    result.latestItems = EmbyHomeCache.decodeCachedItems(value['latestItems'])
    result.sections = EmbyHomeCache.decodeCachedSections(value['sections'])
    return result
  }

  static encode(snapshot: EmbyHomeSnapshot): string {
    // Keep only display metadata and identifiers. Never persist playback URLs or credentials.
    return JSON.stringify(EmbyHomeCache.decode(JSON.stringify(snapshot)))
  }
  private static decodeCachedItems(raw: Object): EmbyItem[] {
    if (!Array.isArray(raw)) return []
    const result: EmbyItem[] = []
    const values = raw as Array<Record<string, Object>>
    for (let i = 0; i < values.length; i++) {
      const candidate = values[i] as Object
      if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) continue
      const value = candidate as Record<string, Object>
      const item = new EmbyItem()
      item.id = EmbyHomeCache.cachedString(value, 'id')
      item.name = EmbyHomeCache.cachedString(value, 'name')
      item.type = EmbyHomeCache.cachedString(value, 'type')
      item.parentId = EmbyHomeCache.cachedString(value, 'parentId')
      item.seriesId = EmbyHomeCache.cachedString(value, 'seriesId')
      item.seasonId = EmbyHomeCache.cachedString(value, 'seasonId')
      item.collectionType = EmbyHomeCache.cachedString(value, 'collectionType')
      item.isFolder = EmbyHomeCache.cachedBoolean(value, 'isFolder')
      item.runTimeTicks = EmbyHomeCache.cachedNumber(value, 'runTimeTicks')
      item.productionYear = EmbyHomeCache.cachedNumber(value, 'productionYear')
      item.indexNumber = EmbyHomeCache.cachedNumber(value, 'indexNumber')
      item.parentIndexNumber = EmbyHomeCache.cachedNumber(value, 'parentIndexNumber')
      item.seriesName = EmbyHomeCache.cachedString(value, 'seriesName')
      item.overview = EmbyHomeCache.cachedString(value, 'overview')
      item.imageItemId = EmbyHomeCache.cachedString(value, 'imageItemId')
      item.primaryImageTag = EmbyHomeCache.cachedString(value, 'primaryImageTag')
      item.backdropImageTag = EmbyHomeCache.cachedString(value, 'backdropImageTag')
      item.backdropItemId = EmbyHomeCache.cachedString(value, 'backdropItemId')
      item.thumbnailImageTag = EmbyHomeCache.cachedString(value, 'thumbnailImageTag')
      item.thumbnailItemId = EmbyHomeCache.cachedString(value, 'thumbnailItemId')
      item.container = EmbyHomeCache.cachedString(value, 'container')
      const userData = value['userData']
      if (userData !== null && typeof userData === 'object') {
        const data = userData as Record<string, Object>
        item.userData.playbackPositionTicks = EmbyHomeCache.cachedNumber(data, 'playbackPositionTicks')
        item.userData.playedPercentage = EmbyHomeCache.cachedNumber(data, 'playedPercentage')
        item.userData.played = EmbyHomeCache.cachedBoolean(data, 'played')
      }
      if (item.id.length > 0 && item.name.length > 0) result.push(item)
    }
    return result
  }

  private static decodeCachedSections(raw: Object): EmbyHomeSection[] {
    if (!Array.isArray(raw)) return []
    const result: EmbyHomeSection[] = []
    const values = raw as Array<Record<string, Object>>
    for (let i = 0; i < values.length; i++) {
      const candidate = values[i] as Object
      if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate)) continue
      const value = candidate as Record<string, Object>
      const section = new EmbyHomeSection()
      section.id = EmbyHomeCache.cachedString(value, 'id')
      section.title = EmbyHomeCache.cachedString(value, 'title')
      section.collectionType = EmbyHomeCache.cachedString(value, 'collectionType')
      section.items = EmbyHomeCache.decodeCachedItems(value['items'])
      if (section.id.length > 0 && section.items.length > 0) result.push(section)
    }
    return result
  }

  private static cachedString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }

  private static cachedNumber(value: Record<string, Object>, key: string): number {
    return typeof value[key] === 'number' && Number.isFinite(value[key] as number) ? value[key] as number : 0
  }

  private static cachedBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }

}
