export const PLAYBACK_HISTORY_VERSION_KEY: string = 'playbackHistoryVersion'

/** 统一播放历史变更通知；用于首页和历史页及时刷新远程来源记录。 */
export class PlaybackHistoryChangeSignal {
  private static version: number = 0

  static notifyChanged(): void {
    const now = Date.now()
    PlaybackHistoryChangeSignal.version = Math.max(PlaybackHistoryChangeSignal.version + 1, now)
    if (!AppStorage.set<number>(PLAYBACK_HISTORY_VERSION_KEY, PlaybackHistoryChangeSignal.version)) {
      AppStorage.setOrCreate<number>(PLAYBACK_HISTORY_VERSION_KEY, PlaybackHistoryChangeSignal.version)
    }
  }
}
