import { PiPWindow, router, typeNode } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { IPlayerEngine, PlaybackOptions, PlayerState } from '../core/player/IPlayerEngine'
import { PlayerEngineFactory } from '../core/player/PlayerEngineFactory'
import { AVPlayerEngine } from '../core/player/AVPlayerEngine'
import { PlaybackSession } from '../core/playback/PlaybackSession'
import { PlaybackQueueItem } from '../core/playback/PlaybackQueueItem'
import { PlaybackOptionsAdapter } from '../core/playback/PlaybackOptionsAdapter'
import { PlaybackPosition } from '../core/playback/PlaybackPosition'
import { PlaybackSessionManager } from './PlaybackSessionManager'
import { PIP_PLAYBACK_OWNER_ID } from '../core/playback/PlaybackOwnerIds'
import { Logger } from '../utils/Logger'
import { NowPlayingActions, NowPlayingStore } from './NowPlayingStore'

const logger = new Logger('TypeNodePiPSession')
const PIP_OWNER_ID: string = PIP_PLAYBACK_OWNER_ID

export class TypeNodePiPRoute {
  url: string = ''
  params: Record<string, Object> = {}
}

class PiPXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    TypeNodePiPSession.getInstance().onSurfaceCreated(surfaceId)
  }

  onSurfaceDestroyed(_surfaceId: string): void {
  }
}

export class TypeNodePiPSession {
  private static instance: TypeNodePiPSession | null = null

  private pipController: PiPWindow.PiPController | null = null
  private xComponentController: PiPXComponentController = new PiPXComponentController()
  private xComponent: typeNode.XComponent | null = null
  private playerEngine: IPlayerEngine | null = null
  private playbackOptions: PlaybackOptions | null = null
  private uiContext: UIContext | null = null
  private route: TypeNodePiPRoute = new TypeNodePiPRoute()
  private surfaceId: string = ''
  private lastState: PlayerState = new PlayerState()
  private initialPositionMs: number = 0
  private syntheticPositionMs: number = 0
  private lastClockMs: number = 0
  private clockPlaying: boolean = false
  private desiredPlaying: boolean = true
  private isCreating: boolean = false
  private isActive: boolean = false
  private isRestoring: boolean = false
  private queueSwitchToken: number = 0
  private completed: boolean = false
  private ownsSession: boolean = false
  private sessionManager: PlaybackSessionManager = PlaybackSessionManager.getInstance()
  private nowPlayingStore: NowPlayingStore = NowPlayingStore.getInstance()

  static getInstance(): TypeNodePiPSession {
    if (TypeNodePiPSession.instance === null) {
      TypeNodePiPSession.instance = new TypeNodePiPSession()
    }
    return TypeNodePiPSession.instance
  }

  isRunning(): boolean {
    return this.isActive || this.isCreating
  }

  getPositionMs(): number {
    this.syncPlaybackClock()
    return this.getCurrentPositionMs()
  }

  async start(context: common.UIAbilityContext, uiContext: UIContext, options: PlaybackOptions,
    route: TypeNodePiPRoute, contentWidth: number, contentHeight: number,
    defaultWindowSizeType: number, initialPlaying: boolean = true): Promise<boolean> {
    const normalizedRoute = this.normalizeRoute(route)
    if (normalizedRoute === null) {
      logger.warn('拒绝启动缺少 sessionId 的 PiP 路由')
      return false
    }
    if (this.isActive || this.isCreating) {
      return this.route.params['sessionId'] === normalizedRoute.params['sessionId']
    }
    if (!PiPWindow.isPiPEnabled()) {
      return false
    }

    this.isCreating = true
    this.completed = false
    this.ownsSession = false
    this.isRestoring = false
    this.route = normalizedRoute
    this.uiContext = uiContext
    this.playbackOptions = this.clonePlaybackOptions(options)
    this.lastState = new PlayerState()
    this.initialPositionMs = this.normalizePosition(options.startPositionMs)
    this.lastState.positionMs = this.initialPositionMs
    this.syntheticPositionMs = this.initialPositionMs
    this.lastClockMs = Date.now()
    this.clockPlaying = initialPlaying
    this.desiredPlaying = initialPlaying
    this.surfaceId = ''
    this.registerPlaybackStoreActions()
    this.syncPlaybackStoreMedia()
    this.nowPlayingStore.updatePlayback(this.initialPositionMs, initialPlaying, PIP_OWNER_ID)

    try {
      this.xComponent = typeNode.createNode(uiContext, 'XComponent', {
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })

      const safeWidth = contentWidth > 0 ? contentWidth : 1920
      const safeHeight = contentHeight > 0 ? contentHeight : 1080
      const config: PiPWindow.PiPConfiguration = {
        context: context,
        componentController: this.xComponentController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: safeWidth,
        contentHeight: safeHeight,
        controlGroups: [PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT],
        defaultWindowSizeType: defaultWindowSizeType
      }

      this.pipController = await PiPWindow.create(config, this.xComponent)
      this.registerListeners()
      await this.pipController.startPiP()
      this.updatePlayPauseControlStatus(initialPlaying)
      this.updateEpisodeControlStatus()
      this.isCreating = false
      this.isActive = true
      this.ownsSession = true
      logger.info('TypeNode PiP started')
      return true
    } catch (err) {
      const businessError = err as BusinessError
      logger.warn('TypeNode PiP start failed: %{public}d - %{public}s', businessError.code, businessError.message)
      this.release(true, false)
      return false
    }
  }

  async onSurfaceCreated(surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId
    if (this.playbackOptions === null) {
      return
    }
    await this.prepareEngine()
  }

  private async prepareEngine(): Promise<void> {
    if (this.playerEngine !== null || this.playbackOptions === null || this.surfaceId.length === 0) {
      return
    }
    const options = this.playbackOptions
    let engine: IPlayerEngine
    if (options.isLocalFile) {
      logger.info('TypeNode PiP uses AVPlayer for local file')
      engine = new AVPlayerEngine()
    } else {
      engine = await PlayerEngineFactory.create()
    }
    if (this.playbackOptions !== options || !this.isRunning()) {
      engine.release()
      return
    }
    this.playerEngine = engine
    this.playerEngine.setSurfaceId(this.surfaceId)
    this.playerEngine.onStateChange((state: PlayerState) => {
      if (this.isRestoring || this.playerEngine !== engine) return
      this.syncPlaybackClock()
      this.lastState = state
      this.nowPlayingStore.updatePlayerState(state, PIP_OWNER_ID)
      const session = this.getSession()
      if (session !== null && !this.isRestoring) {
        const normalizedStateDurationMs = PlaybackQueueItem.normalizeDurationMs(state.durationMs)
        if (normalizedStateDurationMs > 0) session.durationMs = normalizedStateDurationMs
        const normalizedStatePositionMs = this.normalizePosition(state.positionMs, session.durationMs)
        const transientState = state.stateName === 'creating' || state.stateName === 'initialized' ||
          state.stateName === 'preparing' || state.stateName === 'prepared'
        // During a new file's prepare phase some engines briefly report zero
        // before applying the requested resume position. Preserve the session
        // start point until a meaningful position or a steady state arrives.
        if (!transientState || normalizedStatePositionMs > 0) {
          session.startPositionMs = normalizedStatePositionMs
          if (session.queueIndex >= 0 && session.queueIndex < session.queue.length) {
            session.queue[session.queueIndex].positionMs = normalizedStatePositionMs
            if (session.durationMs > 0) {
              session.queue[session.queueIndex].durationMs = session.durationMs
            }
          }
        }
        this.sessionManager.update(session)
        const controller = this.sessionManager.getReportController(session.id)
        if (controller !== null && state.error.length === 0 && !state.completed && !this.completed) {
          controller.update(state.positionMs, state.durationMs, state.playing, state.speed,
            state.stateName === 'prepared' || state.stateName === 'playing' || state.playing)
        }
        if (state.completed && !this.completed) {
          this.completed = true
          if (controller !== null) void controller.stop(state.positionMs, state.durationMs, state.speed)
        }
      }
      if (Number.isFinite(state.positionMs) && state.positionMs > 0) {
        this.syntheticPositionMs = Math.max(this.syntheticPositionMs,
          this.normalizePosition(state.positionMs, state.durationMs))
      }
      if (state.completed || state.stateName === 'completed' || state.stateName === 'stopped' ||
        state.stateName === 'error') {
        this.desiredPlaying = false
        this.syncPlaybackClock(false)
      }
      if (this.pipController !== null) {
        if (state.playing) {
          this.updatePlayPauseControlStatus(true)
        } else if (state.stateName === 'paused' || state.completed || state.stateName === 'completed' ||
          state.stateName === 'stopped' || state.stateName === 'error') {
          this.updatePlayPauseControlStatus(false)
        } else {
          this.updatePlayPauseControlStatus(this.desiredPlaying)
        }
        if (state.videoWidth > 0 && state.videoHeight > 0) {
          try {
            this.pipController.updateContentSize(state.videoWidth, state.videoHeight)
          } catch (_err) {
          }
        }
      }
      if (!this.desiredPlaying && state.playing && this.playerEngine !== null) {
        this.playerEngine.pause()
      }
    })
    this.playerEngine.prepare(this.playbackOptions)
  }

  private registerListeners(): void {
    if (this.pipController === null) {
      return
    }
    this.pipController.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
      logger.info('TypeNode PiP stateChange: state=%{public}d reason=%{public}s', state, reason)
      switch (state) {
        case PiPWindow.PiPState.STARTED:
          this.isActive = true
          this.isCreating = false
          break
        case PiPWindow.PiPState.ABOUT_TO_RESTORE:
          this.restoreToPlayerPage()
          break
        case PiPWindow.PiPState.STOPPED:
          if (reason === 'panelActionRestore') {
            this.restoreToPlayerPage()
            break
          }
          if (!this.isRestoring) {
            this.release()
          }
          break
        case PiPWindow.PiPState.ERROR:
          this.release()
          break
        default:
          break
      }
    })

    this.pipController.on('controlEvent', (control: PiPWindow.ControlEventParam) => {
      this.handleControlEvent(control)
    })
  }

  private handleControlEvent(control: PiPWindow.ControlEventParam): void {
    logger.info('TypeNode PiP controlEvent: controlType=%{public}d status=%{public}s',
      control.controlType, String(control.status))
    switch (control.controlType) {
      case PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE:
        if (control.status === PiPWindow.PiPControlStatus.PLAY) {
          this.desiredPlaying = true
          this.syncPlaybackClock(true)
          this.nowPlayingStore.updatePlayback(this.getCurrentPositionMs(), true, PIP_OWNER_ID)
          if (this.playerEngine !== null) {
            this.playerEngine.play()
          }
        } else {
          this.desiredPlaying = false
          this.syncPlaybackClock(false)
          this.nowPlayingStore.updatePlayback(this.getCurrentPositionMs(), false, PIP_OWNER_ID)
          if (this.playerEngine !== null) {
            this.playerEngine.pause()
          }
        }
        break
      case PiPWindow.PiPControlType.VIDEO_NEXT:
        this.switchEpisode(1)
        break
      case PiPWindow.PiPControlType.VIDEO_PREVIOUS:
        this.switchEpisode(-1)
        break
      case PiPWindow.PiPControlType.FAST_FORWARD:
        this.seekPiP(Math.min(this.getCurrentPositionMs() + 15000, this.getCurrentDurationMs()))
        break
      case PiPWindow.PiPControlType.FAST_BACKWARD:
        this.seekPiP(Math.max(0, this.getCurrentPositionMs() - 15000))
        break
      default:
        break
    }
  }

  private updatePlayPauseControlStatus(playing: boolean): void {
    if (this.pipController === null) {
      return
    }
    try {
      this.pipController.updatePiPControlStatus(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE
      )
    } catch (_err) {
    }
  }

  private updateEpisodeControlStatus(): void {
    if (this.pipController === null) {
      return
    }
    try {
      this.pipController.setPiPControlEnabled(
        PiPWindow.PiPControlType.VIDEO_PREVIOUS, this.hasAdjacentItem(-1))
      this.pipController.setPiPControlEnabled(
        PiPWindow.PiPControlType.VIDEO_NEXT, this.hasAdjacentItem(1))
    } catch (_err) {
      logger.warn('Update TypeNode PiP episode controls failed')
    }
  }

  private getSession(): PlaybackSession | null {
    const id = this.route.params['sessionId']
    return typeof id === 'string' ? this.sessionManager.get(id) : null
  }

  /** PiP 只接收启动会话键；复制参数避免调用方后续修改原对象。 */
  private normalizeRoute(route: TypeNodePiPRoute): TypeNodePiPRoute | null {
    const rawSessionId = route.params['sessionId']
    if (typeof rawSessionId !== 'string' || rawSessionId.trim().length === 0) return null
    const normalized = new TypeNodePiPRoute()
    normalized.url = route.url
    // PiP only carries the process-local session key. Copying legacy route
    // payloads here would let URI/source-specific parameters leak back into
    // the unified PlayerPage route.
    normalized.params['sessionId'] = rawSessionId.trim()
    return normalized
  }

  private hasAdjacentItem(direction: number): boolean {
    const session = this.getSession()
    if (session === null || this.sessionManager.getResolver(session.id) === null) return false
    const index = session.queueIndex + direction
    return session.queueIndex >= 0 && index >= 0 && index < session.queue.length
  }

  private async switchEpisode(direction: number): Promise<void> {
    const session = this.getSession()
    if (this.isRestoring || session === null || !this.hasAdjacentItem(direction)) return
    const resolver = this.sessionManager.getResolver(session.id)
    if (resolver === null) return
    const token = ++this.queueSwitchToken
    const index = session.queueIndex + direction
    try {
      const selected = session.queue[index]
      const next = await resolver.resolvePlayback(selected)
      const hasValidStructure = next !== null && typeof next === 'object' &&
        next.media !== null && typeof next.media === 'object' && !Array.isArray(next.media) &&
        next.stream !== null && typeof next.stream === 'object' && !Array.isArray(next.stream)
      const nextSourceId = hasValidStructure ? TypeNodePiPSession.normalizeText(next.media.sourceId) : ''
      const nextMediaId = hasValidStructure ? TypeNodePiPSession.normalizeText(next.media.mediaId) : ''
      const selectedSourceId = selected !== null && typeof selected === 'object' ?
        TypeNodePiPSession.normalizeText(selected.sourceId) : ''
      const selectedMediaId = selected !== null && typeof selected === 'object' ?
        TypeNodePiPSession.normalizeText(selected.mediaId) : ''
      if (!hasValidStructure || nextSourceId !== selectedSourceId || nextMediaId !== selectedMediaId) {
        throw new Error('Provider 返回的播放会话身份不匹配')
      }
      if (token !== this.queueSwitchToken || this.getSession() !== session || !this.isRunning() || this.isRestoring) return
      this.refreshEngineState()
      session.queue[session.queueIndex].positionMs = PlaybackQueueItem.normalizePositionMs(this.getCurrentPositionMs())
      session.queue[session.queueIndex].durationMs = PlaybackQueueItem.normalizeDurationMs(session.durationMs)
      const reporter = this.sessionManager.getReportController(session.id)
      if (reporter !== null) await reporter.stop(this.getCurrentPositionMs(), session.durationMs, this.lastState.speed)
      if (token !== this.queueSwitchToken || this.getSession() !== session || !this.isRunning() || this.isRestoring) return
      next.id = session.id
      next.queue = session.queue
      next.queueIndex = index
      next.startPositionMs = PlaybackPosition.normalizeResume(next.startPositionMs, next.durationMs)
      if (index >= 0 && index < next.queue.length) {
        next.queue[index].positionMs = PlaybackQueueItem.normalizePositionMs(next.startPositionMs)
        next.queue[index].durationMs = PlaybackQueueItem.normalizeDurationMs(next.durationMs)
        if (next.queue[index].durationMs > 0) {
          next.queue[index].positionMs = Math.min(next.queue[index].positionMs, next.queue[index].durationMs)
        }
      }
      this.sessionManager.update(next)
      this.sessionManager.replaceReporter(session.id, resolver.createReporterForSession(next))
      if (this.playerEngine !== null) {
        this.playerEngine.onStateChange((_state: PlayerState) => {})
        this.playerEngine.release()
        this.playerEngine = null
      }
      this.playbackOptions = PlaybackOptionsAdapter.fromStream(next.stream, next.startPositionMs)
      this.initialPositionMs = next.startPositionMs
      this.syntheticPositionMs = next.startPositionMs
      this.lastState = new PlayerState()
      this.lastState.positionMs = next.startPositionMs
      this.lastClockMs = Date.now()
      this.desiredPlaying = true
      this.clockPlaying = true
      this.completed = false
      this.syncPlaybackStoreMedia()
      this.updateEpisodeControlStatus()
      await this.prepareEngine()
    } catch (err) {
      logger.warn('PiP queue switch failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private restoreToPlayerPage(): void {
    if (this.isRestoring) {
      return
    }
    this.isRestoring = true
    this.navigateToPlayerPage()
  }

  private navigateToPlayerPage(positionOverrideMs?: number): void {
    this.refreshEngineState()
    this.syncPlaybackClock()
    const params: Record<string, Object> = {}
    const keys = Object.keys(this.route.params)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      params[key] = this.route.params[key]
    }
    const session = this.getSession()
    const requestedPositionMs = positionOverrideMs !== undefined ? positionOverrideMs :
      Math.max(this.getCurrentPositionMs(), this.initialPositionMs)
    const restoredPositionMs = this.normalizePosition(requestedPositionMs,
      session === null ? 0 : session.durationMs)
    if (session !== null) {
      session.startPositionMs = restoredPositionMs
      if (session.queueIndex >= 0 && session.queueIndex < session.queue.length) {
        session.queue[session.queueIndex].positionMs = restoredPositionMs
        const sessionDurationMs = PlaybackQueueItem.normalizeDurationMs(session.durationMs)
        if (sessionDurationMs > 0) session.queue[session.queueIndex].durationMs = sessionDurationMs
      }
      this.sessionManager.update(session)
    }
    logger.info('Restore player page from TypeNode PiP position=%{public}d initial=%{public}d last=%{public}d synthetic=%{public}d',
      restoredPositionMs, this.initialPositionMs, this.lastState.positionMs, this.syntheticPositionMs)
    if (this.uiContext !== null) {
      this.uiContext.getRouter().pushUrl({
        url: this.route.url,
        params: params
      }).then(() => {
        this.release(false, false)
      }).catch((err: Error) => {
        logger.warn('Restore player page failed: %{public}s', err.message)
        this.release(true)
      })
      return
    }
    router.pushUrl({
      url: this.route.url,
      params: params
    }).then(() => {
      this.release(false, false)
    }).catch((err: Error) => {
      logger.warn('Restore player page failed: %{public}s', err.message)
      this.release(true)
    })
  }

  private registerPlaybackStoreActions(): void {
    const actions = new NowPlayingActions()
    actions.onPlay = () => {
      this.desiredPlaying = true
      this.syncPlaybackClock(true)
      this.updatePlayPauseControlStatus(true)
      this.nowPlayingStore.updatePlayback(this.getCurrentPositionMs(), true, PIP_OWNER_ID)
      if (this.playerEngine !== null) {
        this.playerEngine.play()
      }
    }
    actions.onPause = () => {
      this.desiredPlaying = false
      this.syncPlaybackClock(false)
      this.updatePlayPauseControlStatus(false)
      this.nowPlayingStore.updatePlayback(this.getCurrentPositionMs(), false, PIP_OWNER_ID)
      if (this.playerEngine !== null) {
        this.playerEngine.pause()
      }
    }
    actions.onSeek = (positionMs: number) => {
      this.seekPiP(positionMs)
    }
    actions.onFastForward = (positionMs: number) => {
      this.seekPiP(positionMs)
    }
    actions.onRewind = (positionMs: number) => {
      this.seekPiP(positionMs)
    }
    actions.onNext = () => {
      this.switchEpisode(1)
    }
    actions.onPrevious = () => {
      this.switchEpisode(-1)
    }
    this.nowPlayingStore.setActions(actions, PIP_OWNER_ID)
  }

  private syncPlaybackStoreMedia(): void {
    if (this.playbackOptions === null) {
      return
    }
    const session = this.getSession()
    if (session === null) return
    this.nowPlayingStore.updateMediaFromOptions(this.playbackOptions, session.media.title,
      session.media.subtitle, session.media.artwork, session.durationMs,
      this.hasAdjacentItem(1), this.hasAdjacentItem(-1), PIP_OWNER_ID)
  }

  private clonePlaybackOptions(options: PlaybackOptions): PlaybackOptions {
    const cloned = new PlaybackOptions()
    cloned.url = options.url
    cloned.startPositionMs = options.startPositionMs
    cloned.referer = options.referer
    cloned.userAgent = options.userAgent
    cloned.proxy = options.proxy
    cloned.streamMetadata = options.streamMetadata
    cloned.isLocalFile = options.isLocalFile
    cloned.localFileSize = options.localFileSize
    const keys = Object.keys(options.headers)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      cloned.headers[key] = options.headers[key]
    }
    return cloned
  }

  private refreshEngineState(): void {
    if (this.playerEngine === null) {
      return
    }
    try {
      const state = this.playerEngine.getState()
      this.lastState = state
      if (Number.isFinite(state.positionMs) && state.positionMs > 0) {
        this.syntheticPositionMs = Math.max(this.syntheticPositionMs, state.positionMs)
      }
    } catch (_err) {
    }
  }

  private syncPlaybackClock(playing?: boolean): void {
    const now = Date.now()
    if (this.clockPlaying && this.lastClockMs > 0 && now > this.lastClockMs) {
      this.syntheticPositionMs += now - this.lastClockMs
    }
    this.lastClockMs = now
    if (playing !== undefined) {
      this.clockPlaying = playing
    }
  }

  private getCurrentPositionMs(): number {
    const enginePositionMs = Number.isFinite(this.lastState.positionMs) && this.lastState.positionMs > 0 ?
      this.lastState.positionMs : 0
    return this.normalizePosition(Math.max(enginePositionMs, this.syntheticPositionMs, this.initialPositionMs),
      this.getCurrentDurationMs())
  }

  private getCurrentDurationMs(): number {
    if (Number.isFinite(this.lastState.durationMs) && this.lastState.durationMs > 0) {
      return this.lastState.durationMs
    }
    return Number.MAX_SAFE_INTEGER
  }

  private normalizePosition(value: number, durationMs: number = 0): number {
    if (!Number.isFinite(value) || value <= 0) return 0
    const position = Math.floor(value)
    return Number.isFinite(durationMs) && durationMs > 0 ? Math.min(position, Math.floor(durationMs)) : position
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private seekPiP(positionMs: number): void {
    this.initialPositionMs = this.normalizePosition(positionMs, this.getCurrentDurationMs())
    this.syntheticPositionMs = this.initialPositionMs
    this.lastState.positionMs = this.syntheticPositionMs
    this.lastClockMs = Date.now()
    this.nowPlayingStore.updatePlayback(this.syntheticPositionMs, this.desiredPlaying, PIP_OWNER_ID)
    if (this.playerEngine !== null) {
      this.playerEngine.seek(this.syntheticPositionMs)
    }
  }

  private release(resetPlaybackStore: boolean = true, releaseSession: boolean = true): void {
    this.queueSwitchToken++
    const session = this.getSession()
    if (releaseSession && this.ownsSession && session !== null) {
      this.refreshEngineState()
      const controller = this.sessionManager.getReportController(session.id)
      if (controller !== null) void controller.stop(this.getCurrentPositionMs(), session.durationMs, this.lastState.speed)
      this.sessionManager.release(session.id)
    }
    if (this.pipController !== null) {
      try {
        this.pipController.off('stateChange')
        this.pipController.off('controlEvent')
      } catch (_err) {
      }
      this.pipController = null
    }
    if (this.playerEngine !== null) {
      this.playerEngine.onStateChange((_state: PlayerState) => {})
      this.playerEngine.release()
      this.playerEngine = null
    }
    this.xComponent = null
    this.playbackOptions = null
    this.uiContext = null
    this.syntheticPositionMs = 0
    this.lastClockMs = 0
    this.clockPlaying = false
    this.isActive = false
    this.isCreating = false
    this.isRestoring = false
    this.ownsSession = false
    if (resetPlaybackStore) {
      this.nowPlayingStore.reset(PIP_OWNER_ID)
    } else {
      this.nowPlayingStore.clearActions(PIP_OWNER_ID)
    }
  }
}
