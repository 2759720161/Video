import { PlaybackOptions, PlayerState } from '../core/player/IPlayerEngine'

export class PlaybackSessionSnapshot {
  url: string = ''
  title: string = ''
  subtitle: string = ''
  cover: string = ''
  durationMs: number = 0
  positionMs: number = 0
  playing: boolean = false
  hasNext: boolean = false
  hasPrevious: boolean = false
  isLocalFile: boolean = false
  videoWidth: number = 0
  videoHeight: number = 0
  speed: number = 1.0
  updatedAtMs: number = 0
  owner: string = ''
}

export class PlaybackSessionActions {
  onPlay?: () => void
  onPause?: () => void
  onSeek?: (positionMs: number) => void
  onFastForward?: (positionMs: number) => void
  onRewind?: (positionMs: number) => void
  onNext?: () => void
  onPrevious?: () => void
}

export class PlaybackSessionStore {
  private static instance: PlaybackSessionStore | null = null

  private snapshot: PlaybackSessionSnapshot = new PlaybackSessionSnapshot()
  private actions: PlaybackSessionActions = new PlaybackSessionActions()
  private listeners: Map<number, (snapshot: PlaybackSessionSnapshot) => void> = new Map()
  private nextListenerId: number = 1

  static getInstance(): PlaybackSessionStore {
    if (PlaybackSessionStore.instance === null) {
      PlaybackSessionStore.instance = new PlaybackSessionStore()
    }
    return PlaybackSessionStore.instance
  }

  getSnapshot(): PlaybackSessionSnapshot {
    return this.cloneSnapshot(this.snapshot)
  }

  subscribe(listener: (snapshot: PlaybackSessionSnapshot) => void): number {
    const id = this.nextListenerId
    this.nextListenerId++
    this.listeners.set(id, listener)
    listener(this.cloneSnapshot(this.snapshot))
    return id
  }

  unsubscribe(id: number): void {
    this.listeners.delete(id)
  }

  setActions(actions: PlaybackSessionActions, owner: string): void {
    this.actions = actions
    this.snapshot.owner = owner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  clearActions(owner: string): void {
    if (this.snapshot.owner !== owner) {
      return
    }
    this.actions = new PlaybackSessionActions()
    this.snapshot.owner = ''
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updateMediaFromOptions(options: PlaybackOptions, title: string, subtitle: string, cover: string,
    hasNext: boolean, hasPrevious: boolean, owner: string): void {
    this.snapshot.url = options.url
    this.snapshot.title = title
    this.snapshot.subtitle = subtitle
    this.snapshot.cover = cover
    this.snapshot.isLocalFile = options.isLocalFile
    this.snapshot.hasNext = hasNext
    this.snapshot.hasPrevious = hasPrevious
    this.snapshot.owner = owner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updateMedia(url: string, title: string, subtitle: string, cover: string, durationMs: number,
    positionMs: number, hasNext: boolean, hasPrevious: boolean, isLocalFile: boolean, owner: string): void {
    this.snapshot.url = url
    this.snapshot.title = title
    this.snapshot.subtitle = subtitle
    this.snapshot.cover = cover
    this.snapshot.durationMs = Math.max(0, durationMs)
    this.snapshot.positionMs = Math.max(0, positionMs)
    this.snapshot.hasNext = hasNext
    this.snapshot.hasPrevious = hasPrevious
    this.snapshot.isLocalFile = isLocalFile
    this.snapshot.owner = owner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updatePlayerState(state: PlayerState, owner: string): void {
    this.snapshot.playing = state.playing
    this.snapshot.positionMs = Math.max(0, state.positionMs)
    if (state.durationMs > 0) {
      this.snapshot.durationMs = state.durationMs
    }
    if (state.videoWidth > 0) {
      this.snapshot.videoWidth = state.videoWidth
    }
    if (state.videoHeight > 0) {
      this.snapshot.videoHeight = state.videoHeight
    }
    if (state.speed > 0) {
      this.snapshot.speed = state.speed
    }
    this.snapshot.owner = owner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updatePlayback(positionMs: number, playing: boolean, owner: string): void {
    this.snapshot.positionMs = Math.max(0, positionMs)
    this.snapshot.playing = playing
    this.snapshot.owner = owner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updateEpisodeAvailability(hasNext: boolean, hasPrevious: boolean, owner: string): void {
    this.snapshot.hasNext = hasNext
    this.snapshot.hasPrevious = hasPrevious
    this.snapshot.owner = owner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  reset(owner: string): void {
    if (this.snapshot.owner.length > 0 && this.snapshot.owner !== owner) {
      return
    }
    this.snapshot = new PlaybackSessionSnapshot()
    this.actions = new PlaybackSessionActions()
    this.notify()
  }

  requestPlay(): void {
    if (this.actions.onPlay !== undefined) {
      this.actions.onPlay()
    }
  }

  requestPause(): void {
    if (this.actions.onPause !== undefined) {
      this.actions.onPause()
    }
  }

  requestSeek(positionMs: number): void {
    if (this.actions.onSeek !== undefined) {
      this.actions.onSeek(positionMs)
    }
  }

  requestFastForward(positionMs: number): void {
    if (this.actions.onFastForward !== undefined) {
      this.actions.onFastForward(positionMs)
    } else {
      this.requestSeek(positionMs)
    }
  }

  requestRewind(positionMs: number): void {
    if (this.actions.onRewind !== undefined) {
      this.actions.onRewind(positionMs)
    } else {
      this.requestSeek(positionMs)
    }
  }

  requestNext(): void {
    if (this.snapshot.hasNext && this.actions.onNext !== undefined) {
      this.actions.onNext()
    }
  }

  requestPrevious(): void {
    if (this.snapshot.hasPrevious && this.actions.onPrevious !== undefined) {
      this.actions.onPrevious()
    }
  }

  private notify(): void {
    const snapshot = this.cloneSnapshot(this.snapshot)
    this.listeners.forEach((listener: (snapshot: PlaybackSessionSnapshot) => void) => {
      listener(snapshot)
    })
  }

  private cloneSnapshot(source: PlaybackSessionSnapshot): PlaybackSessionSnapshot {
    const cloned = new PlaybackSessionSnapshot()
    cloned.url = source.url
    cloned.title = source.title
    cloned.subtitle = source.subtitle
    cloned.cover = source.cover
    cloned.durationMs = source.durationMs
    cloned.positionMs = source.positionMs
    cloned.playing = source.playing
    cloned.hasNext = source.hasNext
    cloned.hasPrevious = source.hasPrevious
    cloned.isLocalFile = source.isLocalFile
    cloned.videoWidth = source.videoWidth
    cloned.videoHeight = source.videoHeight
    cloned.speed = source.speed
    cloned.updatedAtMs = source.updatedAtMs
    cloned.owner = source.owner
    return cloned
  }
}
