import type { PlaybackVariant } from '../playback/PlaybackVariant'

export enum MediaItemType {
  VIDEO = 'video',
  MOVIE = 'movie',
  SERIES = 'series',
  SEASON = 'season',
  EPISODE = 'episode',
  FOLDER = 'folder',
  COLLECTION = 'collection'
}

export class MediaItem {
  sourceId: string = ''
  id: string = ''
  /** 通用浏览父级标识；首页推荐点击浏览时由 Provider 路由解释。 */
  parentId: string = ''
  title: string = ''
  subtitle: string = ''
  overview: string = ''
  type: MediaItemType = MediaItemType.VIDEO
  poster: string = ''
  /** 稳定 artwork 引用；poster 仅用于当前运行时展示。 */
  artworkRef: string = ''
  backdrop: string = ''
  durationMs: number = 0
  positionMs: number = 0
  /** 影视源或多线路 Provider 当前选择的稳定线路标识。 */
  variantId: string = ''
  /** 可供 UI 展示和选择的线路/清晰度列表。 */
  variants: PlaybackVariant[] = []
  year: number = 0
  playable: boolean = false
  browsable: boolean = false
}
