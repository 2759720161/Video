import { CatVodCategory, CatVodEpisode, CatVodEpisodeIdentity, CatVodPage, CatVodRoad, CatVodVideo } from './CatVodModels'

export class CatVodCodec {
  static parse(text: string, preserveOpaqueEpisodes: boolean = false): CatVodPage {
    let raw: Object
    try { raw = JSON.parse(text.replace(/^\uFEFF/, '')) as Object }
    catch (_) { throw new Error('来源返回了无法读取的内容，请检查来源地址') }
    const root = CatVodCodec.object(raw)
    if (root === null || (!Array.isArray(root['list']) && !Array.isArray(root['class']))) {
      throw new Error('该地址没有返回支持的作品列表')
    }
    if (root['code'] !== undefined && CatVodCodec.text(root['code']) === '0') {
      throw new Error(CatVodCodec.text(root['msg']) || '来源请求失败')
    }
    const result = new CatVodPage()
    result.page = CatVodCodec.positive(root['page'], 1)
    result.pageCount = Math.max(result.page, CatVodCodec.positive(root['pagecount'], result.page))
    const classes = Array.isArray(root['class']) ? root['class'] as Object[] : []
    const seenCategories: Set<string> = new Set()
    for (let i = 0; i < classes.length; i++) {
      const item = CatVodCodec.object(classes[i])
      if (item === null) continue
      const category = new CatVodCategory()
      category.id = CatVodCodec.text(item['type_id'])
      category.name = CatVodCodec.text(item['type_name'])
      category.parentId = CatVodCodec.text(item['type_pid'])
      if (category.id.length === 0 || category.name.length === 0 || seenCategories.has(category.id)) continue
      seenCategories.add(category.id)
      result.categories.push(category)
    }
    const items = Array.isArray(root['list']) ? root['list'] as Object[] : []
    const seenVideos: Set<string> = new Set()
    for (let i = 0; i < items.length; i++) {
      const item = CatVodCodec.object(items[i])
      if (item === null) continue
      const video = new CatVodVideo()
      video.id = CatVodCodec.text(item['vod_id'])
      video.name = CatVodCodec.text(item['vod_name'])
      if (video.id.length === 0 || video.name.length === 0 || seenVideos.has(video.id)) continue
      seenVideos.add(video.id)
      video.poster = CatVodCodec.text(item['vod_pic'])
      video.remarks = CatVodCodec.text(item['vod_remarks'])
      video.overview = CatVodCodec.cleanHtml(CatVodCodec.text(item['vod_content']) || CatVodCodec.text(item['vod_blurb']))
      video.year = CatVodCodec.positive(item['vod_year'], 0)
      video.roads = CatVodCodec.roads(CatVodCodec.text(item['vod_play_from']), CatVodCodec.text(item['vod_play_url']), preserveOpaqueEpisodes)
      result.videos.push(video)
    }
    return result
  }

  static roads(names: string, groups: string, preserveOpaqueEpisodes: boolean = false): CatVodRoad[] {
    if (groups.length === 0) return []
    const labels = names.split('$$$')
    const urls = groups.split('$$$')
    const result: CatVodRoad[] = []
    const occurrences: Map<string, number> = new Map()
    for (let i = 0; i < urls.length; i++) {
      const road = new CatVodRoad()
      road.name = (labels[i] ?? '').trim() || '线路 ' + (i + 1)
      const occurrence = occurrences.get(road.name) ?? 0
      occurrences.set(road.name, occurrence + 1)
      road.id = encodeURIComponent(road.name) + ':' + occurrence
      const episodeOccurrences: Map<string, number> = new Map()
      const entries = urls[i].split('#')
      for (let j = 0; j < entries.length; j++) {
        const entry = entries[j].trim()
        if (entry.length === 0) continue
        const separator = entry.indexOf('$')
        const episode = new CatVodEpisode()
        episode.name = separator >= 0 ? entry.substring(0, separator).trim() : '播放 ' + (j + 1)
        episode.url = separator >= 0 ? entry.substring(separator + 1).trim() : entry
        if (episode.name.length === 0 || episode.url.length === 0 ||
          (!preserveOpaqueEpisodes && !CatVodCodec.isPlayableUrl(episode.url))) continue
        episode.occurrence = episodeOccurrences.get(episode.name) ?? 0
        episodeOccurrences.set(episode.name, episode.occurrence + 1)
        road.episodes.push(episode)
      }
      if (road.episodes.length > 0) result.push(road)
    }
    return result
  }

  static episodeId(videoId: string, episode: CatVodEpisode): string {
    return 'catvod|' + encodeURIComponent(videoId) + '|' + encodeURIComponent(episode.name) + '|' + episode.occurrence
  }

  static identity(id: string): CatVodEpisodeIdentity | null {
    const parts = id.split('|')
    if (parts.length !== 4 || parts[0] !== 'catvod' || !/^\d+$/.test(parts[3])) return null
    try {
      const result = new CatVodEpisodeIdentity()
      result.videoId = decodeURIComponent(parts[1])
      result.name = decodeURIComponent(parts[2])
      result.occurrence = Number(parts[3])
      if (result.videoId.length === 0 || result.name.length === 0 || !Number.isSafeInteger(result.occurrence)) return null
      return result
    } catch (_) { return null }
  }

  static findEpisode(road: CatVodRoad, identity: CatVodEpisodeIdentity): CatVodEpisode | null {
    return road.episodes.find((episode: CatVodEpisode) =>
      episode.name === identity.name && episode.occurrence === identity.occurrence) ?? null
  }

  static isHttpUrl(value: string): boolean {
    return /^https?:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(value)
  }

  static isPlayableUrl(value: string): boolean {
    // 原生阶段不把网页播放页当作媒体流；无扩展名的 HTTP 流仍然允许。
    return CatVodCodec.isHttpUrl(value) && !/\.html?(?:[?#]|$)/i.test(value)
  }

  static object(value: Object | undefined): Record<string, Object> | null {
    return value !== null && typeof value === 'object' && !Array.isArray(value)
      ? value as Record<string, Object> : null
  }

  static text(value: Object | undefined): string {
    return typeof value === 'string' || typeof value === 'number' ? String(value).trim() : ''
  }

  private static positive(value: Object | undefined, fallback: number): number {
    const number = Number(CatVodCodec.text(value))
    return Number.isSafeInteger(number) && number > 0 ? number : fallback
  }

  static cleanHtml(text: string): string {
    return text.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/gi, ' ').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/&amp;/gi, '&').trim()
  }
}
