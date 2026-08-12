export class DanmakuRuntimeStats {
  loadedCount: number = 0
  shownCount: number = 0
  droppedCount: number = 0
  filteredCount: number = 0
  activeCount: number = 0
  trackCount: number = 0
  currentFps: number = 0
  canvasWidth: number = 0
  canvasHeight: number = 0
  lastDropReason: string = ''
  lastFilterReason: string = ''
  matchSource: string = 'none'
  currentEpisodeId: number = 0
  currentAnimeId: number = 0

  resetForEpisode(loadedCount: number = 0): void {
    this.loadedCount = loadedCount
    this.shownCount = 0
    this.droppedCount = 0
    this.filteredCount = 0
    this.activeCount = 0
    this.lastDropReason = ''
    this.lastFilterReason = ''
    this.matchSource = 'none'
    this.currentEpisodeId = 0
    this.currentAnimeId = 0
  }
}
