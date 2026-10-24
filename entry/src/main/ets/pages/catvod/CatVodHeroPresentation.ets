import { CatVodVideo } from '../../providers/catvod/CatVodModels'
import { CatVodCodec } from '../../providers/catvod/CatVodCodec'
import { HomeCarouselItem } from '../../components/media/carousel/HomeCarouselItem'

/** Keep the first page's featured selection independent of later pagination. */
export class CatVodHeroPresentation {
  /** ForEach must rebuild stale @Prop bindings when a cached proxy URL becomes available. */
  static posterKey(video: CatVodVideo): string {
    return JSON.stringify([video.id, video.poster, video.name, video.remarks, video.searchOnly])
  }

  static carouselItems(videos: CatVodVideo[]): HomeCarouselItem[] {
    return videos.map((video: CatVodVideo): HomeCarouselItem => {
      const item = new HomeCarouselItem()
      item.id = video.id; item.title = video.name; item.artworkUrl = video.poster
      item.subtitle = CatVodHeroPresentation.metadata(video).join(' · ') || CatVodHeroPresentation.summary(video)
      return item
    })
  }
  static select(videos: CatVodVideo[]): CatVodVideo[] {
    const result: CatVodVideo[] = []
    const seen: Set<string> = new Set()
    for (let i = 0; i < videos.length && result.length < 6; i++) {
      const video = videos[i]
      if (video.id.trim().length === 0 || video.name.trim().length === 0 ||
        video.poster.trim().length === 0 || seen.has(video.id)) continue
      seen.add(video.id); result.push(video)
    }
    return result
  }

  /** Filter only the displayed grid; the complete page remains available for caching and pagination. */
  static belowHero(videos: CatVodVideo[], featured: CatVodVideo[]): CatVodVideo[] {
    if (featured.length === 0) return videos
    const ids = new Set(featured.map((video: CatVodVideo) => video.id))
    return videos.filter((video: CatVodVideo) => !ids.has(video.id))
  }

  static summary(video: CatVodVideo): string {
    const text = CatVodCodec.cleanHtml(video.overview).replace(/\s+/g, ' ').trim()
    return text.length > 60 ? text.substring(0, 60) + '…' : text
  }

  static metadata(video: CatVodVideo): string[] {
    const result: string[] = []
    if (Number.isFinite(video.year) && video.year > 0) result.push(String(video.year))
    const remarks = CatVodCodec.cleanHtml(video.remarks).trim()
    if (remarks.length > 0) result.push(remarks)
    return result
  }

  static height(width: number, topInset: number): number {
    return (width >= 840 ? 360 : (width >= 600 ? 340 : 300)) + topInset
  }

  static posterWidth(width: number): number {
    return width >= 1200 ? 198 : (width >= 840 ? 192 : (width >= 600 ? 180 : 122))
  }
}
