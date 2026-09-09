import { MediaSection } from '../core/media/MediaSection'

/** 首页来源快照；只包含可安全缓存的媒体元数据和稳定 ArtworkRef。 */
export class ProviderHomeSnapshot {
  sourceId: string = ''
  sourceName: string = ''
  updatedAt: number = 0
  sections: MediaSection[] = []
}
