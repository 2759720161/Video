import { describe, it, expect } from '@ohos/hypium'
import { PlaybackStream } from '../main/ets/core/playback/PlaybackStream'
import { PlaybackSession } from '../main/ets/core/playback/PlaybackSession'
import type { PlaybackReporter } from '../main/ets/core/playback/PlaybackReporter'
import { PlaybackSessionManager } from '../main/ets/services/PlaybackSessionManager'
import { LocalPlaybackQueueAdapter } from '../main/ets/providers/local/LocalPlaybackQueueAdapter'
import { LocalVideoRecord } from '../main/ets/models/LocalVideoRecord'
import { PlaybackReportController } from '../main/ets/core/playback/PlaybackReportController'
import { PlaybackOptionsAdapter } from '../main/ets/core/playback/PlaybackOptionsAdapter'
import { PlaybackPosition } from '../main/ets/core/playback/PlaybackPosition'
import { EmbyServerConfig } from '../main/ets/providers/emby/EmbyModels'
import { PlaybackTestFactory } from './helpers/PlaybackTestFactory'

class TestPlaybackReporter implements PlaybackReporter {
  events: string[] = []
  failStart: boolean = false
  async started(_positionMs: number, _durationMs: number, _playing: boolean, _speed: number): Promise<void> {
    this.events.push('started')
    if (this.failStart) throw new Error('test transport failure')
  }
  async progress(_positionMs: number, _durationMs: number, _playing: boolean,
    _speed: number, eventName?: string): Promise<void> {
    this.events.push(eventName ?? 'TimeUpdate')
  }
  async stopped(positionMs: number, _durationMs: number, _speed: number): Promise<void> {
    this.events.push('stopped:' + positionMs)
  }
}

export default function playbackModelsTest(): void {
  describe('PlaybackModels', () => {
    it('reporter_waits_for_ready_and_stops_only_once', 0, async () => {
      const reporter = new TestPlaybackReporter()
      const controller = new PlaybackReportController(reporter)
      controller.update(0, 100000, false, 1, false, 0)
      await controller.stop(0, 100000, 1)
      expect(reporter.events.length).assertEqual(0)
      controller.update(12000, 100000, true, 1, true, 1000)
      await controller.stop(13000, 100000, 1)
      await controller.stop(14000, 100000, 1)
      expect(reporter.events.join(',')).assertEqual('started,stopped:13000')
    })

    it('reporter_preserves_start_progress_stop_order_across_pip_handoff', 0, async () => {
      const manager = PlaybackSessionManager.getInstance()
      const reporter = new TestPlaybackReporter()
      const id = manager.create(PlaybackTestFactory.createSession(), reporter)
      try {
        const pageController = manager.getReportController(id)!
        pageController.update(1000, 100000, true, 1, true, 1000)
        const pipController = manager.getReportController(id)!
        expect(pageController === pipController).assertTrue()
        pipController.update(2000, 100000, true, 1, true, 2000)
        pipController.update(3000, 100000, false, 1, true, 3000)
        pipController.update(4000, 100000, true, 1, true, 4000)
        pipController.update(14000, 100000, true, 1, true, 14000)
        await pipController.stop(15000, 100000, 1)
        expect(reporter.events.join(',')).assertEqual('started,Pause,Unpause,TimeUpdate,stopped:15000')
      } finally {
        manager.release(id)
      }
      expect(manager.getReportController(id) === null).assertTrue()
      expect(manager.getResolver(id) === null).assertTrue()
    })

    it('failed_report_does_not_block_later_stop', 0, async () => {
      const reporter = new TestPlaybackReporter()
      reporter.failStart = true
      const controller = new PlaybackReportController(reporter)
      controller.update(1000, 100000, true, 1, true, 1000)
      controller.update(2000, 100000, false, 1, true, 2000)
      await controller.stop(3000, 100000, 1)
      expect(reporter.events.join(',')).assertEqual('started,Pause,stopped:3000')
    })

    it('stream_request_options_reach_engine_without_sharing_headers', 0, () => {
      const stream = new PlaybackStream()
      stream.url = 'https://example.invalid/video'
      stream.headers['Authorization'] = 'test-only'
      stream.referer = 'https://example.invalid/'
      stream.userAgent = 'test-agent'
      stream.proxy = 'http://127.0.0.1:8888'
      stream.isLocalFile = false
      const options = PlaybackOptionsAdapter.fromStream(stream, 42000)
      expect(options.url).assertEqual(stream.url)
      expect(options.headers['Authorization']).assertEqual('test-only')
      expect(options.referer).assertEqual(stream.referer)
      expect(options.userAgent).assertEqual(stream.userAgent)
      expect(options.proxy).assertEqual(stream.proxy)
      expect(options.startPositionMs).assertEqual(42000)
      expect(options.isLocalFile).assertFalse()
      options.headers['Authorization'] = 'changed'
      expect(stream.headers['Authorization']).assertEqual('test-only')
      stream.isLocalFile = true
      stream.localFileSize = 12345
      const local = PlaybackOptionsAdapter.fromStream(stream, -1)
      expect(local.isLocalFile).assertTrue()
      expect(local.localFileSize).assertEqual(12345)
      expect(local.startPositionMs).assertEqual(0)
    })

    it('completed_resume_uses_same_policy_in_page_and_pip', 0, () => {
      expect(PlaybackPosition.normalizeResume(-1, 100000)).assertEqual(0)
      expect(PlaybackPosition.normalizeResume(42000, 0)).assertEqual(42000)
      expect(PlaybackPosition.normalizeResume(42000, 100000)).assertEqual(42000)
      expect(PlaybackPosition.normalizeResume(97000, 100000)).assertEqual(0)
      expect(PlaybackPosition.normalizeResume(995000, 1000000)).assertEqual(0)
      expect(PlaybackPosition.normalizeResume(100001, 100000)).assertEqual(0)
    })

    it('server_snapshot_survives_edits_to_original_account', 0, () => {
      const original = new EmbyServerConfig()
      original.baseUrl = 'https://server-a.invalid'
      original.userId = 'user-a'
      original.accessToken = 'test-token-a'
      original.deviceId = 'device-a'
      const snapshot = original.copy()
      original.baseUrl = 'https://server-b.invalid'
      original.userId = 'user-b'
      original.accessToken = 'test-token-b'
      expect(snapshot.baseUrl).assertEqual('https://server-a.invalid')
      expect(snapshot.userId).assertEqual('user-a')
      expect(snapshot.accessToken).assertEqual('test-token-a')
      expect(snapshot.deviceId).assertEqual('device-a')
    })

    it('stream_expiration_boundary', 0, () => {
      const stream = new PlaybackStream()
      expect(stream.isExpired(10000)).assertFalse()
      stream.expiresAt = 10000
      expect(stream.isExpired(9999)).assertFalse()
      expect(stream.isExpired(10000)).assertTrue()
      expect(stream.isExpired(10001)).assertTrue()
    })

    it('sessions_do_not_share_mutable_defaults', 0, () => {
      const first = PlaybackTestFactory.createSession('test-source-a', 'test-media-a')
      const second = PlaybackTestFactory.createSession('test-source-b', 'test-media-b')
      first.media.title = '第一集'
      first.stream.headers['Authorization'] = 'test-only'
      first.queue.push(LocalPlaybackQueueAdapter.fromRecord(new LocalVideoRecord()))
      expect(second.media.title).assertEqual('')
      expect(Object.keys(second.stream.headers).length).assertEqual(0)
      expect(second.queue.length).assertEqual(0)
    })

    it('manager_registers_unique_sessions_with_isolated_reporters', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const first = PlaybackTestFactory.createSession('test-source-a', 'test-media-a')
      const second = PlaybackTestFactory.createSession('test-source-b', 'test-media-b')
      const reporter = new TestPlaybackReporter()
      const firstId = manager.create(first, reporter)
      const secondId = manager.create(second)
      try {
        expect(firstId.length > 0).assertTrue()
        expect(firstId === secondId).assertFalse()
        expect(manager.get(firstId) === first).assertTrue()
        expect(manager.getReporter(firstId) === reporter).assertTrue()
        expect(manager.getReporter(secondId) === null).assertTrue()
        expect(manager.get('') === null).assertTrue()
      } finally {
        manager.release(firstId)
        manager.release(secondId)
      }
    })

    it('duplicate_id_does_not_replace_session_or_reporter', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const original = PlaybackTestFactory.createSession()
      const reporter = new TestPlaybackReporter()
      const id = manager.create(original, reporter)
      const duplicate = PlaybackTestFactory.createSession()
      duplicate.id = id
      let rejected = false
      try {
        manager.create(duplicate, new TestPlaybackReporter())
      } catch (_error) {
        rejected = true
      }
      try {
        expect(rejected).assertTrue()
        expect(manager.get(id) === original).assertTrue()
        expect(manager.getReporter(id) === reporter).assertTrue()
      } finally {
        manager.release(id)
      }
    })

    it('update_preserves_reporter_and_current_playback_for_pip', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const reporter = new TestPlaybackReporter()
      const id = manager.create(PlaybackTestFactory.createSession(), reporter)
      const current = new PlaybackSession()
      current.media.sourceId = 'test-source'
      current.media.mediaId = 'test-media'
      current.id = id
      current.stream.url = 'https://example.invalid/episode-2'
      current.queueIndex = 1
      current.startPositionMs = 42000
      try {
        manager.update(current)
        expect(manager.get(id) === current).assertTrue()
        expect(manager.get(id)!.queueIndex).assertEqual(1)
        expect(manager.get(id)!.startPositionMs).assertEqual(42000)
        expect(manager.getReporter(id) === reporter).assertTrue()
      } finally {
        manager.release(id)
      }
    })

    it('release_is_idempotent_and_late_update_cannot_resurrect_session', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const session = PlaybackTestFactory.createSession()
      const id = manager.create(session, new TestPlaybackReporter())
      manager.release(id)
      manager.release(id)
      let rejected = false
      try {
        manager.update(session)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
      expect(manager.get(id) === null).assertTrue()
      expect(manager.getReporter(id) === null).assertTrue()
    })

    it('unregistered_session_cannot_be_updated', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      let rejected = false
      try {
        manager.update(new PlaybackSession())
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
      expect(manager.get('') === null).assertTrue()
    })

    it('empty_source_id_is_rejected', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const session = PlaybackTestFactory.createSession('', 'test-media')
      let rejected = false
      try {
        manager.create(session)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
    })

    it('empty_media_id_is_rejected', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const session = PlaybackTestFactory.createSession('test-source', '')
      let rejected = false
      try {
        manager.create(session)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
    })

    it('empty_stream_url_is_rejected', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const session = PlaybackTestFactory.createSession()
      session.stream.url = ''
      let rejected = false
      try {
        manager.create(session)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
    })

    it('reused_id_does_not_retain_released_reporter', 0, () => {
      const manager = PlaybackSessionManager.getInstance()
      const id = manager.create(PlaybackTestFactory.createSession(), new TestPlaybackReporter())
      manager.release(id)
      const next = PlaybackTestFactory.createSession()
      next.id = id
      manager.create(next)
      try {
        expect(manager.getReporter(id) === null).assertTrue()
      } finally {
        manager.release(id)
      }
    })

    it('local_queue_preserves_database_identity_and_resume_metadata', 0, () => {
      const record = new LocalVideoRecord()
      record.fileKey = 'existing-stable-key'
      record.fileUri = 'file://media/视频.mp4'
      record.fileName = '视频.mp4'
      record.fileSize = 1024
      record.coverUri = 'file://cover.jpg'
      record.positionMs = 1234
      record.durationMs = 60000
      const item = LocalPlaybackQueueAdapter.fromRecord(record)
      expect(item.sourceId).assertEqual('local')
      expect(item.mediaId).assertEqual(record.fileKey)
      expect(item.title).assertEqual(record.fileName)
      expect(item.artwork).assertEqual(record.coverUri)
      expect(item.positionMs).assertEqual(1234)
      expect(item.durationMs).assertEqual(60000)
    })

    it('temporary_file_identity_matches_history_key_rules', 0, () => {
      const record = new LocalVideoRecord()
      record.fileUri = 'file://media/视频.mp4'
      record.fileName = '视频.mp4'
      record.fileSize = 1024
      expect(LocalPlaybackQueueAdapter.fromRecord(record).mediaId)
        .assertEqual('file://media/视频.mp4|1024|视频.mp4')
      record.fileUri = ''
      record.durationMs = 60000
      expect(LocalPlaybackQueueAdapter.fromRecord(record).mediaId).assertEqual('视频.mp4|1024|60000')
      expect(record.fileKey).assertEqual('')
    })
  })
}
