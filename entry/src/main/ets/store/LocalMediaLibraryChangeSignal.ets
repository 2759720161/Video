export const LOCAL_MEDIA_LIBRARY_VERSION_KEY = 'localMediaLibraryVersion'

export class LocalMediaLibraryChangeSignal {
  private static version: number = 0

  static notifyChanged(): void {
    const now = Date.now()
    LocalMediaLibraryChangeSignal.version = Math.max(LocalMediaLibraryChangeSignal.version + 1, now)
    if (!AppStorage.set<number>(LOCAL_MEDIA_LIBRARY_VERSION_KEY, LocalMediaLibraryChangeSignal.version)) {
      AppStorage.setOrCreate<number>(LOCAL_MEDIA_LIBRARY_VERSION_KEY, LocalMediaLibraryChangeSignal.version)
    }
  }
}
