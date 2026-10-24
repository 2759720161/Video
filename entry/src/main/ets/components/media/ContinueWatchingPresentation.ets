export class ContinueWatchingPresentation {
  static width(contentWidth: number): number {
    const width = Number.isFinite(contentWidth) && contentWidth > 0 ? contentWidth : 320
    return Math.min(240, Math.max(120, (width - 12) / 2))
  }
  static time(positionMs: number): string {
    const seconds = Math.floor(Number.isFinite(positionMs) ? Math.max(0, positionMs) / 1000 : 0)
    const minutes = Math.floor(seconds / 60)
    const tail = String(seconds % 60).padStart(2, '0')
    return minutes >= 60 ? Math.floor(minutes / 60) + ':' + String(minutes % 60).padStart(2, '0') + ':' + tail :
      String(minutes).padStart(2, '0') + ':' + tail
  }
}
