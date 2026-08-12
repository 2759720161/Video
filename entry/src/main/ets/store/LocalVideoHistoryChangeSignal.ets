export const LOCAL_VIDEO_HISTORY_VERSION_KEY = 'localVideoHistoryVersion'

export class LocalVideoHistoryChangeSignal {
  private static version: number = 0

  static notifyChanged(): void {
    const now = Date.now()
    LocalVideoHistoryChangeSignal.version = Math.max(LocalVideoHistoryChangeSignal.version + 1, now)
    if (!AppStorage.set<number>(LOCAL_VIDEO_HISTORY_VERSION_KEY, LocalVideoHistoryChangeSignal.version)) {
      AppStorage.setOrCreate<number>(LOCAL_VIDEO_HISTORY_VERSION_KEY, LocalVideoHistoryChangeSignal.version)
    }
  }
}
