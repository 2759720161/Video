export const PREFS_KEY_PLAYER_DEFAULT_SPEED: string = 'playerDefaultSpeed'
export const PREFS_KEY_PLAYER_SEEK_SECONDS: string = 'playerSeekSeconds'

export const PLAYER_DEFAULT_SPEED: number = 1.0
export const PLAYER_SEEK_SECONDS_DEFAULT: number = 15

export function normalizePlayerSpeed(value: number): number {
  const supported: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
  let closest: number = PLAYER_DEFAULT_SPEED
  let distance: number = Number.MAX_VALUE
  for (let i = 0; i < supported.length; i++) {
    const nextDistance = Math.abs(value - supported[i])
    if (nextDistance < distance) {
      closest = supported[i]
      distance = nextDistance
    }
  }
  return closest
}

export function normalizeSeekSeconds(value: number): number {
  if (value <= 10) {
    return 10
  }
  if (value >= 30) {
    return 30
  }
  return 15
}
