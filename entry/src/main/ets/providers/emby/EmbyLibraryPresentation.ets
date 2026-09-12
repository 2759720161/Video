/**
 * Converts Emby collection metadata into a product-facing media view.
 * Physical folder browsing is intentionally kept as a separate mode.
 */
export class EmbyLibraryPresentation {
  static itemTypes(collectionType: string): string {
    const normalized = EmbyLibraryPresentation.normalize(collectionType)
    if (normalized === 'movies') return 'Movie'
    if (normalized === 'tvshows') return 'Series'
    if (normalized === 'musicvideos' || normalized === 'homevideos') return 'Video'
    if (normalized === 'boxsets') return 'BoxSet'
    return 'Series,Movie,Video,BoxSet'
  }

  static contentLabel(collectionType: string): string {
    const normalized = EmbyLibraryPresentation.normalize(collectionType)
    if (normalized === 'movies') return '电影'
    if (normalized === 'tvshows') return '剧集'
    if (normalized === 'musicvideos') return '音乐视频'
    if (normalized === 'homevideos') return '家庭视频'
    if (normalized === 'boxsets') return '合集'
    return '媒体'
  }

  static isSemanticLibrary(collectionType: string): boolean {
    return EmbyLibraryPresentation.normalize(collectionType) !== 'folders'
  }

  private static normalize(value: string): string {
    return value.trim().toLowerCase()
  }
}
