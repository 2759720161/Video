import { PiPWindow, router, typeNode } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { IPlayerEngine, PlaybackOptions, PlayerState } from '../core/player/IPlayerEngine'
import { PlayerEngineFactory } from '../core/player/PlayerEngineFactory'
import { AVPlayerEngine } from '../core/player/AVPlayerEngine'
import { PlaybackRoad } from '../models/PlaybackRoad'
import { Logger } from '../utils/Logger'
import { PlaybackSessionActions, PlaybackSessionStore } from './PlaybackSessionStore'

const logger = new Logger('TypeNodePiPSession')

export class TypeNodePiPRoute {
  url: string = ''
  params: Record<string, Object> = {}
}

class PiPEpisodeTarget {
  roadIndex: number = -1
  episodeIndex: number = -1
  name: string = ''
  url: string = ''
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
  private playbackStore: PlaybackSessionStore = PlaybackSessionStore.getInstance()

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
    if (this.isActive || this.isCreating) {
      return true
    }
    if (!PiPWindow.isPiPEnabled()) {
      return false
    }

    this.isCreating = true
    this.isRestoring = false
    this.route = route
    this.uiContext = uiContext
    this.playbackOptions = this.clonePlaybackOptions(options)
    this.lastState = new PlayerState()
    this.initialPositionMs = options.startPositionMs > 0 ? options.startPositionMs : 0
    this.lastState.positionMs = this.initialPositionMs
    this.syntheticPositionMs = this.initialPositionMs
    this.lastClockMs = Date.now()
    this.clockPlaying = initialPlaying
    this.desiredPlaying = initialPlaying
    this.surfaceId = ''
    this.registerPlaybackStoreActions()
    this.syncPlaybackStoreMedia()
    this.playbackStore.updatePlayback(this.initialPositionMs, initialPlaying, 'typenode-pip')

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
      logger.info('TypeNode PiP started')
      return true
    } catch (err) {
      const businessError = err as BusinessError
      logger.warn('TypeNode PiP start failed: %{public}d - %{public}s', businessError.code, businessError.message)
      this.release(true)
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
    if (this.playbackOptions.isLocalFile) {
      logger.info('TypeNode PiP uses AVPlayer for local file')
      this.playerEngine = new AVPlayerEngine()
    } else {
      this.playerEngine = await PlayerEngineFactory.create()
    }
    this.playerEngine.setSurfaceId(this.surfaceId)
    this.playerEngine.onStateChange((state: PlayerState) => {
      this.syncPlaybackClock()
      this.lastState = state
      this.playbackStore.updatePlayerState(state, 'typenode-pip')
      if (state.positionMs > 0) {
        this.syntheticPositionMs = Math.max(this.syntheticPositionMs, state.positionMs)
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
          this.playbackStore.updatePlayback(this.getCurrentPositionMs(), true, 'typenode-pip')
          if (this.playerEngine !== null) {
            this.playerEngine.play()
          }
        } else {
          this.desiredPlaying = false
          this.syncPlaybackClock(false)
          this.playbackStore.updatePlayback(this.getCurrentPositionMs(), false, 'typenode-pip')
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
        PiPWindow.PiPControlType.VIDEO_PREVIOUS, this.findAdjacentEpisode(-1) !== null)
      this.pipController.setPiPControlEnabled(
        PiPWindow.PiPControlType.VIDEO_NEXT, this.findAdjacentEpisode(1) !== null)
    } catch (_err) {
      logger.warn('Update TypeNode PiP episode controls failed')
    }
  }

  private parseRoads(): PlaybackRoad[] {
    const raw = this.route.params['roadsJson']
    if (raw === undefined) {
      return []
    }
    try {
      return JSON.parse(raw as string) as PlaybackRoad[]
    } catch (_err) {
      return []
    }
  }

  private findAdjacentEpisode(direction: number): PiPEpisodeTarget | null {
    const roads = this.parseRoads()
    const selectedRoadIndex = this.route.params['selectedRoadIndex'] as number
    const currentEpisodeIndex = this.route.params['currentEpisodeIndex'] as number
    if (selectedRoadIndex < 0 || selectedRoadIndex >= roads.length || direction === 0) {
      return null
    }

    if (direction > 0) {
      const currentRoad = roads[selectedRoadIndex]
      if (currentEpisodeIndex >= 0 && currentEpisodeIndex < currentRoad.episodes.length - 1) {
        return this.buildEpisodeTarget(selectedRoadIndex, currentEpisodeIndex + 1, roads)
      }
      for (let i = selectedRoadIndex + 1; i < roads.length; i++) {
        if (roads[i].episodes.length > 0) {
          return this.buildEpisodeTarget(i, 0, roads)
        }
      }
      return null
    }

    if (currentEpisodeIndex > 0) {
      return this.buildEpisodeTarget(selectedRoadIndex, currentEpisodeIndex - 1, roads)
    }
    for (let i = selectedRoadIndex - 1; i >= 0; i--) {
      if (roads[i].episodes.length > 0) {
        return this.buildEpisodeTarget(i, roads[i].episodes.length - 1, roads)
      }
    }
    return null
  }

  private buildEpisodeTarget(roadIndex: number, episodeIndex: number,
    roads: PlaybackRoad[]): PiPEpisodeTarget | null {
    if (roadIndex < 0 || roadIndex >= roads.length || episodeIndex < 0 ||
      episodeIndex >= roads[roadIndex].episodes.length) {
      return null
    }
    const episode = roads[roadIndex].episodes[episodeIndex]
    const target = new PiPEpisodeTarget()
    target.roadIndex = roadIndex
    target.episodeIndex = episodeIndex
    target.name = episode.name
    target.url = episode.url
    return target
  }

  private switchEpisode(direction: number): void {
    if (this.isRestoring) {
      return
    }
    const target = this.findAdjacentEpisode(direction)
    if (target === null) {
      this.updateEpisodeControlStatus()
      return
    }

    this.route.params['videoUrl'] = ''
    this.route.params['episodeUrl'] = target.url
    this.route.params['episodeName'] = target.name
    this.route.params['selectedRoadIndex'] = target.roadIndex
    this.route.params['currentEpisodeIndex'] = target.episodeIndex
    this.route.params['historyPositionMs'] = 0
    this.route.params['resumeTypeNodePiP'] = true
    this.playbackStore.updateEpisodeAvailability(this.findAdjacentEpisode(1) !== null,
      this.findAdjacentEpisode(-1) !== null, 'typenode-pip')
    this.isRestoring = true
    logger.info('TypeNode PiP switch episode: road=%{public}d episode=%{public}d direction=%{public}d',
      target.roadIndex, target.episodeIndex, direction)

    const controller = this.pipController
    if (controller === null) {
      this.navigateToPlayerPage(0)
      return
    }
    controller.stopPiP().then(() => {
      this.navigateToPlayerPage(0)
    }).catch((_err: BusinessError) => {
      this.navigateToPlayerPage(0)
    })
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
    const restoredPositionMs = positionOverrideMs !== undefined ? positionOverrideMs :
      Math.max(this.getCurrentPositionMs(), this.initialPositionMs)
    params['historyPositionMs'] = restoredPositionMs
    logger.info('Restore player page from TypeNode PiP position=%{public}d initial=%{public}d last=%{public}d synthetic=%{public}d',
      restoredPositionMs, this.initialPositionMs, this.lastState.positionMs, this.syntheticPositionMs)
    if (this.uiContext !== null) {
      this.uiContext.getRouter().pushUrl({
        url: this.route.url,
        params: params
      }).then(() => {
        this.release(false)
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
      this.release(false)
    }).catch((err: Error) => {
      logger.warn('Restore player page failed: %{public}s', err.message)
      this.release(true)
    })
  }

  private registerPlaybackStoreActions(): void {
    const actions = new PlaybackSessionActions()
    actions.onPlay = () => {
      this.desiredPlaying = true
      this.syncPlaybackClock(true)
      this.updatePlayPauseControlStatus(true)
      this.playbackStore.updatePlayback(this.getCurrentPositionMs(), true, 'typenode-pip')
      if (this.playerEngine !== null) {
        this.playerEngine.play()
      }
    }
    actions.onPause = () => {
      this.desiredPlaying = false
      this.syncPlaybackClock(false)
      this.updatePlayPauseControlStatus(false)
      this.playbackStore.updatePlayback(this.getCurrentPositionMs(), false, 'typenode-pip')
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
    this.playbackStore.setActions(actions, 'typenode-pip')
  }

  private syncPlaybackStoreMedia(): void {
    if (this.playbackOptions === null) {
      return
    }
    const title = this.readRouteString('animeName', this.readRouteString('videoFileName', '正在播放'))
    const subtitle = this.readRouteString('episodeName', '')
    const cover = this.readRouteString('bangumiCover', this.readRouteString('animeCover',
      this.readRouteString('coverFallback', '')))
    this.playbackStore.updateMediaFromOptions(this.playbackOptions, title, subtitle, cover,
      this.findAdjacentEpisode(1) !== null, this.findAdjacentEpisode(-1) !== null, 'typenode-pip')
  }

  private readRouteString(key: string, fallback: string): string {
    const value = this.route.params[key]
    if (value === undefined || value === null) {
      return fallback
    }
    return String(value)
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
      if (state.positionMs > 0) {
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
    const enginePositionMs = this.lastState.positionMs > 0 ? this.lastState.positionMs : 0
    return Math.max(enginePositionMs, this.syntheticPositionMs, this.initialPositionMs)
  }

  private getCurrentDurationMs(): number {
    if (this.lastState.durationMs > 0) {
      return this.lastState.durationMs
    }
    return Number.MAX_SAFE_INTEGER
  }

  private seekPiP(positionMs: number): void {
    this.syntheticPositionMs = Math.max(0, positionMs)
    this.lastState.positionMs = this.syntheticPositionMs
    this.lastClockMs = Date.now()
    this.playbackStore.updatePlayback(this.syntheticPositionMs, this.desiredPlaying, 'typenode-pip')
    if (this.playerEngine !== null) {
      this.playerEngine.seek(this.syntheticPositionMs)
    }
  }

  private release(resetPlaybackStore: boolean = true): void {
    if (this.pipController !== null) {
      try {
        this.pipController.off('stateChange')
        this.pipController.off('controlEvent')
      } catch (_err) {
      }
      this.pipController = null
    }
    if (this.playerEngine !== null) {
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
    if (resetPlaybackStore) {
      this.playbackStore.reset('typenode-pip')
    } else {
      this.playbackStore.clearActions('typenode-pip')
    }
  }
}
