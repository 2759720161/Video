import { EmbyItem } from './EmbyModels'

export interface EmbyHomeSource {
  getLibrariesRaw(): Promise<EmbyItem[]>
  getResumeItemsRaw(): Promise<EmbyItem[]>
  getNextUpItemsRaw(limit: number): Promise<EmbyItem[]>
  getLatestLibraryItemsRaw(parentId: string, limit: number): Promise<EmbyItem[]>
}
