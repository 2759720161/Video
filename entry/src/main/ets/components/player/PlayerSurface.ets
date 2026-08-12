import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode } from '../../core/player/IPlayerEngine'
import { PlayerEngineFactory } from '../../core/player/PlayerEngineFactory'
import { Logger } from '../../utils/Logger'

const logger = new Logger('PlayerSurface')
const PLAYER_LIVE_URL_KEY: string = 'playerLivePlaybackUrl'
const PLAYER_LIVE_POSITION_KEY: string = 'playerLivePlaybackPositionMs'
const RETAINED_PLAYER_SESSION_TIMEOUT_MS: number = 6000
let playerSurfaceInitSeq: number = 0

interface RetainedPlayerSession {
  targetUrl: string
  engineType: string
  engine: IPlayerEngine
  expiryTimer: number
}

let retainedPlayerSession: RetainedPlayerSession | null = null

export function releaseRetainedPlayerSession(): void {
  if (retainedPlayerSession === null) {
    return
  }
  if (retainedPlayerSession.expiryTimer >= 0) {
    clearTimeout(retainedPlayerSession.expiryTimer)
  }
  try {
    retainedPlayerSession.engine.release()
  } catch (_err) {
  }
  retainedPlayerSession = null
}

function retainPlayerSession(targetUrl: string, engineType: string, engine: IPlayerEngine): void {
  releaseRetainedPlayerSession()
  const session: RetainedPlayerSession = {
    targetUrl: targetUrl,
    engineType: engineType,
    engine: engine,
    expiryTimer: -1
  }
  retainedPlayerSession = session
  session.expiryTimer = setTimeout(() => {
    if (retainedPlayerSession === session) {
      logger.warn('CrashDiag PlayerSurface retained engine expired: urlHash=%{public}s',
        shortPlayerSurfaceHash(targetUrl))
      releaseRetainedPlayerSession()
    }
  }, RETAINED_PLAYER_SESSION_TIMEOUT_MS)
}

function takeRetainedPlayerSession(targetUrl: string): RetainedPlayerSession | null {
  if (retainedPlayerSession === null) {
    return null
  }
  if (retainedPlayerSession.targetUrl !== targetUrl) {
    releaseRetainedPlayerSession()
    return null
  }
  const session = retainedPlayerSession
  if (session.expiryTimer >= 0) {
    clearTimeout(session.expiryTimer)
  }
  retainedPlayerSession = null
  return session
}

function shortPlayerSurfaceHash(value: string): string {
  let hash = 0
  for (let i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
  }
  return String(value.length) + ':' + String(hash)
}

class PlayerXComponentController extends XComponentController {
  private surfaceChangedCallback: (surfaceId: string, rect: SurfaceRect) => void

  constructor(callback: (surfaceId: string, rect: SurfaceRect) => void) {
    super()
    this.surfaceChangedCallback = callback
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    this.surfaceChangedCallback(surfaceId, rect)
  }
}

@Component
export struct PlayerSurface {
  @Prop @Watch('onVideoUrlChange') videoUrl: string = '';
  @Prop @Watch('onPlaybackOptionsChange') playbackOptions: PlaybackOptions = new PlaybackOptions();
  @Prop liveStartPositionMs: number = 0;
  @Prop fillParent: boolean = false;
  @Prop @Watch('onAspectModeChanged') aspectMode: VideoAspectMode = VideoAspectMode.contain;
  @Prop keepAliveOnDisappear: boolean = false;
  @State surfaceId: string = '';
  @State @Watch('onLayoutInputsChanged') videoWidth: number = 0;
  @State @Watch('onLayoutInputsChanged') videoHeight: number = 0;
  // Width and height must be committed as one layout sample. Watching them separately makes
  // the first assignment combine the new width with the old height (843x843 / 373x373),
  // which briefly enlarges the native video layer during rotation.
  @State parentWidth: number = 0;
  @State parentHeight: number = 0;
  @State xComponentWidth: number = 0;
  @State xComponentHeight: number = 0;
  @State xComponentOffsetX: number = 0;
  @State xComponentOffsetY: number = 0;
  private playerEngine: IPlayerEngine | null = null;
  private hasEngine: boolean = false;
  private isDestroyed: boolean = false;
  private pendingPrepareTimer: number = -1;
  private activeInitSeq: number = 0;
  private preparedUrl: string = '';
  private preparingUrl: string = '';
  private lastRequestedUrl: string = '';
  private playbackFailed: boolean = false;
  private xComponentController: XComponentController = new PlayerXComponentController(
    (surfaceId: string, rect: SurfaceRect) => {
      this.handleNativeSurfaceChanged(surfaceId, rect)
    });
  private engineType: string = 'mpv';
  private mpvFallbackUsed: boolean = false;
  private lastStableParentWidth: number = 0;
  private lastStableParentHeight: number = 0;
  onPlayerReady?: () => void;
  onStateChange?: (state: PlayerState) => void;
  onEngineReady?: (engine: IPlayerEngine) => void;
  onSurfaceReady?: (controller: XComponentController) => void;

  aboutToDisappear(): void {
    const pageActive = AppStorage.get<boolean>('playerPageActive') ?? false
    const targetUrl = this.getTargetUrl()
    if (!this.playbackFailed && (this.keepAliveOnDisappear || pageActive) &&
      this.hasEngine && this.playerEngine !== null &&
      targetUrl.length > 0) {
      logger.warn('CrashDiag PlayerSurface retain engine on rebuild: seq=%{public}d engine=%{public}s urlHash=%{public}s',
        this.activeInitSeq, this.engineType, this.shortHash(targetUrl))
      retainPlayerSession(targetUrl, this.engineType, this.playerEngine)
      this.playerEngine = null
      this.hasEngine = false
      this.preparedUrl = ''
      this.preparingUrl = ''
      this.isDestroyed = true
      return
    }
    if (this.playbackFailed) {
      logger.warn('CrashDiag PlayerSurface release failed engine on disappear: seq=%{public}d urlHash=%{public}s',
        this.activeInitSeq, this.shortHash(targetUrl))
    }
    this.isDestroyed = true;
    if (this.keepAliveOnDisappear && !this.playbackFailed) {
      logger.info('PlayerSurface keep engine alive on disappear')
      return
    }
    this.releaseEngine();
  }

  build() {
    Stack() {
      XComponent({
        id: 'videoXComponent',
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .onLoad(async () => {
          this.isDestroyed = false
          this.surfaceId = this.xComponentController.getXComponentSurfaceId();
          logger.info('Surface created: %{public}s', this.surfaceId);
          if (this.onSurfaceReady) {
            this.onSurfaceReady(this.xComponentController);
          }
          if (this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.setSurfaceId(this.surfaceId)
            return
          }
          const retainedSession = takeRetainedPlayerSession(this.getTargetUrl())
          if (retainedSession !== null) {
            this.engineType = retainedSession.engineType
            this.playerEngine = retainedSession.engine
            this.hasEngine = true
            this.preparedUrl = retainedSession.targetUrl
            this.lastRequestedUrl = retainedSession.targetUrl
            this.bindEngineCallbacks(this.playerEngine)
            this.playerEngine.setSurfaceId(this.surfaceId)
            this.playerEngine.setAspectMode(this.aspectMode)
            logger.warn('CrashDiag PlayerSurface reused engine after rebuild: seq=%{public}d engine=%{public}s urlHash=%{public}s',
              this.activeInitSeq, this.engineType, this.shortHash(retainedSession.targetUrl))
            if (this.onEngineReady) {
              this.onEngineReady(this.playerEngine)
            }
            if (this.onStateChange) {
              this.onStateChange(this.playerEngine.getState())
            }
            if (this.onPlayerReady) {
              this.onPlayerReady()
            }
            return
          }
          await this.loadEngineType();
          this.initPlayer();
        })
        .width(this.xComponentWidth > 0 ? this.xComponentWidth : '100%')
        .height(this.xComponentHeight > 0 ? this.xComponentHeight : '100%')
        .position({ x: this.xComponentOffsetX, y: this.xComponentOffsetY })
        .backgroundColor(Color.Black)
        // SURFACE XComponent 默认使用 RESIZE_FILL，会在暂停旋转时拉伸旧缓冲帧。
        // 显式映射当前画面模式，使系统旋转动画阶段也保持正确的视觉比例。
        .renderFit(this.getSurfaceRenderFit())
        .opacity(this.videoWidth > 0 && this.videoHeight > 0 ? 1 : 0)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w = Number(newArea.width)
      const h = Number(newArea.height)
      if (w > 0 && h > 0) {
        // 防御窗口旋转时可能出现的真实正方形占位尺寸。宽高状态本身则在下方
        // 完整提交后统一计算，避免代码自行拼出 843x843 / 373x373 中间值。
        if (this.isRotationPlaceholderArea(w, h)) {
          logger.info('Ignore transient square surface layout during rotation: %{public}dx%{public}d',
            Math.round(w), Math.round(h))
          return
        }
        this.lastStableParentWidth = w
        this.lastStableParentHeight = h
        if (w !== this.parentWidth || h !== this.parentHeight) {
          this.parentWidth = w
          this.parentHeight = h
          this.calculateBoxFitLayout()
        }
      }
    })
  }

  private onAspectModeChanged(): void {
    this.calculateBoxFitLayout()
    if (this.hasEngine && this.playerEngine !== null) {
      logger.info('PlayerSurface forward aspect mode: mode=%{public}s', this.getAspectModeName(this.aspectMode))
      this.playerEngine.setAspectMode(this.aspectMode)
    }
  }

  private handleNativeSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    if (!this.hasEngine || this.playerEngine === null) {
      return
    }
    const state = this.playerEngine.getState()
    if (state.playing || state.videoWidth <= 0 || state.videoHeight <= 0) {
      return
    }
    logger.info('Paused XComponent surface changed: id=%{public}s rect=%{public}dx%{public}d; request VO redraw',
      surfaceId, Math.round(rect.surfaceWidth), Math.round(rect.surfaceHeight))
    this.playerEngine.setAspectMode(this.aspectMode)
  }

  private isRotationPlaceholderArea(width: number, height: number): boolean {
    if (this.lastStableParentWidth <= 0 || this.lastStableParentHeight <= 0) {
      return false
    }
    const isIncomingSquare = Math.abs(width - height) <= 1
    const wasNonSquare = Math.abs(this.lastStableParentWidth - this.lastStableParentHeight) > 1
    return isIncomingSquare && wasNonSquare
  }

  private onLayoutInputsChanged(): void {
    this.calculateBoxFitLayout()
  }

  private calculateBoxFitLayout(): void {
    if (this.parentWidth <= 0 || this.parentHeight <= 0) {
      return
    }

    // Keep the native Surface identical to its parent. Surface layers are
    // composed outside ArkUI's normal canvas, and resizing/positioning the
    // XComponent itself can leave its native buffer at the old rectangle
    // after rotation (typically visible in a screen corner). mpv owns aspect
    // fitting inside this stable full-size canvas via keepaspect/panscan.
    const parentW = this.parentWidth
    const parentH = this.parentHeight
    const targetW = parentW
    const targetH = parentH
    const targetX = 0
    const targetY = 0
    const changed = targetW !== this.xComponentWidth || targetH !== this.xComponentHeight ||
      targetX !== this.xComponentOffsetX || targetY !== this.xComponentOffsetY

    this.xComponentWidth = targetW
    this.xComponentHeight = targetH
    this.xComponentOffsetX = targetX
    this.xComponentOffsetY = targetY

    if (changed) {
      logger.warn('CrashDiag PlayerSurface aspect layout: mode=%{public}s, params=boxFit=%{public}s,parent=%{public}dx%{public}d,video=%{public}dx%{public}d,surface=%{public}dx%{public}d,offset=%{public}d,%{public}d',
        this.getAspectModeName(this.aspectMode), this.getBoxFitName(this.aspectMode),
        Math.round(parentW), Math.round(parentH), Math.round(this.videoWidth), Math.round(this.videoHeight),
        Math.round(targetW), Math.round(targetH), Math.round(targetX), Math.round(targetY))
    }
  }

  private getSurfaceRenderFit(): RenderFit {
    switch (this.aspectMode) {
      case VideoAspectMode.cover:
        return RenderFit.RESIZE_COVER
      case VideoAspectMode.fill:
        return RenderFit.RESIZE_FILL
      case VideoAspectMode.contain:
      default:
        return RenderFit.RESIZE_CONTAIN
    }
  }

  private getAspectModeName(mode: VideoAspectMode): string {
    switch (mode) {
      case VideoAspectMode.contain:
        return 'contain(自动适应)'
      case VideoAspectMode.cover:
        return 'cover(裁切填充)'
      case VideoAspectMode.fill:
        return 'fill(拉伸填充)'
      default:
        return 'unknown'
    }
  }

  private getBoxFitName(mode: VideoAspectMode): string {
    switch (mode) {
      case VideoAspectMode.contain:
        return 'contain'
      case VideoAspectMode.cover:
        return 'cover'
      case VideoAspectMode.fill:
        return 'fill'
      default:
        return 'contain'
    }
  }

  private async loadEngineType(): Promise<void> {
    this.engineType = PlayerEngineFactory.getAvailableEngines().indexOf('mpv') >= 0 ? 'mpv' : 'avplayer'
  }

  private cancelPendingPrepare(): void {
    if (this.pendingPrepareTimer >= 0) {
      logger.warn('CrashDiag PlayerSurface cancel pending prepare: seq=%{public}d', this.activeInitSeq)
      clearTimeout(this.pendingPrepareTimer);
      this.pendingPrepareTimer = -1;
    }
  }

  private releaseEngine(): void {
    const startMs = Date.now()
    this.cancelPendingPrepare();
    if (this.hasEngine && this.playerEngine !== null) {
      logger.warn('CrashDiag PlayerSurface releaseEngine begin: seq=%{public}d hasEngine=%{public}s urlHash=%{public}s',
        this.activeInitSeq, String(this.hasEngine), this.shortHash(this.videoUrl))
      this.playerEngine.release();
      this.playerEngine = null;
      this.hasEngine = false;
      this.preparedUrl = '';
      this.preparingUrl = '';
      logger.warn('CrashDiag PlayerSurface releaseEngine end: seq=%{public}d elapsed=%{public}dms',
        this.activeInitSeq, Date.now() - startMs)
    }
  }

  private onVideoUrlChange(): void {
    const targetUrl = this.getTargetUrl()
    if (targetUrl.length > 0) {
      if (!this.arePlaybackOptionsReady()) {
        logger.info('Video URL changed but playback options are not ready');
        return;
      }
      if (this.isSamePlaybackTarget(targetUrl)) {
        logger.info('CrashDiag PlayerSurface videoUrl change ignored: same target urlHash=%{public}s',
          this.shortHash(targetUrl))
        return
      }
      logger.info('Video URL changed, re-preparing player');
      this.releaseEngine();
      this.initPlayer();
    }
  }

  private onPlaybackOptionsChange(): void {
    const targetUrl = this.getTargetUrl()
    if (targetUrl.length === 0 || !this.arePlaybackOptionsReady()) {
      return
    }
    if (this.isSamePlaybackTarget(targetUrl)) {
      logger.info('CrashDiag PlayerSurface playbackOptions change ignored: same target urlHash=%{public}s',
        this.shortHash(targetUrl))
      return
    }
    if (this.hasEngine && this.playerEngine !== null) {
      if (this.engineType === 'mpv' && !this.playbackFailed) {
        this.replaceCurrentMpvTarget(targetUrl)
      } else {
        logger.info('Playback options changed, re-preparing player')
        this.releaseEngine()
        this.initPlayer()
      }
    } else {
      logger.info('Playback options became ready, preparing player')
      this.initPlayer();
    }
  }

  private async initPlayer(): Promise<void> {
    const seq = ++playerSurfaceInitSeq;
    this.activeInitSeq = seq;
    this.playbackFailed = false;
    const initStartMs = Date.now();
    const targetUrl = this.getTargetUrl()
    if (targetUrl.length === 0) {
      logger.info('CrashDiag PlayerSurface init skip: seq=%{public}d reason=empty-url', seq)
      return;
    }
    if (!this.arePlaybackOptionsReady()) {
      logger.info('CrashDiag PlayerSurface init skip: seq=%{public}d reason=options-not-ready urlHash=%{public}s',
        seq, this.shortHash(this.videoUrl))
      return;
    }
    if (this.isSamePlaybackTarget(targetUrl)) {
      logger.info('CrashDiag PlayerSurface init skip: seq=%{public}d reason=same-target urlHash=%{public}s',
        seq, this.shortHash(targetUrl))
      return
    }
    this.lastRequestedUrl = targetUrl
    this.preparingUrl = targetUrl

    logger.info('PlayerSurface init: seq=%{public}d engine=%{public}s surface=%{public}s urlHash=%{public}s',
      seq, this.engineType,
      this.surfaceId, this.shortHash(this.videoUrl))
    const selectedEngine = PlayerEngineFactory.createByType(this.engineType)
    selectedEngine.setSurfaceId(this.surfaceId)
    this.playerEngine = selectedEngine

    this.bindEngineCallbacks(this.playerEngine!);

    this.playerEngine!.setAspectMode(this.aspectMode);

    const options = this.createTargetPlaybackOptions(targetUrl)

    this.hasEngine = true;
    const engine = this.playerEngine!
    const engineReadyCb = this.onEngineReady
    const playerReadyCb = this.onPlayerReady
    logger.info('CrashDiag PlayerSurface init ready: seq=%{public}d elapsed=%{public}dms pendingPrepare=scheduled',
      seq, Date.now() - initStartMs)
    this.pendingPrepareTimer = setTimeout(() => {
      this.pendingPrepareTimer = -1;
      if (this.isDestroyed) {
        logger.warn('CrashDiag PlayerSurface prepare skipped: seq=%{public}d reason=destroyed', seq)
        return;
      }
      if (this.activeInitSeq !== seq || this.lastRequestedUrl !== options.url || engine !== this.playerEngine) {
        logger.warn('CrashDiag PlayerSurface prepare skipped: seq=%{public}d reason=stale currentSeq=%{public}d',
          seq, this.activeInitSeq)
        return
      }
      const prepareStartMs = Date.now()
      logger.warn('CrashDiag PlayerSurface prepare begin: seq=%{public}d urlHash=%{public}s',
        seq, this.shortHash(options.url))
      if (options.startPositionMs > 0) {
        logger.warn('CrashDiag PlayerSurface prepare resume: seq=%{public}d startPosition=%{public}d',
          seq, options.startPositionMs)
      }
      engine.prepare(options);
      logger.warn('CrashDiag PlayerSurface prepare returned: seq=%{public}d elapsed=%{public}dms',
        seq, Date.now() - prepareStartMs)
      this.preparedUrl = options.url
      this.preparingUrl = ''
      if (engineReadyCb) {
        engineReadyCb(engine);
      }
      if (playerReadyCb) {
        playerReadyCb();
      }
    }, 0);
  }

  private replaceCurrentMpvTarget(targetUrl: string): void {
    if (this.playerEngine === null) {
      return
    }
    this.cancelPendingPrepare()
    const seq = ++playerSurfaceInitSeq
    this.activeInitSeq = seq
    this.lastRequestedUrl = targetUrl
    this.preparingUrl = targetUrl
    this.preparedUrl = ''
    const options = this.createTargetPlaybackOptions(targetUrl)
    logger.warn('CrashDiag PlayerSurface replace media on existing mpv: seq=%{public}d urlHash=%{public}s ' +
      'surface=%{public}s', seq, this.shortHash(targetUrl), this.surfaceId)
    this.playerEngine.prepare(options)
    this.preparedUrl = targetUrl
    this.preparingUrl = ''
  }

  private createTargetPlaybackOptions(targetUrl: string): PlaybackOptions {
    const options = new PlaybackOptions()
    options.url = targetUrl
    options.startPositionMs = this.resolveStartPositionMs(targetUrl)
    options.referer = this.playbackOptions.referer
    options.userAgent = this.playbackOptions.userAgent
    options.proxy = this.playbackOptions.proxy
    options.isLocalFile = this.playbackOptions.isLocalFile
    options.localFileSize = this.playbackOptions.localFileSize
    const headerKeys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      const key = headerKeys[i]
      options.headers[key] = this.playbackOptions.headers[key]
    }
    return options
  }

  private arePlaybackOptionsReady(): boolean {
    return this.playbackOptions.url.length > 0;
  }

  private getTargetUrl(): string {
    return this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUrl
  }

  private resolveStartPositionMs(targetUrl: string): number {
    // `liveStartPositionMs` is a reactive child prop and can briefly retain the
    // outgoing file's value when playbackOptions has already switched URLs.
    // It has no URL identity of its own, so using it here can transfer one
    // episode's progress to another. The AppStorage checkpoint below is URL
    // bound and remains the safe source for fullscreen/component rebuilds.
    const cachedUrl = AppStorage.get<string>(PLAYER_LIVE_URL_KEY) ?? ''
    if (cachedUrl === targetUrl) {
      const cachedPosition = AppStorage.get<number>(PLAYER_LIVE_POSITION_KEY) ?? 0
      if (cachedPosition > 0) {
        return cachedPosition
      }
    }
    return this.playbackOptions.startPositionMs
  }

  private bindEngineCallbacks(engine: IPlayerEngine): void {
    engine.onStateChange((state: PlayerState) => {
      if (this.isDestroyed) {
        return
      }
      if (state.stateName === 'error' && state.error.length > 0) {
        this.playbackFailed = true
        this.fallbackToAVPlayerIfNeeded()
      }
      if (state.videoWidth > 0 && state.videoHeight > 0 &&
        (state.videoWidth !== this.videoWidth || state.videoHeight !== this.videoHeight)) {
        this.videoWidth = state.videoWidth
        this.videoHeight = state.videoHeight
      }
      if (this.onStateChange) {
        this.onStateChange(state)
      }
    })
  }

  private fallbackToAVPlayerIfNeeded(): void {
    if (this.engineType !== 'mpv' || this.mpvFallbackUsed || this.isDestroyed) {
      return
    }
    this.mpvFallbackUsed = true
    logger.warn('MPV playback failed; retrying the same media with AVPlayer')
    this.engineType = 'avplayer'
    this.playbackFailed = false
    this.releaseEngine()
    this.initPlayer()
  }

  private isSamePlaybackTarget(targetUrl: string): boolean {
    if (targetUrl.length === 0) {
      return false
    }
    return targetUrl === this.preparedUrl || targetUrl === this.preparingUrl
  }

  private shortHash(value: string): string {
    let hash = 0
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
    }
    return String(value.length) + ':' + String(hash)
  }
}
