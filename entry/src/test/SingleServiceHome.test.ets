import { describe, it, expect } from '@ohos/hypium'
import { HomeSourcePolicy } from '../main/ets/services/library/HomeSourcePolicy'
import { MediaSourceInstance } from '../main/ets/core/media/MediaSourceInstance'
import { EmbyItem } from '../main/ets/providers/emby/EmbyModels'
import { EmbyHomeSnapshot, EmbyHomeSection } from '../main/ets/services/library/EmbyHomeSnapshot'
import { EmbyHomeCache } from '../main/ets/services/library/EmbyHomeCache'
import { EmbyHomeCoordinator } from '../main/ets/services/library/EmbyHomeCoordinator'
import type { EmbyHomePersistence } from '../main/ets/services/library/EmbyHomeCoordinator'
import type { EmbyHomeSource } from '../main/ets/providers/emby/EmbyHomeSource'

function source(id: string, type: string = 'emby', enabled: boolean = true): MediaSourceInstance {
  const value = new MediaSourceInstance(); value.id = id; value.providerType = type; value.enabled = enabled
  return value
}
function media(id: string, type: string = 'Movie'): EmbyItem {
  const item = new EmbyItem(); item.id = id; item.name = id; item.type = type
  return item
}
class MemoryPersistence implements EmbyHomePersistence {
  values: Map<string, string> = new Map()
  writes: string[] = []
  async read(key: string): Promise<string> { return this.values.get(key) ?? '' }
  async write(key: string, value: string): Promise<void> { this.values.set(key, value); this.writes.push(key) }
}
class FakeHomeSource implements EmbyHomeSource {
  libraries: EmbyItem[] = [media('movies', 'CollectionFolder')]
  resumed: EmbyItem[] = []
  previews: EmbyItem[] = [media('movie')]
  librariesWait: Promise<EmbyItem[]> | null = null
  failLibraries: boolean = false
  failPreview: boolean = false
  activePreviews: number = 0
  maximumPreviews: number = 0
  previewRequests: string[] = []
  async getLibrariesRaw(): Promise<EmbyItem[]> {
    if (this.failLibraries) throw new Error('offline')
    return this.librariesWait ?? this.libraries
  }
  async getResumeItemsRaw(): Promise<EmbyItem[]> { return this.resumed }
  async getNextUpItemsRaw(_limit: number): Promise<EmbyItem[]> { return [] }
  async getLatestLibraryItemsRaw(id: string, limit: number): Promise<EmbyItem[]> {
    this.previewRequests.push(id + ':' + limit)
    this.activePreviews++
    this.maximumPreviews = Math.max(this.maximumPreviews, this.activePreviews)
    await Promise.resolve()
    this.activePreviews--
    if (this.failPreview) throw new Error('preview offline')
    return this.previews
  }
}

export default function singleServiceHomeTest(): void {
  describe('SingleServiceHome', () => {
    it('built_in_local_row_alone_is_not_an_added_service', 0, () => {
      expect(HomeSourcePolicy.hasAddedService([source('local', 'local')], false)).assertFalse()
      expect(HomeSourcePolicy.hasAddedService([], false)).assertFalse()
    })
    it('explicitly_created_local_folder_counts_even_when_empty', 0, () => {
      expect(HomeSourcePolicy.hasAddedService([source('local', 'local')], true)).assertTrue()
    })
    it('added_remote_services_count_even_when_disabled_or_offline', 0, () => {
      expect(HomeSourcePolicy.hasAddedService([source('local', 'local'), source('server')], false)).assertTrue()
      expect(HomeSourcePolicy.hasAddedService([source('server', 'emby', false)], false)).assertTrue()
      expect(HomeSourcePolicy.hasAddedService([source('nas', 'webdav')], false)).assertTrue()
    })
    it('removing_the_last_remote_and_local_folder_restores_no_services', 0, () => {
      const sources = [source('local', 'local'), source('server')]
      expect(HomeSourcePolicy.hasAddedService(sources, false)).assertTrue()
      sources.pop()
      expect(HomeSourcePolicy.hasAddedService(sources, false)).assertFalse()
    })
    it('selects_an_instance_not_a_provider_type', 0, () => {
      expect(HomeSourcePolicy.resolve('second', [source('local', 'local'), source('first'), source('second')])).assertEqual('second')
    })
    it('adding_services_does_not_replace_the_selected_home', 0, () => {
      expect(HomeSourcePolicy.resolve('local', [source('local', 'local'), source('new')])).assertEqual('local')
      expect(HomeSourcePolicy.resolve('first', [source('local', 'local'), source('first'), source('new')])).assertEqual('first')
    })
    it('deleted_disabled_and_unsupported_sources_fall_back_to_local', 0, () => {
      const sources = [source('local', 'local'), source('disabled', 'emby', false), source('future', 'plex')]
      for (const id of ['missing', 'disabled', 'future']) expect(HomeSourcePolicy.resolve(id, sources)).assertEqual('local')
    })
    it('cache_preserves_series_context_and_excludes_unapproved_fields', 0, () => {
      const decoded = EmbyHomeCache.decode('{"timestamp":123,"libraries":[],"sections":[],"resumeItems":[' +
        '{"id":"e","name":"Episode","type":"Episode","seriesId":"show","seasonId":"season",' +
        '"poster":"https://example.invalid/?api_key=SECRET","accessToken":"SECRET",' +
        '"variants":[{"url":"https://example.invalid/SECRET"}],' +
        '"userData":{"playbackPositionTicks":10000000,"played":false}}]}')
      expect(decoded.resumeItems[0].seriesId).assertEqual('show')
      expect(decoded.resumeItems[0].seasonId).assertEqual('season')
      expect(decoded.resumeItems[0].resumePositionMs()).assertEqual(1000)
      expect(EmbyHomeCache.encode(decoded).includes('SECRET')).assertFalse()
    })
    it('publishes_resume_before_a_slow_library_request_finishes', 0, async () => {
      const provider = new FakeHomeSource()
      let release: (items: EmbyItem[]) => void = () => {}
      provider.librariesWait = new Promise<EmbyItem[]>((resolve) => { release = resolve })
      const episode = media('resume', 'Episode'); episode.userData.playbackPositionTicks = 10000000
      provider.resumed = [episode]
      const snapshots: EmbyHomeSnapshot[] = []
      const task = new EmbyHomeCoordinator(provider, 'A', new MemoryPersistence()).load(value => snapshots.push(value))
      for (let i = 0; i < 8; i++) await Promise.resolve()
      expect(snapshots.some(value => value.resumeItems.length === 1 && value.librariesLoading)).assertTrue()
      release(provider.libraries); await task
    })
    it('disposing_a_service_blocks_late_publications_and_cache_writes', 0, async () => {
      const provider = new FakeHomeSource(); const cache = new MemoryPersistence()
      let release: (items: EmbyItem[]) => void = () => {}
      provider.librariesWait = new Promise<EmbyItem[]>((resolve) => { release = resolve })
      const coordinator = new EmbyHomeCoordinator(provider, 'old', cache)
      let publications = 0
      const task = coordinator.load(() => { publications++ })
      for (let i = 0; i < 8; i++) await Promise.resolve()
      coordinator.dispose(); const before = publications
      release(provider.libraries); await task
      expect(publications).assertEqual(before)
      expect(cache.writes.length).assertEqual(0)
      expect(provider.previewRequests.length).assertEqual(0)
    })
    it('keeps_cached_content_when_the_same_server_is_offline', 0, async () => {
      const provider = new FakeHomeSource(); provider.failLibraries = true
      const cache = new MemoryPersistence(); const cached = new EmbyHomeSnapshot()
      cached.timestamp = 123; cached.libraries = [media('cached-library', 'CollectionFolder')]
      const section = new EmbyHomeSection(); section.id = 'cached-library'; section.items = [media('cached-movie')]
      cached.sections = [section]; cache.values.set('server', EmbyHomeCache.encode(cached))
      let result = new EmbyHomeSnapshot()
      await new EmbyHomeCoordinator(provider, 'server', cache).load(value => { result = value })
      expect(result.sections[0].items[0].id).assertEqual('cached-movie')
      expect(result.librariesError.length > 0).assertTrue()
      expect(cache.writes.length).assertEqual(0)
    })
    it('limits_preview_concurrency_and_keeps_other_services_cache', 0, async () => {
      const provider = new FakeHomeSource(); const cache = new MemoryPersistence()
      provider.libraries = [media('a'), media('b'), media('c'), media('d')]
      cache.values.set('unselected', 'preserved')
      await new EmbyHomeCoordinator(provider, 'selected', cache).load(() => {})
      expect(provider.maximumPreviews <= 2).assertTrue()
      expect(provider.previewRequests.length).assertEqual(4)
      expect(provider.previewRequests.every(value => value.endsWith(':10'))).assertTrue()
      expect(cache.values.get('unselected')).assertEqual('preserved')
      expect(cache.writes[0]).assertEqual('selected')
    })
    it('preview_failure_does_not_hide_libraries_or_resume', 0, async () => {
      const provider = new FakeHomeSource(); provider.failPreview = true
      const episode = media('resume', 'Episode'); episode.userData.playbackPositionTicks = 10000000
      provider.resumed = [episode]
      let result = new EmbyHomeSnapshot()
      await new EmbyHomeCoordinator(provider, 'server', new MemoryPersistence()).load(value => { result = value })
      expect(result.libraries.length).assertEqual(1)
      expect(result.resumeItems.length).assertEqual(1)
      expect(result.sections[0].error.length > 0).assertTrue()
    })
  })
}
