import { describe, it, expect } from '@ohos/hypium'
import { CatVodCodec } from '../main/ets/providers/catvod/CatVodCodec'
import { CatVodSourceConfig, CatVodSourceConfigCodec } from '../main/ets/providers/catvod/CatVodSourceConfig'
import { CatVodProvider } from '../main/ets/providers/catvod/CatVodProvider'
import type { CatVodDataSource } from '../main/ets/providers/catvod/CatVodModels'
import { CatVodCategory, CatVodPage, CatVodVideo } from '../main/ets/providers/catvod/CatVodModels'
import { MediaSourceInstance } from '../main/ets/core/media/MediaSourceInstance'
import { PlaybackQueueItem } from '../main/ets/core/playback/PlaybackQueueItem'
import { HomeSourcePolicy } from '../main/ets/services/library/HomeSourcePolicy'

const DETAIL: string = '{"page":1,"pagecount":1,"list":[{"vod_id":"show|1","vod_name":"测试剧集",' +
  '"vod_play_from":"A$$$B$$$C","vod_play_url":"第1集$https://a.invalid/1.m3u8#第2集$https://a.invalid/2.m3u8' +
  '$$$第2集$https://b.invalid/2.m3u8#第1集$https://b.invalid/1.m3u8$$$第2集$https://c.invalid/2.m3u8"}]}'

class FixtureSource implements CatVodDataSource {
  content: string = DETAIL
  detailRequests: number = 0
  async categories(): Promise<CatVodCategory[]> { return [] }
  async page(_category: string, _keyword: string, _page: number): Promise<CatVodPage> { return CatVodCodec.parse(this.content) }
  async detail(id: string): Promise<CatVodVideo | null> {
    this.detailRequests++
    return CatVodCodec.parse(this.content).videos.find((video: CatVodVideo) => video.id === id) ?? null
  }
}

function source(): MediaSourceInstance {
  const item = new MediaSourceInstance()
  item.id = 'catvod_test'; item.providerType = 'catvod'; item.name = '测试来源'
  return item
}

function queue(provider: CatVodProvider, video: CatVodVideo, road: number, episode: number): PlaybackQueueItem {
  const media = provider.episodeItems(video, video.roads[road].id)[episode]
  const item = new PlaybackQueueItem()
  item.sourceId = media.sourceId; item.mediaId = media.id; item.title = media.title
  item.subtitle = media.subtitle; item.variantId = media.variantId; item.variants = media.variants
  item.startFromBeginning = true
  return item
}

export default function catVodTest(): void {
  describe('CatVod', () => {
    it('decodes_numeric_ids_and_deduplicates_bad_entries', 0, () => {
      const page = CatVodCodec.parse('{"page":"2","pagecount":"3","class":[{"type_id":1,"type_name":"电影"},' +
        '{"type_id":1,"type_name":"重复"},null],"list":[{"vod_id":7,"vod_name":"作品"},' +
        '{"vod_id":7,"vod_name":"重复"},{"vod_id":8},null]}')
      expect(page.page).assertEqual(2)
      expect(page.pageCount).assertEqual(3)
      expect(page.categories.length).assertEqual(1)
      expect(page.videos.length).assertEqual(1)
      expect(page.videos[0].id).assertEqual('7')
    })
    it('rejects_html_and_unrelated_json', 0, () => {
      for (const text of ['<html>blocked</html>', '[]', 'null', '{"token":"value"}']) {
        let rejected = false
        try { CatVodCodec.parse(text) } catch (_) { rejected = true }
        expect(rejected).assertTrue()
      }
    })
    it('keeps_dollars_inside_urls_and_ignores_opaque_script_tokens', 0, () => {
      const roads = CatVodCodec.roads('A', '第1集$https://example.invalid/a$token.m3u8#第2集$base64-token#第3集$javascript:alert(1)')
      expect(roads.length).assertEqual(1)
      expect(roads[0].episodes.length).assertEqual(1)
      expect(roads[0].episodes[0].url).assertEqual('https://example.invalid/a$token.m3u8')
    })
    it('does_not_offer_html_player_pages_and_prefers_the_migrated_hls_line', 0, () => {
      const page = CatVodCodec.parse('{"list":[{"vod_id":"v","vod_name":"作品",' +
        '"vod_play_from":"网页$$$原画$$$dyttm3u8","vod_play_url":"播放$https://site.invalid/player.html?id=1' +
        '$$$播放$https://media.invalid/1.mp4$$$播放$https://media.invalid/1.m3u8"}]}')
      expect(page.videos[0].roads.length).assertEqual(2)
      expect(CatVodProvider.defaultRoad(page.videos[0])!.name).assertEqual('dyttm3u8')
    })
    it('round_trips_reserved_characters_and_duplicate_episode_names', 0, () => {
      const episodes = CatVodCodec.roads('A', '集|1$https://a.invalid/1#集|1$https://a.invalid/2')[0].episodes
      const first = CatVodCodec.episodeId('作品|:/', episodes[0])
      const second = CatVodCodec.episodeId('作品|:/', episodes[1])
      expect(first === second).assertFalse()
      expect(CatVodCodec.identity(second)!.videoId).assertEqual('作品|:/')
      expect(CatVodCodec.identity(second)!.name).assertEqual('集|1')
      expect(CatVodCodec.identity(second)!.occurrence).assertEqual(1)
      expect(CatVodCodec.identity('catvod|%ZZ|name|0') === null).assertTrue()
      expect(CatVodCodec.identity('catvod|v|name|-1') === null).assertTrue()
    })
    it('rejects_program_urls_and_header_line_breaks', 0, () => {
      const config = new CatVodSourceConfig()
      config.apiUrl = 'https://9280.kstore.space/ceshi/index.js.md5'
      expect(CatVodSourceConfigCodec.normalize(config)).assertFalse()
      config.apiUrl = 'https://9280.kstore.space/ceshi/index.js'
      expect(CatVodSourceConfigCodec.normalize(config)).assertFalse()
      config.apiUrl = 'https://api.invalid/vod'
      config.referer = 'https://site.invalid/\r\nInjected: value'
      expect(CatVodSourceConfigCodec.normalize(config)).assertFalse()
    })
    it('replaces_reserved_query_params_and_encodes_search', 0, () => {
      const config = new CatVodSourceConfig()
      config.apiUrl = 'https://api.invalid/vod?key=abc&ac=list&pg=99'
      const params: Record<string, string> = {}
      params['ac'] = 'detail'; params['pg'] = '2'; params['wd'] = '中文 & 搜索'
      const url = CatVodSourceConfigCodec.requestUrl(config, params)
      expect(url.includes('key=abc')).assertTrue()
      expect(url.includes('ac=list')).assertFalse()
      expect(url.includes('pg=99')).assertFalse()
      expect(url.includes('wd=' + encodeURIComponent('中文 & 搜索'))).assertTrue()
    })
    it('switches_lines_by_episode_name_not_position', 0, async () => {
      const fixture = new FixtureSource()
      const provider = new CatVodProvider(source(), fixture, new CatVodSourceConfig())
      const video = CatVodCodec.parse(DETAIL).videos[0]
      const item = queue(provider, video, 0, 0)
      expect(item.variants.length).assertEqual(2)
      item.variantId = video.roads[1].id
      const session = await provider.resolvePlayback(item)
      expect(session.stream.url).assertEqual('https://b.invalid/1.m3u8')
      expect(session.media.mediaId).assertEqual(item.mediaId)
    })
    it('rejects_a_line_that_does_not_contain_the_selected_episode', 0, async () => {
      const provider = new CatVodProvider(source(), new FixtureSource(), new CatVodSourceConfig())
      const video = CatVodCodec.parse(DETAIL).videos[0]
      const item = queue(provider, video, 0, 0)
      item.variantId = video.roads[2].id
      let rejected = false
      try { await provider.resolvePlayback(item) } catch (_) { rejected = true }
      expect(rejected).assertTrue()
      item.variantId = video.roads[0].id; item.sourceId = 'another_source'
      rejected = false
      try { await provider.resolvePlayback(item) } catch (_) { rejected = true }
      expect(rejected).assertTrue()
    })
    it('refreshes_the_url_without_changing_the_history_identity', 0, async () => {
      const fixture = new FixtureSource()
      const config = new CatVodSourceConfig()
      config.referer = 'https://site.invalid/'
      const provider = new CatVodProvider(source(), fixture, config)
      const video = CatVodCodec.parse(DETAIL).videos[0]
      const item = queue(provider, video, 0, 0)
      const before = await provider.resolvePlayback(item)
      fixture.content = DETAIL.replace('https://a.invalid/1.m3u8', 'https://a.invalid/1.m3u8?token=new')
      const after = await provider.resolvePlayback(item)
      expect(after.stream.url === before.stream.url).assertFalse()
      expect(after.media.mediaId).assertEqual(before.media.mediaId)
      expect(after.stream.referer).assertEqual(config.referer)
      expect(after.stream.userAgent).assertEqual(config.userAgent)
      expect((await provider.getItem(item.mediaId))!.id).assertEqual(item.mediaId)
    })
    it('history_open_consumes_its_prepared_detail_once_then_refreshes_normally', 0, async () => {
      const fixture = new FixtureSource()
      const provider = new CatVodProvider(source(), fixture, new CatVodSourceConfig())
      const video = CatVodCodec.parse(DETAIL).videos[0]
      const current = queue(provider, video, 0, 0)
      const restored = await provider.getItem(current.mediaId)
      expect(restored !== null).assertTrue()
      current.variantId = restored!.variantId
      fixture.content = DETAIL.replace('A$$$', '重命名线路$$$')
      const opened = await provider.resolvePlayback(current)
      expect(fixture.detailRequests).assertEqual(1)
      expect(opened.media.mediaId).assertEqual(current.mediaId)
      expect(opened.stream.url).assertEqual('https://a.invalid/1.m3u8')
      fixture.content = DETAIL.replace('https://a.invalid/1.m3u8', 'https://a.invalid/1.m3u8?fresh=1')
      const refreshed = await provider.resolvePlayback(current)
      expect(fixture.detailRequests).assertEqual(2)
      expect(refreshed.stream.url).assertEqual('https://a.invalid/1.m3u8?fresh=1')
    })
    it('refreshes_only_the_current_series_queue_and_preserves_position', 0, async () => {
      const provider = new CatVodProvider(source(), new FixtureSource(), new CatVodSourceConfig())
      const video = CatVodCodec.parse(DETAIL).videos[0]
      const current = queue(provider, video, 0, 0)
      current.positionMs = 12345
      const session = await provider.resolvePlayback(current)
      session.queue = [current]
      const items = await provider.refreshQueue(session)
      expect(items.length).assertEqual(2)
      expect(items[0].positionMs).assertEqual(12345)
      expect(items[1].sourceId).assertEqual(source().id)
      expect(CatVodCodec.identity(items[1].mediaId)!.videoId).assertEqual(video.id)
    })
    it('enables_catvod_home_without_selecting_it_automatically', 0, () => {
      const local = source(); local.id = 'local'; local.providerType = 'local'
      expect(HomeSourcePolicy.canSelect(source())).assertTrue()
      expect(HomeSourcePolicy.resolve('local', [local, source()])).assertEqual('local')
      expect(HomeSourcePolicy.resolve(source().id, [local, source()])).assertEqual(source().id)
      const disabled = source(); disabled.enabled = false
      expect(HomeSourcePolicy.canSelect(disabled)).assertFalse()
    })
  })
}
