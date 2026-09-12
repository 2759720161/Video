import { describe, it, expect } from '@ohos/hypium'
import { EmbyLibraryPresentation } from '../main/ets/providers/emby/EmbyLibraryPresentation'

export default function embyLibraryPresentationTest(): void {
  describe('EmbyLibraryPresentation', () => {
    it('maps_typed_libraries_to_semantic_media', 0, () => {
      expect(EmbyLibraryPresentation.itemTypes('movies')).assertEqual('Movie')
      expect(EmbyLibraryPresentation.itemTypes('tvshows')).assertEqual('Series')
      expect(EmbyLibraryPresentation.itemTypes('homevideos')).assertEqual('Video')
      expect(EmbyLibraryPresentation.itemTypes('boxsets')).assertEqual('BoxSet')
    })

    it('keeps_mixed_libraries_semantic_without_folder_entries', 0, () => {
      expect(EmbyLibraryPresentation.itemTypes('')).assertEqual('Series,Movie,Video,BoxSet')
      expect(EmbyLibraryPresentation.itemTypes('mixed')).assertEqual('Series,Movie,Video,BoxSet')
      expect(EmbyLibraryPresentation.itemTypes('mixed').indexOf('Folder') < 0).assertTrue()
    })

    it('labels_library_content_for_people', 0, () => {
      expect(EmbyLibraryPresentation.contentLabel('movies')).assertEqual('电影')
      expect(EmbyLibraryPresentation.contentLabel('tvshows')).assertEqual('剧集')
      expect(EmbyLibraryPresentation.contentLabel('')).assertEqual('媒体')
    })
  })
}
