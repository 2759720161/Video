export class PlaybackPosition {
  static normalizeResume(positionMs: number, durationMs: number): number {
    if (!Number.isFinite(positionMs) || positionMs <= 0) return 0
    const position = Math.floor(positionMs)
    if (!Number.isFinite(durationMs) || durationMs <= 0) return position
    const duration = Math.floor(durationMs)
    if (duration <= 0) return position
    const boundedPosition = Math.min(position, duration)
    return duration - boundedPosition <= 3000 || boundedPosition / duration >= 0.995 ? 0 : boundedPosition
  }
}
