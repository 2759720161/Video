import { PlaybackSession } from '../../main/ets/core/playback/PlaybackSession'

/** 构造满足 PlaybackSessionManager 严格不变量的测试会话。 */
export class PlaybackTestFactory {
  static createSession(sourceId: string = 'test-source', mediaId: string = 'test-media'): PlaybackSession {
    const session = new PlaybackSession()
    session.media.sourceId = sourceId
    session.media.mediaId = mediaId
    session.media.title = 'Test Media'
    session.stream.url = 'https://example.invalid/media.mp4'
    session.durationMs = 100000
    session.media.durationMs = 100000
    return session
  }
}
