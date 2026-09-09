import { PlaybackOptions, PlayerState } from '../core/player/IPlayerEngine'

export class NowPlayingSnapshot {
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

export class NowPlayingActions {
  onPlay?: () => void
  onPause?: () => void
  onSeek?: (positionMs: number) => void
  onFastForward?: (positionMs: number) => void
  onRewind?: (positionMs: number) => void
  onNext?: () => void
  onPrevious?: () => void
}

export class NowPlayingStore {
  private static instance: NowPlayingStore | null = null

  private snapshot: NowPlayingSnapshot = new NowPlayingSnapshot()
  private actions: NowPlayingActions = new NowPlayingActions()
  private listeners: Map<number, (snapshot: NowPlayingSnapshot) => void> = new Map()
  private nextListenerId: number = 1

  static getInstance(): NowPlayingStore {
    if (NowPlayingStore.instance === null) {
      NowPlayingStore.instance = new NowPlayingStore()
    }
    return NowPlayingStore.instance
  }

  getSnapshot(): NowPlayingSnapshot {
    return this.cloneSnapshot(this.snapshot)
  }

  subscribe(listener: (snapshot: NowPlayingSnapshot) => void): number {
    const id = this.nextListenerId
    this.nextListenerId++
    this.listeners.set(id, listener)
    listener(this.cloneSnapshot(this.snapshot))
    return id
  }

  unsubscribe(id: number): void {
    this.listeners.delete(id)
  }

  setActions(actions: NowPlayingActions, owner: string): void {
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    if (normalizedOwner.length === 0) {
      return
    }
    this.actions = actions
    this.snapshot.owner = normalizedOwner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  clearActions(owner: string): void {
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    if (normalizedOwner.length === 0 || this.snapshot.owner !== normalizedOwner) {
      return
    }
    this.actions = new NowPlayingActions()
    this.snapshot.owner = ''
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updateMediaFromOptions(options: PlaybackOptions, title: string, subtitle: string, cover: string,
    durationMs: number, hasNext: boolean, hasPrevious: boolean, owner: string): void {
    if (!this.acceptOwner(owner)) {
      return
    }
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    this.snapshot.url = options.url
    this.snapshot.title = title
    this.snapshot.subtitle = subtitle
    this.snapshot.cover = cover
    this.snapshot.isLocalFile = options.isLocalFile
    // A queue switch can publish the new stream before the engine emits its
    // first prepared state. Publish the resolver's start position immediately
    // so system controls and PiP do not briefly expose the previous item's
    // progress.
    this.snapshot.durationMs = NowPlayingStore.normalizeNonNegative(durationMs)
    this.snapshot.positionMs = NowPlayingStore.normalizePosition(options.startPositionMs, this.snapshot.durationMs)
    this.snapshot.hasNext = hasNext
    this.snapshot.hasPrevious = hasPrevious
    this.snapshot.owner = normalizedOwner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updateMedia(url: string, title: string, subtitle: string, cover: string, durationMs: number,
    positionMs: number, hasNext: boolean, hasPrevious: boolean, isLocalFile: boolean, owner: string): void {
    if (!this.acceptOwner(owner)) {
      return
    }
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    this.snapshot.url = url
    this.snapshot.title = title
    this.snapshot.subtitle = subtitle
    this.snapshot.cover = cover
    this.snapshot.durationMs = NowPlayingStore.normalizeNonNegative(durationMs)
    this.snapshot.positionMs = NowPlayingStore.normalizePosition(positionMs, this.snapshot.durationMs)
    this.snapshot.hasNext = hasNext
    this.snapshot.hasPrevious = hasPrevious
    this.snapshot.isLocalFile = isLocalFile
    this.snapshot.owner = normalizedOwner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updatePlayerState(state: PlayerState, owner: string): void {
    if (!this.acceptOwner(owner)) {
      return
    }
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    this.snapshot.playing = state.playing
    if (Number.isFinite(state.durationMs) && state.durationMs > 0) {
      this.snapshot.durationMs = NowPlayingStore.normalizeNonNegative(state.durationMs)
    }
    this.snapshot.positionMs = NowPlayingStore.normalizePosition(state.positionMs, this.snapshot.durationMs)
    if (Number.isFinite(state.videoWidth) && state.videoWidth > 0) {
      this.snapshot.videoWidth = state.videoWidth
    }
    if (Number.isFinite(state.videoHeight) && state.videoHeight > 0) {
      this.snapshot.videoHeight = state.videoHeight
    }
    if (Number.isFinite(state.speed) && state.speed > 0) {
      this.snapshot.speed = state.speed
    }
    this.snapshot.owner = normalizedOwner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updatePlayback(positionMs: number, playing: boolean, owner: string): void {
    if (!this.acceptOwner(owner)) {
      return
    }
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    this.snapshot.positionMs = NowPlayingStore.normalizePosition(positionMs, this.snapshot.durationMs)
    this.snapshot.playing = playing
    this.snapshot.owner = normalizedOwner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  updateEpisodeAvailability(hasNext: boolean, hasPrevious: boolean, owner: string): void {
    if (!this.acceptOwner(owner)) {
      return
    }
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    this.snapshot.hasNext = hasNext
    this.snapshot.hasPrevious = hasPrevious
    this.snapshot.owner = normalizedOwner
    this.snapshot.updatedAtMs = Date.now()
    this.notify()
  }

  reset(owner: string): void {
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    if (normalizedOwner.length === 0 ||
      (this.snapshot.owner.length > 0 && this.snapshot.owner !== normalizedOwner)) {
      return
    }
    this.snapshot = new NowPlayingSnapshot()
    this.actions = new NowPlayingActions()
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
      this.actions.onSeek(NowPlayingStore.normalizePosition(positionMs, this.snapshot.durationMs))
    }
  }

  requestFastForward(positionMs: number): void {
    const normalizedPositionMs = NowPlayingStore.normalizePosition(positionMs, this.snapshot.durationMs)
    if (this.actions.onFastForward !== undefined) {
      this.actions.onFastForward(normalizedPositionMs)
    } else {
      this.requestSeek(normalizedPositionMs)
    }
  }

  requestRewind(positionMs: number): void {
    const normalizedPositionMs = NowPlayingStore.normalizePosition(positionMs, this.snapshot.durationMs)
    if (this.actions.onRewind !== undefined) {
      this.actions.onRewind(normalizedPositionMs)
    } else {
      this.requestSeek(normalizedPositionMs)
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
    this.listeners.forEach((listener: (snapshot: NowPlayingSnapshot) => void) => {
      try {
        listener(snapshot)
      } catch (_) {
        // 一个页面或系统订阅者失效时，不能阻断其他播控订阅者的同步。
      }
    })
  }

  private acceptOwner(owner: string): boolean {
    const normalizedOwner = NowPlayingStore.normalizeOwner(owner)
    if (normalizedOwner.length === 0) {
      return false
    }
    return this.snapshot.owner.length === 0 || this.snapshot.owner === normalizedOwner
  }

  private static normalizeOwner(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private cloneSnapshot(source: NowPlayingSnapshot): NowPlayingSnapshot {
    const cloned = new NowPlayingSnapshot()
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

  private static normalizeNonNegative(value: number): number {
    return Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0
  }

  private static normalizePosition(value: number, durationMs: number): number {
    const positionMs = NowPlayingStore.normalizeNonNegative(value)
    const normalizedDurationMs = NowPlayingStore.normalizeNonNegative(durationMs)
    return normalizedDurationMs > 0 ? Math.min(positionMs, normalizedDurationMs) : positionMs
  }
}
