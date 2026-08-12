import { PlayerSurface, releaseRetainedPlayerSession } from '../../components/player/PlayerSurface'
import { GestureLayer } from '../../components/player/GestureLayer'
import { DanmakuCanvas } from '../../components/player/DanmakuCanvas'
import { IPlayerEngine, PlaybackOptions, PlayerState, PlayerTrack, PlayerTrackType, VideoAspectMode, VideoAspectModeHelper, VideoMediaInfo } from '../../core/player/IPlayerEngine'
import { ExternalSubtitleCue, ExternalSubtitleParser } from '../../core/player/ExternalSubtitleParser'
import { DanmakuManager } from '../../core/danmaku/DanmakuManager'
import { BusinessError } from '@kit.BasicServicesKit'
import { DanmakuFileParser, LocalDanmakuParseResult } from '../../core/danmaku/DanmakuFileParser'
import { LocalFilePicker, LocalFileResult } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { DanmakuSettingsPanelContent } from '../../components/player/DanmakuSettingsPanel'
import { DanmakuSettingsSidePanel } from '../../components/player/DanmakuSettingsSidePanel'
import { AspectModePanel } from '../../components/player/AspectModePanel'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { PlaybackQueueCodec, PlaybackQueueItem } from '../../models/PlaybackQueueItem'
import { DanmakuItem } from '../../models/DanmakuItem'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { PiPCallbacks, PiPManager } from '../../services/PiPManager'
import { TypeNodePiPRoute, TypeNodePiPSession } from '../../services/TypeNodePiPSession'
import { PlaybackSessionActions, PlaybackSessionStore } from '../../services/PlaybackSessionStore'
import { router, window, PiPWindow, promptAction } from '@kit.ArkUI'
import { KeyCode } from '@ohos.multimodalInput.keyCode'
import { audio } from '@kit.AudioKit'
import { common } from '@kit.AbilityKit'
import {
  createConfiguredImmersiveMaterial,
  createThickImmersiveMaterial,
} from '../../utils/ImmersiveMaterial'
import {
  PLAYER_AUTO_PIP_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_PIP
} from '../../utils/PlayerAutoPiP'
import {
  PLAYER_AUTO_NEXT_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_NEXT
} from '../../utils/PlayerAutoNext'
import {
  PLAYER_DEFAULT_SPEED,
  PLAYER_SEEK_SECONDS_DEFAULT,
  PREFS_KEY_PLAYER_DEFAULT_SPEED,
  PREFS_KEY_PLAYER_SEEK_SECONDS,
  normalizePlayerSpeed,
  normalizeSeekSeconds
} from '../../utils/PlayerPlaybackPreferences'
import {
  PREFS_KEY_SUBTITLE_BOTTOM_OFFSET,
  PREFS_KEY_SUBTITLE_ENABLED,
  PREFS_KEY_SUBTITLE_FONT_BOLD,
  PREFS_KEY_SUBTITLE_FONT_COLOR,
  PREFS_KEY_SUBTITLE_FONT_SIZE,
  PREFS_KEY_SUBTITLE_OUTLINE_ENABLED,
  PREFS_KEY_SUBTITLE_TIME_OFFSET_MS,
  SUBTITLE_BOTTOM_OFFSET_DEFAULT,
  SUBTITLE_ENABLED_DEFAULT,
  SUBTITLE_FONT_BOLD_DEFAULT,
  SUBTITLE_FONT_COLOR_DEFAULT,
  SUBTITLE_FONT_SIZE_DEFAULT,
  SUBTITLE_OUTLINE_ENABLED_DEFAULT,
  SUBTITLE_TIME_OFFSET_MS_DEFAULT
} from '../../utils/SubtitlePreferences'

const logger = new Logger('LocalPlayerPage')

const HISTORY_SAVE_INTERVAL_MS: number = 5000
const EXTERNAL_SUBTITLE_TICK_MS: number = 100
const SUBTITLE_MENU_COMMIT_DELAY_MS: number = 20
const PLAYER_LIVE_URL_KEY: string = 'playerLivePlaybackUrl'
const PLAYER_LIVE_POSITION_KEY: string = 'playerLivePlaybackPositionMs'
const PLAYER_REBUILD_RESUME_GUARD_MS: number = 3000
const COMPLETED_RESUME_RESTART_WINDOW_MS: number = 3000
const COMPLETED_RESUME_RESTART_RATIO: number = 0.995
const PREFS_KEY_PLAYER_PAGE_BRIGHTNESS: string = 'playerPageBrightness'
const PLAYER_PAGE_BRIGHTNESS_SAVE_DELAY_MS: number = 280

@Entry
@Component
struct LocalPlayerPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') appInForeground: boolean = true
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @State videoUri: string = ''
  @State videoFileName: string = ''
  @State isPlaying: boolean = false
  @State positionMs: number = 0
  @State liveStartPositionMs: number = 0
  @State durationMs: number = 0
  @State speed: number = 1.0
  @State speedLabel: string = '1x'
  @State isControlVisible: boolean = true
  @State isDraggingProgress: boolean = false
  @State isFullScreen: boolean = false
  @State isPiPActive: boolean = false
  @State private videoWidth: number = 0
  @State private videoHeight: number = 0
  @State private videoCodec: string = ''
  @State private videoFrameRate: number = 0
  @State private videoBitrate: number = 0
  @State private videoDecoder: string = ''
  @State private videoDynamicRange: string = ''
  @StorageLink(PREFS_KEY_PLAYER_AUTO_PIP) playerAutoPiP: boolean = PLAYER_AUTO_PIP_DEFAULT
  @StorageLink(PREFS_KEY_PLAYER_AUTO_NEXT) playerAutoNext: boolean = PLAYER_AUTO_NEXT_DEFAULT
  private readonly playerRememberPosition: boolean = true
  private readonly playerKeepScreenOn: boolean = true
  @StorageLink(PREFS_KEY_PLAYER_DEFAULT_SPEED) playerDefaultSpeed: number = PLAYER_DEFAULT_SPEED
  @StorageLink(PREFS_KEY_PLAYER_SEEK_SECONDS) playerSeekSeconds: number = PLAYER_SEEK_SECONDS_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_ENABLED) subtitleEnabled: boolean = SUBTITLE_ENABLED_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_FONT_SIZE) subtitleFontSize: number = SUBTITLE_FONT_SIZE_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_FONT_BOLD) subtitleFontBold: boolean = SUBTITLE_FONT_BOLD_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_FONT_COLOR) subtitleFontColor: string = SUBTITLE_FONT_COLOR_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_BOTTOM_OFFSET) subtitleBottomOffset: number = SUBTITLE_BOTTOM_OFFSET_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED) subtitleOutlineEnabled: boolean = SUBTITLE_OUTLINE_ENABLED_DEFAULT
  @StorageLink(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS) subtitleTimeOffsetMs: number = SUBTITLE_TIME_OFFSET_MS_DEFAULT
  @State playbackOptions: PlaybackOptions = new PlaybackOptions()
  @State screenBrightness: number = 0.5
  @State volume: number = 1.0
  private playerEngine: IPlayerEngine | null = null
  private xComponentController: XComponentController | null = null
  private pendingQueueTargetUri: string = ''
  private pendingQueueStartPositionMs: number = 0
  private queueSwitchSawPreparing: boolean = false
  @State hasEngine: boolean = false
  private danmakuManager: DanmakuManager | null = null
  @State isDanmakuEnabled: boolean = true
  @State showSpeedMenu: boolean = false
  @State showMediaInfoSheet: boolean = false
  @State showAudioTrackSheet: boolean = false
  @State showSubtitleTrackSheet: boolean = false
  @State subtitleMenuSection: string = 'primary'
  @State secondarySubtitleIndex: number = -1
  @State secondarySubtitleScale: number = 70
  @State subtitlePairSpacing: number = 0
  @State availableTracks: PlayerTrack[] = []
  @State externalSubtitleText: string = ''
  @State externalSubtitleFileName: string = ''
  @State externalSubtitleUri: string = ''
  @State externalSubtitleSelected: boolean = false
  @State subtitleMenuSelectionKey: string = 'off'
  private externalSubtitleCues: ExternalSubtitleCue[] = []
  @State playbackQueue: PlaybackQueueItem[] = []
  @State currentQueueIndex: number = -1
  @State showPlaybackQueue: boolean = false
  @State showHud: boolean = false
  @State hudText: string = ''
  @State playbackErrorText: string = ''
  @State danmakuFileName: string = ''
  @State currentAspectMode: VideoAspectMode = VideoAspectMode.contain
  @State showAspectModePanel: boolean = false
  @State showDanmakuSettingsPanel: boolean = false
  @State showDanmakuSettingsSheet: boolean = false
  @State showDanmakuManageSheet: boolean = false
  @State danmakuSettingsOpenVersion: number = 0
  @State showDanmakuLoadDialog: boolean = false
  @State showDanmakuOffsetPanel: boolean = false
  @State danmakuOffsetMs: number = 0
  @State danmakuLoadedFormat: string = ''
  @State danmakuLoadedCount: number = 0
  @State danmakuUri: string = ''
  @State pendingDanmakuItems: DanmakuItem[] = []
  @State pendingDanmakuFileName: string = ''
  @State pendingDanmakuFormat: string = ''
  @State pendingDanmakuUri: string = ''
  private controlHideTimer: number = -1
  private hudTimer: number = -1
  private volumeApplyTimer: number = -1
  private pageBrightnessSaveTimer: number = -1
  private pendingPageBrightness: number = -1
  private playerLayoutSyncTimer: number = -1
  private fullscreenTransitionTimer: number = -1
  private lastVolumeApplyMs: number = 0
  private pendingVolumeValue: number = -1
  private externalSubtitleTimer: number = -1
  private externalSubtitleClockPositionMs: number = 0
  private externalSubtitleClockUpdatedAtMs: number = 0
  private externalSubtitleClockPlaying: boolean = false
  private externalSubtitleRestoreAttemptedForUrl: string = ''
  private externalSubtitleRestoreInProgressForUrl: string = ''
  private externalSubtitleRestoreToken: number = 0
  private keepScreenOnRequestToken: number = 0
  private keepScreenOnEnabled: boolean = false
  private keepScreenOnRequested: boolean = false
  private wasPlayingBeforeDrag: boolean = false
  private lastHistorySaveMs: number = 0
  private historySeekMs: number = -1
  private historyDurationMs: number = 0
  private lastKnownPositionMs: number = 0
  private videoFileSize: number = 0
  private localVideoHistoryStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private readonly FULLSCREEN_ROTATION_SETTLE_MS: number = 180
  private isPageAlive: boolean = false
  private pipManager: PiPManager = PiPManager.getInstance()
  private playbackSessionStore: PlaybackSessionStore = PlaybackSessionStore.getInstance()
  private keepPlaybackForPiP: boolean = false
  private isRestoringFromPiP: boolean = false
  private isLeavingWithPiP: boolean = false
  private lastPlaybackSessionSyncMs: number = 0
  private lastPlaybackSessionStateName: string = ''
  private lastPlaybackSessionPlaying: boolean = false
  private lastPlaybackSessionPositionMs: number = -1
  private lastPlaybackSessionDurationMs: number = -1
  private temporarySpeedRestoreValue: number = PLAYER_DEFAULT_SPEED
  private audioManager: audio.AudioManager | null = null
  private mediaVolumeMinLevel: number = -1
  private mediaVolumeMaxLevel: number = -1
  private tracksLoadedForUrl: string = ''
  private videoInfoLoadedForUrl: string = ''
  private completionHandledForUrl: string = ''
  @State isAnimatingFullscreen: boolean = false
  @State suppressControlAnimation: boolean = false
  @State hideBottomControlsForFullscreenTransition: boolean = false

  aboutToAppear(): void {
    this.isPageAlive = true
    this.syncKeepScreenOnWithPlayback()
    AppStorage.setOrCreate('playerPageActive', true)
    this.pipManager.setCallbacks(this.buildPiPCallbacks())
    this.registerPlaybackSessionActions()
    const rawParams = router.getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      const videoUri = params['videoUri']
      const videoFileName = params['videoFileName']
      const videoFileSize = params['videoFileSize']
      const historyPositionMs = params['historyPositionMs']
      const historyDurationMs = params['historyDurationMs']
      const playlistJson = params['playlistJson']
      const queueIndex = params['queueIndex']

      if (typeof videoUri === 'string') this.videoUri = videoUri
      if (typeof videoFileName === 'string') this.videoFileName = videoFileName
      if (typeof videoFileSize === 'number') this.videoFileSize = videoFileSize
      if (typeof historyPositionMs === 'number') {
        this.historySeekMs = historyPositionMs
      }
      if (typeof historyDurationMs === 'number') {
        this.historyDurationMs = historyDurationMs
      }
      if (typeof playlistJson === 'string') {
        this.playbackQueue = PlaybackQueueCodec.decode(playlistJson)
      }
      if (typeof queueIndex === 'number' && queueIndex >= 0 && queueIndex < this.playbackQueue.length) {
        this.currentQueueIndex = queueIndex
      }
    }

    if (this.historyDurationMs <= 0 && this.currentQueueIndex >= 0 &&
      this.currentQueueIndex < this.playbackQueue.length) {
      this.historyDurationMs = this.playbackQueue[this.currentQueueIndex].durationMs
    }
    if (this.historySeekMs > 0) {
      const normalizedHistoryPosition = this.normalizeResumePosition(this.historySeekMs, this.historyDurationMs)
      if (normalizedHistoryPosition !== this.historySeekMs) {
        logger.info('Completed local history restarts from beginning: position=%{public}d duration=%{public}d',
          this.historySeekMs, this.historyDurationMs)
        this.clearLivePlaybackPosition()
      }
      this.historySeekMs = normalizedHistoryPosition
      this.lastKnownPositionMs = normalizedHistoryPosition
    }

    if (this.videoUri.length > 0) {
      this.ensurePlaybackQueueForCurrentVideo()
      const options = new PlaybackOptions()
      options.url = this.videoUri
      options.isLocalFile = true
      options.localFileSize = this.videoFileSize
      if (this.historySeekMs > 0) {
        options.startPositionMs = this.historySeekMs
        this.historySeekMs = -1
        this.showHudText('继续播放 ' + this.formatTime(options.startPositionMs))
      }
      this.playbackOptions = options
      this.syncPlaybackSessionMedia()
      this.enterFullscreenOnOpen()
    }

    this.startAutoHideTimer()
    this.loadSystemMediaVolume()
    this.loadAspectModePreference()
    this.restoreSavedPageBrightness()
    this.loadPlaybackPreferences()
    this.loadPlayerAutoPiPPreference()
    setTimeout(() => {
      if (this.isPageAlive) {
        try {
          this.getUIContext().getFocusController().requestFocus('localPlayerKeyboardTarget')
        } catch (_err) {
          // The target can temporarily have an unfocusable ancestor during page transitions.
          logger.warn('Local player keyboard target is not focusable yet')
        }
      }
    }, 0)
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('playerPageActive', false)
    // 页面亮度仅在播放页生效；离开页面（包括进入画中画）立即交还给系统亮度。
    this.flushPageBrightnessPreference()
    this.restoreSystemBrightness()
    this.setKeepScreenOn(false)
    this.clearPlayerAspectSyncTimer()
    this.clearFullscreenTransitionTimer()
    if (this.shouldKeepPlaybackForPiP()) {
      this.pauseAutoHideTimer()
      this.clearHudTimer()
      this.clearVolumeApplyTimer()
      this.stopExternalSubtitleClock()
      if (this.videoUri.length > 0) {
        this.saveLocalHistory(false)
      }
      logger.info('LocalPlayerPage aboutToDisappear skipped release for PiP')
      return
    }
    releaseRetainedPlayerSession()
    this.playbackSessionStore.reset('local-player')
    this.isPageAlive = false
    this.pauseAutoHideTimer()
    this.clearHudTimer()
    this.clearVolumeApplyTimer()
    this.stopExternalSubtitleClock()
    if (this.videoUri.length > 0) {
      this.saveLocalHistory(true)
    }
    this.stopPlaybackBeforeLeaving()
    if (this.danmakuManager !== null) {
      this.danmakuManager.release()
      this.danmakuManager = null
    }
    if (this.isFullScreen) {
      this.setFullScreenMode(false)
    }
    this.pipManager.destroyPiP()
  }

  onRdbReadyChanged(): void {
    if (this.appRdbReady && this.videoUri.length > 0 &&
      this.externalSubtitleRestoreAttemptedForUrl !== this.videoUri) {
      this.restoreExternalSubtitleFromHistory()
    }
  }

  private shouldKeepPlaybackForPiP(): boolean {
    return this.keepPlaybackForPiP || this.isPiPActive || this.pipManager.isActive() || this.pipManager.isCreating()
  }

  private onAppForegroundChanged(): void {
    if (this.appInForeground) {
      this.syncKeepScreenOnWithPlayback()
      return
    }
    this.setKeepScreenOn(false)
    this.pauseForApplicationBackground()
  }

  private pauseForApplicationBackground(): void {
    if (!this.isPageAlive || this.shouldKeepPlaybackForPiP()) {
      return
    }
    if (this.videoUri.length > 0) {
      this.ensurePlaybackQueueForCurrentVideo()
      this.saveLocalHistory(true)
    }
    if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
      logger.info('LocalPlayerPage pause playback for app background')
      this.playerEngine.pause()
      this.isPlaying = false
      this.pauseAutoHideTimer()
    }
  }

  private showPiPBackBlockedToast(): void {
    try {
      promptAction.showToast({ message: '画中画启动失败' })
    } catch (_err) {
    }
  }

  private handleBackFromPlayer(): boolean {
    if (this.isAnimatingFullscreen) {
      return true
    }
    if (this.isFullScreen) {
      this.toggleFullScreen()
      return true
    }
    return false
  }

  private async leavePlayerWithPiP(): Promise<void> {
    if (this.handleBackFromPlayer()) {
      return
    }
    // 此路径用于自动退出；手动画中画入口不会经过此处。
    if (!this.shouldAutoLeaveWithTypeNodePiP()) {
      this.leavePlayerNormally()
      return
    }
    if (this.isLeavingWithPiP) {
      return
    }
    this.isLeavingWithPiP = true
    if (!TypeNodePiPSession.getInstance().isRunning() && this.hasEngine) {
      const started = await this.startTypeNodePiPForLeaving()
      if (!started) {
        this.showPiPBackBlockedToast()
        this.isLeavingWithPiP = false
        return
      }
    }
    if (!this.handleBackFromPlayer()) {
      router.back()
    }
  }

  onBackPress(): boolean {
    if (this.handleBackFromPlayer()) {
      return true
    }
    if (this.shouldAutoLeaveWithTypeNodePiP()) {
      this.leavePlayerWithPiP()
    } else {
      this.leavePlayerNormally()
    }
    return true
  }

  private leavePlayerNormally(): void {
    if (this.handleBackFromPlayer()) {
      return
    }
    router.back()
  }

  private shouldAutoLeaveWithTypeNodePiP(): boolean {
    return this.playerAutoPiP && this.canLeaveWithTypeNodePiP()
  }

  private canLeaveWithTypeNodePiP(): boolean {
    return this.videoUri.length > 0 && this.hasEngine
  }

  private async startTypeNodePiPForLeaving(): Promise<boolean> {
    const route = new TypeNodePiPRoute()
    route.url = 'pages/player/LocalPlayerPage'
    route.params = this.buildLocalPlayerRouteParams()

    const options = this.cloneCurrentPlaybackOptions()
    options.startPositionMs = this.positionMs
    const context = getContext(this) as common.UIAbilityContext
    const contentWidth = this.videoWidth > 0 ? this.videoWidth : 1920
    const contentHeight = this.videoHeight > 0 ? this.videoHeight : 1080
    return TypeNodePiPSession.getInstance().start(
      context,
      this.getUIContext(),
      options,
      route,
      contentWidth,
      contentHeight,
      contentWidth > contentHeight ? 2 : 1,
      this.isPlaying
    )
  }

  private buildLocalPlayerRouteParams(): Record<string, Object> {
    const params: Record<string, Object> = {}
    params['videoUri'] = this.videoUri
    params['videoFileName'] = this.videoFileName
    params['videoFileSize'] = this.videoFileSize
    params['historyPositionMs'] = this.positionMs
    return params
  }

  private cloneCurrentPlaybackOptions(): PlaybackOptions {
    const cloned = new PlaybackOptions()
    cloned.url = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUri
    cloned.startPositionMs = this.playbackOptions.startPositionMs
    cloned.referer = this.playbackOptions.referer
    cloned.userAgent = this.playbackOptions.userAgent
    cloned.proxy = this.playbackOptions.proxy
    cloned.streamMetadata = this.playbackOptions.streamMetadata
    cloned.isLocalFile = true
    cloned.localFileSize = this.playbackOptions.localFileSize
    const keys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      cloned.headers[key] = this.playbackOptions.headers[key]
    }
    return cloned
  }

  build() {
    Stack() {
      this.PlayerState()
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.handlePlayerAreaChange(Math.max(0, newArea.width as number),
        Math.max(0, newArea.height as number))
    })
  }

  @Builder
  PlayerState(): void {
    Stack() {
      Column() {
        this.VideoSection()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)

      if (this.showDanmakuManageSheet) {
        this.DanmakuManageOverlay()
      }

      if (this.showDanmakuSettingsSheet && !this.isFullScreen) {
        this.DanmakuSettingsOverlay()
      }

      if (this.showAudioTrackSheet) {
        this.AudioTrackMenuOverlay()
      }

      if (this.showSubtitleTrackSheet) {
        this.SubtitleMenuOverlay()
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background(Color.Black)
    .bindSheet($$this.showDanmakuLoadDialog, this.buildDanmakuLoadDialog, {
      height: 280,
      showClose: false,
      dragBar: false,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showDanmakuLoadDialog = false
        this.startAutoHideTimer()
      }
    })
    .bindSheet($$this.showDanmakuOffsetPanel, this.buildDanmakuOffsetPanel, {
      height: 240,
      showClose: false,
      dragBar: true,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showDanmakuOffsetPanel = false
        this.startAutoHideTimer()
      }
    })
    .bindSheet($$this.showMediaInfoSheet, this.MediaInfoSheet, {
      height: 390,
      showClose: false,
      dragBar: true,
      onAppear: () => this.pauseAutoHideTimer(),
      onDisappear: () => {
        this.showMediaInfoSheet = false
        this.startAutoHideTimer()
      }
    })
  }

  @Builder
  private VideoSection() {
    Stack({ alignContent: Alignment.Center }) {
      this.VideoLayerContent()
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(Color.Black)
    .clip(true)
    .id('localPlayerKeyboardTarget')
    .focusable(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handlePlayerKeyEvent(event)
    })
  }

  @Builder
  private VideoLayerContent() {
    if (this.videoUri.length > 0) {
      PlayerSurface({
        videoUrl: this.videoUri,
        playbackOptions: this.playbackOptions,
        liveStartPositionMs: this.liveStartPositionMs,
        fillParent: true,
        aspectMode: this.currentAspectMode,
        keepAliveOnDisappear: this.shouldKeepPlaybackForPiP(),
        onStateChange: (state: PlayerState) => {
          this.handlePlayerState(state)
        },
          onEngineReady: (engine: IPlayerEngine) => {
            if (!this.isPageAlive) {
              engine.stop()
              return
            }
            this.playerEngine = engine
            this.hasEngine = true
            engine.onExternalSubtitleChange((text: string) => {
              this.externalSubtitleText = text
            })
            this.applyDefaultPlaybackSpeed()
            if (this.appRdbReady && this.videoUri.length > 0 &&
              this.externalSubtitleRestoreAttemptedForUrl !== this.videoUri) {
              this.restoreExternalSubtitleFromHistory()
            }
          },
          onSurfaceReady: (controller: XComponentController) => {
            this.xComponentController = controller
          }
      })

    } else {
      Column() {
        Text('未选择视频文件')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }

    GestureLayer({
      durationMs: this.durationMs,
      positionMs: this.positionMs,
      volume: this.volume,
      screenBrightness: this.screenBrightness,
      isPlaying: this.isPlaying,
      isControlVisible: this.isControlVisible,
      gestureEnabled: !this.shouldDisablePlayerGestures(),
      onSeek: (positionMs: number) => {
        this.seekTo(positionMs)
        this.showHudText('跳转到 ' + this.formatTime(positionMs))
        this.showControlsWithAutoHide()
      },
      onVolumeChange: (volume: number) => {
        this.requestSystemMediaVolume(volume)
        if (this.hasEngine && this.playerEngine !== null) {
          this.playerEngine.setVolume(volume)
        }
      },
      onBrightnessChange: (brightness: number) => {
        this.requestWindowBrightness(brightness)
      },
      onTogglePlayPause: () => {
        this.togglePlayPause()
        this.showHudText(this.isPlaying ? '播放' : '暂停')
      },
      onToggleControls: () => {
        this.toggleControls()
      },
      onMouseSingleClick: () => {
        this.togglePlayPause()
        this.showHudText(this.isPlaying ? '播放' : '暂停')
      },
      onMouseDoubleClick: () => {
        this.toggleFullScreen()
      },
      onTemporarySpeedStart: () => {
        this.startTemporarySpeed()
      },
      onTemporarySpeedEnd: () => {
        this.endTemporarySpeed()
      }
    })
      .width('100%')
      .height('100%')
      .zIndex(4)

    this.PlayerControlOverlay()

    if (this.subtitleEnabled && this.externalSubtitleText.length > 0) {
      this.ExternalSubtitleOverlay()
    }

    if (this.showHud) {
      this.HudView()
    }

    if (this.playbackErrorText.length > 0 && !this.isFullScreen) {
      this.PlaybackErrorOverlay()
    }

    if (this.isFullScreen && this.showDanmakuSettingsPanel) {
      DanmakuSettingsSidePanel({
        showPanel: this.showDanmakuSettingsPanel,
        isDanmakuEnabled: this.isDanmakuEnabled,
        isFullScreen: this.isFullScreen,
        settingsVersion: this.danmakuSettingsOpenVersion,
        onPanelClose: () => {
          this.closeDanmakuSettings()
        },
        onSetDanmakuEnabled: (enabled: boolean) => {
          this.setDanmakuEnabled(enabled)
        },
        onPauseAutoHide: () => {
          this.pauseAutoHideTimer()
        },
        onResumeAutoHide: () => {
          this.startAutoHideTimer()
        }
      })
        .zIndex(10)
    }
  }

  @Builder
  private PlayerControlOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.VideoTopBar()
        Blank()
          .layoutWeight(1)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
        this.VideoBottomBar()
      }
      .width('100%')
      .height('100%')
      .zIndex(6)
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.showAspectModePanel) {
        this.AspectModePanelOverlay()
      }

      if (this.showSpeedMenu) {
        this.SpeedMenuOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(6)
    .hitTestBehavior(this.isControlVisible ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private VideoTopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (!this.isPlayerControlActionAllowed()) {
          return
        }
        if (this.isFullScreen) {
          this.toggleFullScreen()
        } else {
          if (this.shouldAutoLeaveWithTypeNodePiP()) {
            this.leavePlayerWithPiP()
          } else {
            this.leavePlayerNormally()
          }
        }
      })

      Text(this.videoFileName.length > 0 ? this.videoFileName : '本地播放')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })

      this.PiPToolButton()

      this.TopSymbolButton($r('sys.symbol.rectangle_4_group_1'), '视频比例', () => {
        this.showAspectModePanel = true
        this.pauseAutoHideTimer()
      })
    }
    .width('100%')
    .height(this.topSafeHeight + 68)
    .padding({ left: 10, right: 14, top: this.topSafeHeight + 8, bottom: 8 })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#AA000000', 0.0], ['#5C000000', 0.55], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : -12 })
    .opacity(this.isControlVisible ? 1 : 0)
    .hitTestBehavior(this.isControlVisible ? HitTestMode.Default : HitTestMode.None)
    .animation({ duration: this.getControlAnimationDuration(), curve: Curve.EaseInOut })
  }

  @Builder
  private VideoBottomBar() {
    Column() {
      if (this.isFullScreen) {
        this.LandscapeProgressRow()
        this.LandscapeControlRow()
      } else {
        this.PortraitControlRow()
      }
    }
    .width('100%')
    .padding({ top: this.isFullScreen ? 18 : 12 })
    .linearGradient({
      direction: GradientDirection.Top,
      colors: [['#B8000000', 0.0], ['#70000000', 0.58], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : 12 })
    .opacity(this.shouldShowBottomControlLayer() ? 1 : 0)
    .hitTestBehavior(this.shouldShowBottomControlLayer() ? HitTestMode.Default : HitTestMode.None)
    .animation({ duration: this.getControlAnimationDuration(), curve: Curve.EaseInOut })
  }

  @Builder
  private LandscapeProgressRow() {
    Column({ space: 2 }) {
      this.ProgressUtilityRow()
      Row() {
        Text(this.formatTime(this.positionMs))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_primary'))
        this.ProgressSlider()
        Text(this.formatTime(this.durationMs))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_primary'))
      }
      .width('100%')
      .height(28)
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 2 })
  }

  @Builder
  private ProgressSlider() {
    Slider({
      value: this.durationMs > 0 ? this.positionMs : 0,
      min: 0,
      max: this.durationMs > 0 ? this.durationMs : 1,
      step: 1000
    })
      .layoutWeight(1)
      .trackColor('#55FFFFFF')
      .selectedColor($r('app.color.accent_blue'))
      .blockColor($r('app.color.text_on_primary'))
      .hitTestBehavior(this.shouldShowBottomControlLayer() ? HitTestMode.Default : HitTestMode.None)
      .onChange((value: number, mode: SliderChangeMode) => {
        if (!this.shouldShowBottomControlLayer()) {
          return
        }
        if (mode === SliderChangeMode.Begin) {
          this.isDraggingProgress = true
          this.wasPlayingBeforeDrag = this.isPlaying
          if (this.wasPlayingBeforeDrag && this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.pause()
          }
          this.pauseAutoHideTimer()
        } else if (mode === SliderChangeMode.Moving) {
          this.positionMs = value
        } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
          this.isDraggingProgress = false
          this.seekTo(value)
          if (this.wasPlayingBeforeDrag && this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.play()
          }
          this.showControlsWithAutoHide()
        } else {
          this.positionMs = value
        }
      })
  }

  @Builder
  private PortraitControlRow() {
    Column() {
      this.ProgressUtilityRow()

      Row() {
        Text(this.formatTime(this.positionMs))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')
        this.ProgressSlider()
        Text(this.formatTime(this.durationMs))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')
      }
      .width('100%')
      .height(24)
      .padding({ left: 14, right: 14 })

      this.PrimaryPlaybackControls()
    }
    .width('100%')
    .padding({ bottom: (this.bottomSafeHeight > 0 ? this.bottomSafeHeight : 0) + 16 })
  }

  @Builder
  private VideoInfoRow(): void {
    if (this.hasVideoInfo()) {
      Row({ space: 12 }) {
        if (this.videoCodec.length > 0) {
          this.VideoInfoText(this.formatVideoCodec())
        }
        if (this.videoWidth > 0 && this.videoHeight > 0) {
          this.VideoInfoText(this.videoWidth + '×' + this.videoHeight)
        }
        if (this.videoFrameRate > 0) {
          this.VideoInfoText(this.formatVideoFrameRate())
        }
        if (this.videoBitrate > 0) {
          this.VideoInfoText(this.formatVideoBitrate())
        }
        if (this.videoDecoder.length > 0) {
          this.VideoInfoText(this.videoDecoder)
        }
        if (this.videoDynamicRange.length > 0) {
          this.VideoInfoText(this.videoDynamicRange)
        }
      }
      .height(20)
    }
  }

  /** 位于进度条上方：左侧媒体信息，右侧独立字幕入口。 */
  @Builder
  private ProgressUtilityRow(): void {
    Row() {
      this.VideoInfoRow()
      Blank()
        .layoutWeight(1)
      Row({ space: 2 }) {
        this.SubtitleToolButton()
        this.AudioTrackToolButton()
      }
    }
    .width('100%')
    .height(32)
    .padding({ left: 2, right: 2 })
  }

  @Builder
  private SubtitleToolButton(): void {
    Row() {
      SymbolGlyph($r('sys.symbol.AI_word_suggest'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(36)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(15)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      this.openTrackSheet(PlayerTrackType.subtitle)
    })
  }

  @Builder
  private AudioTrackToolButton(): void {
    Row() {
      SymbolGlyph($r('sys.symbol.identify_song'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(36)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(15)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      this.openTrackSheet(PlayerTrackType.audio)
    })
  }

  @Builder
  private VideoInfoText(value: string): void {
    Text(value)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor('#E6FFFFFF')
      .maxLines(1)
  }

  @Builder
  private LandscapeControlRow() {
    Column() {
      this.PrimaryPlaybackControls()
    }
    .height(this.bottomSafeHeight + 62)
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: this.bottomSafeHeight + 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PrimaryPlaybackControls(): void {
    Stack({ alignContent: Alignment.Center }) {
      // 主控组独立于右侧功能键，播放/暂停始终相对整条底栏居中。
      Row({ space: 6 }) {
        this.SeekControlButton(false)
        this.TopSymbolButton($r('sys.symbol.backward_end_fill'), '上一个视频', () => {
          this.playPreviousQueueItem()
        })

        if (this.isPlaying) {
          this.TopSymbolButton($r('sys.symbol.pause_fill'), '暂停', () => {
            this.togglePlayPause()
          })
        } else {
          this.TopSymbolButton($r('sys.symbol.play_fill'), '播放', () => {
            this.togglePlayPause()
          })
        }

        this.TopSymbolButton($r('sys.symbol.forward_end_fill'), '下一个视频', () => {
          this.playNextQueueItem(false)
        })
        this.SeekControlButton(true)
      }
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      // 竖屏将倍速置于左端，横屏仍与全屏按钮保持在右端；
      // 中间主控独立于这条功能栏，始终相对整条底栏居中。
      Row() {
        if (!this.isFullScreen) {
          this.SpeedToolButton()
        }
        Blank()
          .layoutWeight(1)
        if (this.isFullScreen) {
          this.SpeedToolButton()
        }
        this.TopSymbolButton(
          this.isFullScreen ? $r('sys.symbol.rectangle_portrait_rotate') : $r('sys.symbol.rectangle_rotate'),
          this.isFullScreen ? '退出全屏' : '全屏', () => {
          this.toggleFullScreen()
        })
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height(50)
    .padding({ left: 10, right: 10, bottom: 8 })
  }

  @Builder
  private SpeedToolButton() {
    Row() {
      this.CurrentSpeedSymbol()
    }
    .width(44)
    .height(40)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      if (this.showSpeedMenu) {
        this.closeSpeedMenu()
      } else {
        this.openSpeedMenu()
      }
    })
  }

  @Builder
  private CurrentSpeedSymbol(): void {
    if (this.speed === 0.5) {
      SymbolGlyph($r('sys.symbol.speed_50percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 0.75) {
      SymbolGlyph($r('sys.symbol.speed_75percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 1.25) {
      SymbolGlyph($r('sys.symbol.speed_125percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 1.5) {
      SymbolGlyph($r('sys.symbol.speed_150percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 2.0) {
      SymbolGlyph($r('sys.symbol.speed_200percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 3.0) {
      Text('3×')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
    } else {
      SymbolGlyph($r('sys.symbol.speed_100percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
  }

  @Builder
  private TopSymbolButton(symbol: Resource, accessibilityLabel: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      action()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private SeekControlButton(forward: boolean): void {
    if (normalizeSeekSeconds(this.playerSeekSeconds) === 10) {
      if (forward) {
        this.TopSymbolButton($r('sys.symbol.goforward_10'), '前进 10 秒', () => this.seekByConfiguredSeconds(true))
      } else {
        this.TopSymbolButton($r('sys.symbol.gobackward_10'), '后退 10 秒', () => this.seekByConfiguredSeconds(false))
      }
    } else if (normalizeSeekSeconds(this.playerSeekSeconds) === 30) {
      if (forward) {
        this.TopSymbolButton($r('sys.symbol.goforward_30'), '前进 30 秒', () => this.seekByConfiguredSeconds(true))
      } else {
        this.TopSymbolButton($r('sys.symbol.gobackward_30'), '后退 30 秒', () => this.seekByConfiguredSeconds(false))
      }
    } else {
      if (forward) {
        this.TopSymbolButton($r('sys.symbol.goforward_15'), '前进 15 秒', () => this.seekByConfiguredSeconds(true))
      } else {
        this.TopSymbolButton($r('sys.symbol.gobackward_15'), '后退 15 秒', () => this.seekByConfiguredSeconds(false))
      }
    }
  }

  @Builder
  private PiPToolButton() {
    if (PiPManager.isPiPSupported() && this.hasEngine) {
      Row() {
        Image($r('app.media.ic_pip'))
          .draggable(false)
          .width(22)
          .height(22)
      }
      .width(44)
      .height(40)
      .borderRadius(20)
      .backgroundColor('#00000000')
      .border({ width: 0, color: '#00000000' })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (!this.isPlayerControlActionAllowed()) {
          return
        }
        this.startPiPFromControl()
        this.showControlsWithAutoHide()
      })
    }

    if (this.showPlaybackQueue) {
      this.PlaybackQueueOverlay()
    }
  }

  @Builder
  private SymbolToolButton(symbol: Resource, accessibilityLabel: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(23)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(44)
    .height(40)
    .borderRadius(20)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private DanmakuToggleButton() {
    Row() {
      SymbolGlyph(this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off'))
        .fontSize(23)
        .renderingStrategy(this.isDanmakuEnabled ? SymbolRenderingStrategy.MULTIPLE_COLOR : SymbolRenderingStrategy.SINGLE)
        .fontColor(this.isDanmakuEnabled ?
          ['#F2FFFFFF', $r('app.color.accent_blue'), $r('app.color.accent_blue')] :
          ['#F2FFFFFF'])
    }
    .width(44)
    .height(40)
    .borderRadius(20)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleDanmaku()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private HudView() {
    Column() {
      Text(this.hudText)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .textShadow({ radius: 2, color: '#E6000000', offsetX: 1, offsetY: 1 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .zIndex(9)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private PlaybackErrorOverlay() {
    Column() {
      Text(this.playbackErrorText)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 12 })
      Row({ space: 10 }) {
        if (this.canAuthorizeCurrentVideo()) {
          Button('重新授权')
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(12)
            .onClick(() => {
              this.authorizeCurrentVideo()
            })
        }
        Button('重新选择')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .borderRadius(12)
          .onClick(() => {
            this.pickVideoFile()
          })
      }
      .width('76%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .zIndex(12)
  }

  @Builder
  private MediaInfoSheet(): void {
    Column() {
      Text('媒体信息')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 18, bottom: 18 })

      this.MediaInfoRow('文件', this.videoFileName.length > 0 ? this.videoFileName : '未知文件')
      this.MediaInfoRow('分辨率', this.videoWidth > 0 && this.videoHeight > 0 ? this.videoWidth + ' × ' + this.videoHeight : '正在读取')
      if (this.videoCodec.length > 0) {
        this.MediaInfoRow('视频编码', this.formatVideoCodec())
      }
      if (this.videoFrameRate > 0) {
        this.MediaInfoRow('帧率', this.formatVideoFrameRate())
      }
      if (this.videoBitrate > 0) {
        this.MediaInfoRow('视频码率', this.formatVideoBitrate())
      }
      if (this.videoDecoder.length > 0) {
        this.MediaInfoRow('解码方式', this.videoDecoder)
      }
      if (this.videoDynamicRange.length > 0) {
        this.MediaInfoRow('动态范围', this.videoDynamicRange)
      }
      this.MediaInfoRow('时长', this.durationMs > 0 ? this.formatTime(this.durationMs) : '正在读取')
      this.MediaInfoRow('文件大小', this.videoFileSize > 0 ? this.formatFileSize(this.videoFileSize) : '未知')
      this.MediaInfoRow('当前进度', this.durationMs > 0 ? this.formatTime(this.positionMs) + ' / ' + this.formatTime(this.durationMs) : this.formatTime(this.positionMs))
      this.MediaInfoRow('播放速度', this.speedLabel)

    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MediaInfoRow(label: string, value: string): void {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(82)
      Text(value).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider_color') })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private AudioTrackSheet(): void {
    this.TrackSheetContent('音轨', PlayerTrackType.audio)
  }

  /** 音轨菜单锚定在底部音轨按钮上方，避免遮挡整个播放画面。 */
  @Builder
  private AudioTrackMenuOverlay(): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => this.closeTrackSheet(PlayerTrackType.audio))

      Column() {
        if (this.getTracksByType(PlayerTrackType.audio).length === 0) {
          Text('当前视频未提供可切换的音轨')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 12 })
        } else {
          Scroll() {
            Column({ space: 5 }) {
              ForEach(this.getTracksByType(PlayerTrackType.audio), (track: PlayerTrack) => {
                this.AudioTrackMenuItem(track)
              }, (track: PlayerTrack) => 'audio_menu_' + track.index + '_' +
                (track.selected ? 'selected' : 'idle'))
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width(this.isFullScreen ? 250 : 238)
      .height(this.getAudioTrackMenuHeight())
    .padding({ top: 8, bottom: 8 })
    .margin({ right: 6, bottom: this.getAudioTrackMenuBottomOffset() })
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('app.color.speed_menu_surface'))
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .systemMaterial(createThickImmersiveMaterial())
    .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .zIndex(28)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private AudioTrackMenuItem(track: PlayerTrack): void {
    Row({ space: 10 }) {
      Text(this.buildAudioTrackSummary(track))
        .fontSize(14)
        .fontWeight(track.selected ? FontWeight.Bold : FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (track.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.brand')])
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.selectPlayerTrack(track))
  }

  private getAudioTrackMenuHeight(): number {
    const count = this.getTracksByType(PlayerTrackType.audio).length
    if (count === 0) {
      return 76
    }
    // 对齐视频比例菜单：上下各 8vp，每项 44vp；超过上限后交给 Scroll 滚动。
    const contentHeight = 16 + count * 44
    const maxHeight = this.isFullScreen ? 280 : 300
    return Math.min(contentHeight, maxHeight)
  }

  private getAudioTrackMenuBottomOffset(): number {
    // 音轨按钮位于进度条上方，菜单从该按钮正上方展开。
    if (this.isFullScreen) {
      return this.bottomSafeHeight + 126
    }
    return this.bottomSafeHeight + 142
  }

  @Builder
  private SubtitleTrackSheet(): void {
    this.TrackSheetContent('字幕', PlayerTrackType.subtitle)
  }

  /** Player subtitle controls: selection pane on the left, actions on the right. */
  @Builder
  private SubtitleMenuOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => this.closeTrackSheet(PlayerTrackType.subtitle))

      Row() {
        Column() {
          this.SubtitleMenuContent()
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ left: 18, right: 10, top: 18, bottom: 18 })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)

        Column() {
          this.SubtitleMenuNavigation()
        }
        .width(this.isFullScreen ? 218 : 148)
        .height('100%')
        .padding({ top: 18, right: 10, bottom: 18 })
      }
      .width(this.isFullScreen ? '62%' : '88%')
      .height(this.isFullScreen ? 326 : 358)
      .borderRadius(16)
      .clip(true)
      .backgroundColor($r('app.color.speed_menu_surface'))
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .systemMaterial(createThickImmersiveMaterial())
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .zIndex(28)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private SubtitleMenuNavigation(): void {
    Column({ space: 3 }) {
      this.SubtitleMenuPrimaryNavRow()
      this.SubtitleMenuNavRow($r('sys.symbol.doc_text'), '副字幕', 'secondary')
      Divider().color('#20FFFFFF').margin({ top: 6, bottom: 6 })
      this.SubtitleMenuActionRow($r('sys.symbol.doc_text'), '导入字幕', () => {
        this.pickAndAddExternalSubtitle()
      })
      Divider().color('#20FFFFFF').margin({ top: 6, bottom: 6 })
      this.SubtitleMenuNavRow($r('sys.symbol.gearshape'), '字幕样式', 'style')
      this.SubtitleMenuNavRow($r('sys.symbol.clock'), '字幕偏移', 'offset')
      this.SubtitleMenuActionRow($r('sys.symbol.xmark'), '关闭字幕', () => {
        this.closeAllSubtitlesAndSheet()
      })
    }
    .width('100%')
  }

  @Builder
  private SubtitleMenuPrimaryNavRow(): void {
    Row({ space: 9 }) {
      Text('Aa')
        .fontSize(23)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.subtitleMenuSection === 'primary' ? $r('app.color.accent_blue') : '#F5FFFFFF')
      Text('主字幕')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.subtitleMenuSection === 'primary' ? $r('app.color.accent_blue') : '#F5FFFFFF')
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.subtitleMenuSection === 'primary' ? $r('app.color.accent_blue') : '#A6FFFFFF'])
    }
    .width('100%')
    .height(38)
    .padding({ left: 12, right: 10 })
    .borderRadius(13)
    .backgroundColor(this.subtitleMenuSection === 'primary' ? $r('app.color.accent_blue_light') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.subtitleMenuSection = 'primary')
  }

  @Builder
  private SubtitleMenuNavRow(symbol: Resource, title: string, section: string): void {
    Row({ space: 9 }) {
      SymbolGlyph(symbol)
        .fontSize(21)
        .fontColor([this.subtitleMenuSection === section ? $r('app.color.accent_blue') : '#F5FFFFFF'])
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.subtitleMenuSection === section ? $r('app.color.accent_blue') : '#F5FFFFFF')
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.subtitleMenuSection === section ? $r('app.color.accent_blue') : '#A6FFFFFF'])
    }
    .width('100%')
    .height(38)
    .padding({ left: 12, right: 10 })
    .borderRadius(13)
    .backgroundColor(this.subtitleMenuSection === section ? $r('app.color.accent_blue_light') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.subtitleMenuSection = section)
  }

  @Builder
  private SubtitleMenuActionRow(symbol: Resource, title: string, action: () => void): void {
    Row({ space: 9 }) {
      SymbolGlyph(symbol)
        .fontSize(21)
        .fontColor(['#F5FFFFFF'])
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5FFFFFF')
        .layoutWeight(1)
    }
    .width('100%')
    .height(38)
    .padding({ left: 12, right: 10 })
    .borderRadius(13)
    .alignItems(VerticalAlign.Center)
    .onClick(() => action())
  }

  @Builder
  private SubtitleMenuContent(): void {
    if (this.subtitleMenuSection === 'primary') {
      this.PrimarySubtitlePane()
    } else if (this.subtitleMenuSection === 'secondary') {
      this.SecondarySubtitlePane()
    } else if (this.subtitleMenuSection === 'style') {
      this.SubtitleStylePane()
    } else {
      this.SubtitleOffsetPane()
    }
  }

  @Builder
  private PrimarySubtitlePane(): void {
    Column({ space: 8 }) {
      Text('主字幕')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#A6FFFFFF')
        .width('100%')

      this.PrimarySubtitleMenuChoice('关闭', '', 'off', () => {
        this.disableSelectedSubtitleTracks()
      })

      if (this.hasLoadedExternalSubtitle()) {
        this.PrimarySubtitleMenuChoice(this.externalSubtitleFileName, '外挂', 'external', () => {
          this.enableExternalSubtitle()
        })
      }

      if (!this.hasLoadedExternalSubtitle() && this.getSubtitleMenuTracks().length === 0) {
        Text('没有可用字幕')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#A6FFFFFF')
          .width('100%')
          .margin({ left: 12, top: 6 })
      }

      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.getSubtitleMenuTracks(), (track: PlayerTrack) => {
            this.PrimarySubtitleMenuChoice(this.buildTrackTitle(track), this.buildTrackDetail(track),
              'track_' + String(track.index), () => this.selectPrimarySubtitleTrack(track))
          }, (track: PlayerTrack) => 'primary_subtitle_' + track.index)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private SecondarySubtitlePane(): void {
    Column({ space: 8 }) {
      Text('副字幕')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#A6FFFFFF')
        .width('100%')
      this.SecondarySubtitleMenuChoice('关闭', '', -1, () => {
        this.disableSecondarySubtitle()
      })
      if (this.getSubtitleMenuTracks().length === 0) {
        Text('没有可用字幕')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#A6FFFFFF')
          .width('100%')
          .margin({ left: 12, top: 6 })
      }
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.getSubtitleMenuTracks(), (track: PlayerTrack) => {
            this.SecondarySubtitleMenuChoice(this.buildTrackTitle(track), this.buildTrackDetail(track), track.index,
              () => this.selectSecondarySubtitleTrack(track))
          }, (track: PlayerTrack) => 'secondary_subtitle_' + track.index)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private PrimarySubtitleMenuChoice(title: string, detail: string, selectionKey: string, action: () => void): void {
    Row({ space: 7 }) {
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.subtitleMenuSelectionKey === selectionKey ? $r('app.color.accent_blue') : '#F5FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (detail.length > 0) {
          Text(detail)
            .fontSize(11)
            .fontColor(this.subtitleMenuSelectionKey === selectionKey ? $r('app.color.accent_blue') : '#A6FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.subtitleMenuSelectionKey === selectionKey) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%')
    .height(detail.length > 0 ? 54 : 46)
    .padding({ left: 12, right: 12 })
    .borderRadius(13)
    .backgroundColor(this.subtitleMenuSelectionKey === selectionKey ? $r('app.color.accent_blue_light') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      // 将主字幕行的高亮在原始点击回调中立即写入，不能等待异步播放器调用。
      this.setSubtitleMenuSelection(selectionKey)
      // Returning from the pointer callback lets ArkUI submit the selected
      // frame before libmpv/libass performs a potentially expensive track
      // switch and font rebuild on the application thread.
      setTimeout(() => action(), SUBTITLE_MENU_COMMIT_DELAY_MS)
    })
  }

  @Builder
  private SecondarySubtitleMenuChoice(title: string, detail: string, trackIndex: number, action: () => void): void {
    Row({ space: 7 }) {
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.secondarySubtitleIndex === trackIndex ? $r('app.color.accent_blue') : '#F5FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (detail.length > 0) {
          Text(detail)
            .fontSize(11)
            .fontColor(this.secondarySubtitleIndex === trackIndex ? $r('app.color.accent_blue') : '#A6FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.secondarySubtitleIndex === trackIndex) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%')
    .height(detail.length > 0 ? 54 : 46)
    .padding({ left: 12, right: 12 })
    .borderRadius(13)
    .backgroundColor(this.secondarySubtitleIndex === trackIndex ? $r('app.color.accent_blue_light') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => action())
  }

  @Builder
  private SubtitleStyleMenuChoice(title: string, enabledValue: boolean, action: () => void): void {
    Row({ space: 7 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.subtitleOutlineEnabled === enabledValue ? $r('app.color.accent_blue') : '#F5FFFFFF')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.subtitleOutlineEnabled === enabledValue) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 12, right: 12 })
    .borderRadius(13)
    .backgroundColor(this.subtitleOutlineEnabled === enabledValue ? $r('app.color.accent_blue_light') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private SubtitleStylePane(): void {
    Column({ space: 12 }) {
      Text('字幕样式')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#A6FFFFFF')
        .width('100%')
      this.SubtitleStyleMenuChoice('文字阴影', true, () => this.setSubtitleOutlineFromMenu(true))
      this.SubtitleStyleMenuChoice('无阴影', false, () => this.setSubtitleOutlineFromMenu(false))
      this.SubtitleMenuSlider('主字幕大小 ' + Math.round(this.subtitleFontSize / SUBTITLE_FONT_SIZE_DEFAULT * 100) + '%',
        this.subtitleFontSize, 16, 24, 2, (value: number) => this.setSubtitleFontSizeFromMenu(value))
      this.SubtitleMenuSlider('副字幕大小 ' + this.secondarySubtitleScale + '%', this.secondarySubtitleScale, 50, 100, 5,
        (value: number) => this.secondarySubtitleScale = Math.round(value))
      this.SubtitleMenuSlider('主副字幕间距 ' + this.subtitlePairSpacing + ' vp', this.subtitlePairSpacing, 0, 32, 2,
        (value: number) => this.subtitlePairSpacing = Math.round(value))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SubtitleOffsetPane(): void {
    Column({ space: 16 }) {
      Row() {
        Text('字幕偏移 ' + this.subtitleTimeOffsetMs + ' ms')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F5FFFFFF')
          .layoutWeight(1)
        Text('恢复默认')
          .fontSize(13)
          .fontColor('#A6FFFFFF')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('#26FFFFFF')
          .onClick(() => this.setSubtitleTimeOffsetFromMenu(SUBTITLE_TIME_OFFSET_MS_DEFAULT))
      }
      .width('100%')
      this.SubtitleMenuSlider('', this.subtitleTimeOffsetMs, -5000, 5000, 100,
        (value: number) => this.setSubtitleTimeOffsetFromMenu(value))
      Text('底部边距 ' + this.subtitleBottomOffset + ' vp')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5FFFFFF')
        .width('100%')
      this.SubtitleMenuSlider('', this.subtitleBottomOffset, 0, 96, 4,
        (value: number) => this.setSubtitleBottomOffsetFromMenu(value))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SubtitleMenuSlider(label: string, value: number, min: number, max: number, step: number,
    action: (value: number) => void): void {
    Column({ space: 5 }) {
      if (label.length > 0) {
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#CFFFFFFF')
          .width('100%')
      }
      Slider({ value: value, min: min, max: max, step: step })
        .width('100%')
        .height(26)
        .selectedColor($r('app.color.accent_blue'))
        .trackColor('#2EFFFFFF')
        .blockColor('#FFF2F2F2')
        .onChange((nextValue: number) => action(nextValue))
    }
    .width('100%')
  }

  @Builder
  private TrackSheetOverlay(title: string, type: PlayerTrackType): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeTrackSheet(type)
        })

      Column() {
        this.TrackSheetContent(title, type)
      }
      .width('100%')
      .height(360)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 18, topRight: 18 })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: -6 })
    }
    .width('100%')
    .height('100%')
    .zIndex(28)
  }

  @Builder
  private TrackSheetContent(title: string, type: PlayerTrackType): void {
    Column() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 18, bottom: 10 })

      if (type === PlayerTrackType.subtitle) {
        this.TrackOption('关闭字幕', '不显示内嵌字幕', -1, !this.hasSelectedTrack(type), () => {
          this.disableSelectedSubtitleTracks()
        })
      }

      if (this.getTracksByType(type).length === 0) {
        Text(type === PlayerTrackType.audio ? '当前视频未提供可切换的音轨' : '当前视频未提供内嵌字幕轨')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 56 })
      } else {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.getTracksByType(type), (track: PlayerTrack) => {
              this.TrackOption(this.buildTrackTitle(track), this.buildTrackDetail(track), track.index, track.selected, () => {
                this.selectPlayerTrack(track)
              })
            }, (track: PlayerTrack) => 'track_' + track.type + '_' + track.index + '_' +
              (track.selected ? 'selected' : 'idle'))
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, bottom: 20 })
  }

  @Builder
  private TrackOption(title: string, detail: string, _index: number, selected: boolean, action: () => void): void {
    Row({ space: 12 }) {
      SymbolGlyph(selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(22)
        .fontColor([selected ? $r('app.color.accent_blue') : $r('sys.color.icon_secondary')])
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(detail)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(62)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor(selected ? $r('app.color.button_ghost_bg') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => action())
  }

  @Builder
  private PlaybackQueueOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#88000000')
        .onClick(() => {
          this.showPlaybackQueue = false
          this.startAutoHideTimer()
        })

      Column() {
        Row() {
          Text('当前播放')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.getPlaybackQueueLabel())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 12 })
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .width(36)
            .height(36)
            .onClick(() => {
              this.showPlaybackQueue = false
              this.startAutoHideTimer()
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        if (this.playbackQueue.length === 0) {
          Text('当前视频没有可用的播放列表')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 54, bottom: 54 })
        } else {
          Scroll() {
            Column({ space: 4 }) {
              ForEach(this.playbackQueue, (item: PlaybackQueueItem, index: number) => {
                this.PlaybackQueueItemRow(item, index)
              }, (item: PlaybackQueueItem, index: number) => 'queue_' + index + '_' + item.uri)
            }
            .width('100%')
          }
          .width('100%')
          .height(300)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: this.bottomSafeHeight + 18 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 18, topRight: 18 })
    }
    .width('100%')
    .height('100%')
    .zIndex(28)
  }

  @Builder
  private PlaybackQueueItemRow(item: PlaybackQueueItem, index: number): void {
    Row({ space: 12 }) {
      Text(String(index + 1))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isCurrentQueueItem(index) ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
        .width(24)
        .textAlign(TextAlign.Center)
      Column() {
        Text(item.name.length > 0 ? item.name : '本地视频')
          .fontSize(15)
          .fontWeight(this.isCurrentQueueItem(index) ? FontWeight.Bold : FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.positionMs > 0) {
          Text('继续播放 ' + this.formatTime(item.positionMs))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 3 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.isCurrentQueueItem(index)) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%')
    .height(58)
    .padding({ left: 10, right: 10 })
    .borderRadius(12)
    .backgroundColor(this.isCurrentQueueItem(index) ? $r('app.color.button_ghost_bg') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.playQueueItem(index, true)
    })
  }

  private isCurrentQueueItem(index: number): boolean {
    return index === this.currentQueueIndex
  }

  @Builder
  private ExternalSubtitleOverlay(): void {
    Column() {
      Text(this.externalSubtitleText)
        .fontSize(this.subtitleFontSize)
        .fontWeight(this.subtitleFontBold ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.subtitleFontColor)
        .textAlign(TextAlign.Center)
        .lineHeight(this.subtitleFontSize + 8)
        .textShadow(this.subtitleOutlineEnabled ? { radius: 2, color: '#E6000000', offsetX: 1, offsetY: 1 } : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
        .maxLines(3)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, bottom: (this.isFullScreen ? this.bottomSafeHeight + 18 : 24) + this.subtitleBottomOffset })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .zIndex(5)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private LocalDanmakuStatusRow(): void {
    Row({ space: 8 }) {
      SymbolGlyph(this.danmakuFileName.length > 0 ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off'))
        .fontSize(17)
        .fontColor([this.danmakuFileName.length > 0 ? $r('app.color.accent_blue') : $r('sys.color.icon_secondary')])
      Text(this.buildCurrentDanmakuText())
        .fontSize(12)
        .fontColor(this.danmakuFileName.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })
    .onClick(() => {
      this.handleDanmakuPrimaryAction()
    })
  }

  @Builder
  private AspectModePanelOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.showAspectModePanel = false
        })

      AspectModePanel({
        currentMode: this.currentAspectMode,
        onSelectMode: (mode: VideoAspectMode) => {
          this.applyAspectMode(mode)
          this.showAspectModePanel = false
          this.showControlsWithAutoHide()
        }
      })
        .margin({ top: this.isFullScreen ? this.topSafeHeight + 46 : 46, right: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(9)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private SpeedMenuOverlay() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .hitTestBehavior(HitTestMode.Default)
        .onClick(() => {
          this.closeSpeedMenu()
        })

      Column() {
        Scroll() {
          Column() {
            this.SpeedMenuItem(3.0)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(2.0)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.75)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.5)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.25)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.0)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(0.75)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(0.5)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(0.25)
          }
          .width('100%')
        }
        .width('100%')
        .height(364)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .hitTestBehavior(HitTestMode.Default)
      }
      .width(104)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.speed_menu_surface'))
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .systemMaterial(createThickImmersiveMaterial())
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
      .margin({ right: 12, bottom: this.isFullScreen ? this.bottomSafeHeight + 74 : this.bottomSafeHeight + 66 })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
  }

  @Builder
  private SpeedMenuItem(value: number) {
    Row() {
      Text(this.formatPlaybackSpeed(value))
        .fontSize(15)
        .fontWeight(Math.abs(this.speed - value) < 0.01 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      if (Math.abs(this.speed - value) < 0.01) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.brand')])
      }
    }
      .width('100%')
      .height(40)
      .padding({ left: 14, right: 14 })
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.setPlaybackSpeed(value)
        this.closeSpeedMenu()
      })
  }

  @Builder
  private SpeedMenuDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.category_menu_divider'))
      .margin({ left: 14, right: 14 })
  }

  private openSpeedMenu(): void {
    this.showSpeedMenu = true
    this.pauseAutoHideTimer()
  }

  private closeSpeedMenu(): void {
    this.showSpeedMenu = false
    this.showControlsWithAutoHide()
  }

  private shouldDisablePlayerGestures(): boolean {
    return this.showSpeedMenu || this.showAspectModePanel || this.showDanmakuSettingsPanel ||
      this.showDanmakuSettingsSheet || this.showDanmakuManageSheet || this.showDanmakuLoadDialog ||
      this.showDanmakuOffsetPanel
  }

  @Builder
  private DanmakuManageOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showDanmakuManageSheet = false
          this.startAutoHideTimer()
        })

      Column() {
        Row() {
          Text('弹幕')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .width(40)
            .height(40)
            .onClick(() => {
              this.showDanmakuManageSheet = false
              this.startAutoHideTimer()
            })
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)

        Text(this.buildCurrentDanmakuText())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 16 })

        Column({ space: 10 }) {
          this.DanmakuManageAction(this.danmakuFileName.length > 0 ? '更换弹幕' : '加载弹幕',
            '选择 XML / JSON / ASS 文件', $r('sys.symbol.doc_text'), true, () => {
            this.runAfterDanmakuManageClosed(() => {
              this.pickAndLoadLocalDanmaku()
            })
          })
          this.DanmakuManageAction('弹幕设置', '显示密度、透明度、字号等', $r('sys.symbol.barrage_setting'), false, () => {
            this.runAfterDanmakuManageClosed(() => {
              this.openDanmakuSettings()
            })
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: this.bottomSafeHeight + 18 })
      .borderRadius({ topLeft: 18, topRight: 18 })
      .backgroundColor($r('app.color.card_background'))
      .systemMaterial(createConfiguredImmersiveMaterial())
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: -6 })
    }
    .width('100%')
    .height('100%')
    .zIndex(30)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
  }

  @Builder
  private DanmakuManageAction(title: string, subtitle: string, symbol: Resource, primary: boolean, action: () => void) {
    Row({ space: 12 }) {
      Stack() {
        Circle()
          .width(34)
          .height(34)
          .fill(primary ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
          .opacity(primary ? 0.18 : 1)
        SymbolGlyph(symbol)
          .fontSize(19)
          .fontColor([primary ? $r('app.color.accent_blue') : $r('sys.color.icon_secondary')])
      }
      .width(36)
      .height(36)

      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private DanmakuSettingsOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeDanmakuSettings()
        })

      Column() {
        Row() {
          Blank()
            .layoutWeight(1)
          Rect()
            .width(36)
            .height(4)
            .borderRadius(2)
            .fill($r('app.color.divider_color'))
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height(18)
        .alignItems(VerticalAlign.Center)

        this.buildDanmakuSettingsSheet()
      }
      .width('100%')
      .height('70%')
      .borderRadius({ topLeft: 18, topRight: 18 })
      .clip(true)
      .backgroundColor($r('app.color.page_background'))
      .systemMaterial(createConfiguredImmersiveMaterial())
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: -6 })
    }
    .width('100%')
    .height('100%')
    .zIndex(40)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
  }

  @Builder
  buildDanmakuSettingsSheet() {
    DanmakuSettingsPanelContent({
      isDanmakuEnabled: this.isDanmakuEnabled,
      isFullScreen: this.isFullScreen,
      settingsVersion: this.danmakuSettingsOpenVersion,
      showSourceFilter: false,
      onSetDanmakuEnabled: (enabled: boolean) => {
        this.setDanmakuEnabled(enabled)
      },
      onPanelClose: () => {
        this.showDanmakuSettingsSheet = false
      },
      onPauseAutoHide: () => {
        this.pauseAutoHideTimer()
      },
      onResumeAutoHide: () => {
        this.startAutoHideTimer()
      }
    })
  }

  @Builder
  buildDanmakuLoadDialog() {
    Column() {
      Text('弹幕已存在')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 24, bottom: 4 })
      Text('当前已有 ' + this.danmakuLoadedCount + ' 条弹幕，如何处理新加载的 ' + this.pendingDanmakuItems.length + ' 条弹幕？')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 20 })
        .padding({ left: 24, right: 24 })

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(12)
          .onClick(() => {
            this.showDanmakuLoadDialog = false
            this.pendingDanmakuItems = []
            this.pendingDanmakuFileName = ''
            this.pendingDanmakuFormat = ''
            this.pendingDanmakuUri = ''
          })

        Button('追加')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            this.applyPendingDanmaku(true)
            this.showDanmakuLoadDialog = false
          })

        Button('替换')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.status_error'))
          .fontColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            this.applyPendingDanmaku(false)
            this.showDanmakuLoadDialog = false
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20 })
    }
    .width('100%')
  }

  @Builder
  buildDanmakuOffsetPanel() {
    Column() {
      Text('弹幕时间校准')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 20, bottom: 8 })

      Text('当前偏移: ' + this.formatOffset(this.danmakuOffsetMs))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 16 })

      Row({ space: 8 }) {
        Button('-5s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(-5000))
        Button('-1s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(-1000))
        Button('重置')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(10)
          .onClick(() => this.resetDanmakuOffset())
        Button('+1s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(1000))
        Button('+5s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(5000))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 20 })
    }
    .width('100%')
  }

  private handlePlayerState(state: PlayerState): void {
    if (!this.isPageAlive) {
      return
    }
    if (this.shouldIgnorePendingQueueSwitchState(state)) {
      return
    }
    if (this.shouldIgnoreTransientRebuildZeroState(state)) {
      logger.info('LocalPlayerPage ignore transient rebuild zero: state=%{public}s liveStart=%{public}d',
        state.stateName, this.liveStartPositionMs)
      return
    }
    this.isPlaying = state.playing
    this.syncKeepScreenOnWithPlayback()
    this.positionMs = state.positionMs
    this.syncExternalSubtitleClock(state.positionMs, state.playing)
    if (state.positionMs > 0) {
      this.lastKnownPositionMs = state.positionMs
    }
    if (state.playing && state.positionMs > 0) {
      this.liveStartPositionMs = state.positionMs
      this.cacheLivePlaybackPosition(state.positionMs)
    }
    this.durationMs = state.durationMs
    this.volume = state.volume
    this.speed = state.speed
    this.speedLabel = this.speed.toFixed(this.speed % 1 === 0 ? 0 : 2) + 'x'
    if (this.shouldSyncPlaybackSessionState(state)) {
      this.playbackSessionStore.updatePlayerState(state, 'local-player')
    }
    if (state.videoWidth > 0 && state.videoHeight > 0 &&
      (state.videoWidth !== this.videoWidth || state.videoHeight !== this.videoHeight)) {
      this.videoWidth = state.videoWidth
      this.videoHeight = state.videoHeight
    }
    if (this.pipManager.isActive()) {
      this.pipManager.updatePlaybackState(state.playing)
      if (state.videoWidth > 0 && state.videoHeight > 0) {
        this.pipManager.updateContentSize(state.videoWidth, state.videoHeight)
      }
    }

    if ((state.stateName === 'prepared' || state.stateName === 'playing') &&
      this.videoUri.length > 0 && this.tracksLoadedForUrl !== this.videoUri) {
      this.tracksLoadedForUrl = this.videoUri
      this.refreshPlayerTracks()
    }
    if ((state.stateName === 'prepared' || state.stateName === 'playing') &&
      this.videoUri.length > 0 && this.videoInfoLoadedForUrl !== this.videoUri) {
      this.refreshVideoInfo()
    }
    if (this.appRdbReady && (state.stateName === 'prepared' || state.stateName === 'playing') &&
      this.videoUri.length > 0 && this.externalSubtitleRestoreAttemptedForUrl !== this.videoUri) {
      this.restoreExternalSubtitleFromHistory()
    }

    if (this.danmakuManager !== null) {
      this.danmakuManager.onPlayerStateUpdate(state)
    }

    if (state.error.length > 0) {
      logger.warn('Local playback error: %{public}s', state.error)
      this.playbackErrorText = '本地文件访问失败，请重新授权或重新选择'
      this.showHudText('本地文件访问失败')
    } else if (this.playbackErrorText.length > 0 && state.playing) {
      this.playbackErrorText = ''
    }

    if (state.completed && this.completionHandledForUrl !== this.videoUri) {
      this.completionHandledForUrl = this.videoUri
      // An EOF position is not a valid live-resume checkpoint. Keeping it in
      // AppStorage makes a fullscreen/page rebuild override normalized history
      // and load the media at EOF again.
      this.clearLivePlaybackPosition()
      this.saveLocalHistory()
      if (this.playerAutoNext) {
        this.playNextQueueItem(true)
      }
    }

    if (this.videoUri.length > 0 && this.durationMs > 0 && this.lastKnownPositionMs > 0) {
      const now = Date.now()
      if (now - this.lastHistorySaveMs >= HISTORY_SAVE_INTERVAL_MS) {
        this.lastHistorySaveMs = now
        this.saveLocalHistory()
      }
    }
  }

  private updateExternalSubtitleText(positionMs: number): void {
    if (this.externalSubtitleCues.length === 0) {
      if (this.externalSubtitleText.length > 0) {
        this.externalSubtitleText = ''
      }
      return
    }
    const subtitlePositionMs = Math.max(0, positionMs - this.subtitleTimeOffsetMs)
    const nextText = ExternalSubtitleParser.textAt(this.externalSubtitleCues, subtitlePositionMs)
    if (nextText !== this.externalSubtitleText) {
      this.externalSubtitleText = nextText
    }
  }

  /**
   * MPV time-pos events can be coalesced on a busy UI thread. Keep a local
   * clock between those events so short subtitle cues cannot be skipped.
   */
  private syncExternalSubtitleClock(positionMs: number, playing: boolean): void {
    this.externalSubtitleClockPositionMs = Math.max(0, positionMs)
    this.externalSubtitleClockUpdatedAtMs = Date.now()
    this.externalSubtitleClockPlaying = playing
    this.updateExternalSubtitleText(this.externalSubtitleClockPositionMs)
    if (playing && this.externalSubtitleCues.length > 0 && this.isPageAlive) {
      this.startExternalSubtitleClock()
    } else if (!playing || this.externalSubtitleCues.length === 0) {
      this.stopExternalSubtitleClock()
    }
  }

  private startExternalSubtitleClock(): void {
    if (this.externalSubtitleTimer >= 0) {
      return
    }
    this.externalSubtitleTimer = setInterval(() => {
      if (!this.isPageAlive || !this.externalSubtitleClockPlaying || this.externalSubtitleCues.length === 0) {
        this.stopExternalSubtitleClock()
        return
      }
      const elapsedMs = Date.now() - this.externalSubtitleClockUpdatedAtMs
      const predictedPositionMs = this.externalSubtitleClockPositionMs + elapsedMs * this.speed
      this.updateExternalSubtitleText(predictedPositionMs)
    }, EXTERNAL_SUBTITLE_TICK_MS)
  }

  private stopExternalSubtitleClock(): void {
    if (this.externalSubtitleTimer >= 0) {
      clearInterval(this.externalSubtitleTimer)
      this.externalSubtitleTimer = -1
    }
  }

  private togglePlayPause(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      if (this.isPlaying) {
        this.playerEngine.pause()
      } else {
        this.playerEngine.play()
      }
    }

  }

  private async refreshPlayerTracks(): Promise<void> {
    if (!this.hasEngine || this.playerEngine === null) {
      return
    }
    try {
      this.availableTracks = await this.playerEngine.getTracks()
      // 外挂字幕在关闭后仍会保留在 MPV 轨道列表中，不能用异步返回的 selected
      // 覆盖用户刚刚在菜单中作出的选择；内嵌字幕则以播放器返回状态为准。
      if (!this.hasLoadedExternalSubtitle()) {
        let selectedKey = 'off'
        for (let i = 0; i < this.availableTracks.length; i++) {
          const track = this.availableTracks[i]
          if (track.type === PlayerTrackType.subtitle && track.selected) {
            selectedKey = 'track_' + String(track.index)
            break
          }
        }
        this.setSubtitleMenuSelection(selectedKey)
      }
      logger.info('本地播放器轨道读取完成: %{public}d', this.availableTracks.length)
    } catch (err) {
      this.availableTracks = []
      logger.warn('读取本地播放器轨道失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private openTrackSheet(type: PlayerTrackType): void {
    if (type === PlayerTrackType.audio) {
      this.showAudioTrackSheet = true
    } else {
      this.subtitleMenuSection = 'primary'
      this.showSubtitleTrackSheet = true
    }
    this.pauseAutoHideTimer()
    this.refreshPlayerTracks()
  }

  private closeTrackSheet(type: PlayerTrackType): void {
    if (type === PlayerTrackType.audio) {
      this.showAudioTrackSheet = false
    } else {
      this.showSubtitleTrackSheet = false
    }
    this.startAutoHideTimer()
  }

  private async refreshVideoInfo(): Promise<void> {
    if (!this.hasEngine || this.playerEngine === null) {
      return
    }
    const currentUri = this.videoUri
    try {
      const info: VideoMediaInfo = await this.playerEngine.getVideoInfo()
      if (currentUri !== this.videoUri) {
        return
      }
      this.videoCodec = info.codec
      this.videoFrameRate = info.frameRate
      this.videoBitrate = info.bitrate
      this.videoDecoder = info.decoder
      this.videoDynamicRange = info.dynamicRange
      if (info.codec.length > 0) {
        this.videoInfoLoadedForUrl = currentUri
      }
      logger.info('本地播放器视频信息读取完成: codec=%{public}s fps=%{public}s bitrate=%{public}s decoder=%{public}s range=%{public}s',
        info.codec, String(info.frameRate), String(info.bitrate), info.decoder, info.dynamicRange)
    } catch (err) {
      logger.warn('读取本地播放器视频信息失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private getTracksByType(type: PlayerTrackType): PlayerTrack[] {
    const tracks: PlayerTrack[] = []
    for (let i = 0; i < this.availableTracks.length; i++) {
      if (this.availableTracks[i].type === type) {
        tracks.push(this.availableTracks[i])
      }
    }
    return tracks
  }

  /** The external subtitle is already rendered as its own file row in the left pane. */
  private getSubtitleMenuTracks(): PlayerTrack[] {
    const tracks = this.getTracksByType(PlayerTrackType.subtitle)
    if (!this.hasLoadedExternalSubtitle()) {
      return tracks
    }
    const visibleTracks: PlayerTrack[] = []
    for (let i = 0; i < tracks.length; i++) {
      if (tracks[i].name !== this.externalSubtitleFileName) {
        visibleTracks.push(tracks[i])
      }
    }
    return visibleTracks
  }

  private setPrimarySubtitleSelectionImmediately(index: number): void {
    for (let i = 0; i < this.availableTracks.length; i++) {
      if (this.availableTracks[i].type === PlayerTrackType.subtitle) {
        this.availableTracks[i].selected = this.availableTracks[i].index === index
      }
    }
    this.availableTracks = this.availableTracks.slice()
  }

  private hasSelectedTrack(type: PlayerTrackType): boolean {
    const tracks = this.getTracksByType(type)
    for (let i = 0; i < tracks.length; i++) {
      if (tracks[i].selected) {
        return true
      }
    }
    return false
  }

  private hasLoadedExternalSubtitle(): boolean {
    return this.externalSubtitleFileName.length > 0 && this.externalSubtitleUri.length > 0
  }

  private hasActiveExternalSubtitle(): boolean {
    return this.hasLoadedExternalSubtitle() && this.externalSubtitleSelected
  }

  /** Updates the visual menu selection before waiting for the playback kernel. */
  private setSubtitleMenuSelection(selectionKey: string): void {
    if (this.subtitleMenuSelectionKey === selectionKey &&
      this.externalSubtitleSelected === (selectionKey === 'external')) {
      return
    }
    this.subtitleMenuSelectionKey = selectionKey
    this.externalSubtitleSelected = selectionKey === 'external'
    logger.info('字幕菜单选中态已立即更新: %{public}s', selectionKey)
  }

  private waitForSubtitleMenuCommit(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, SUBTITLE_MENU_COMMIT_DELAY_MS)
    })
  }

  private async selectPrimarySubtitleTrack(track: PlayerTrack): Promise<void> {
    if (this.playerEngine === null) {
      return
    }
    try {
      this.setSubtitleMenuSelection('track_' + String(track.index))
      this.setPrimarySubtitleSelectionImmediately(track.index)
      await this.playerEngine.selectTrack(track.index)
      if (this.hasLoadedExternalSubtitle()) {
        this.externalSubtitleCues = []
        this.externalSubtitleText = ''
        this.externalSubtitleFileName = ''
        this.externalSubtitleUri = ''
        this.externalSubtitleRestoreToken++
        this.stopExternalSubtitleClock()
        await this.persistExternalSubtitleBinding()
      }
      this.subtitleEnabled = true
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_ENABLED, true)
      PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_ENABLED, true).catch((_err: void) => {})
      await this.refreshPlayerTracks()
      this.showHudText('已切换主字幕')
    } catch (err) {
      this.refreshPlayerTracks()
      logger.warn('切换主字幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('切换字幕失败')
    }
  }

  private async selectSecondarySubtitleTrack(track: PlayerTrack): Promise<void> {
    if (this.playerEngine === null) {
      return
    }
    const previousIndex = this.secondarySubtitleIndex
    this.secondarySubtitleIndex = track.index
    try {
      await this.waitForSubtitleMenuCommit()
      await this.playerEngine.setSecondarySubtitle(track.index)
      this.showHudText('已切换副字幕')
    } catch (err) {
      this.secondarySubtitleIndex = previousIndex
      logger.warn('切换副字幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('当前播放内核不支持副字幕')
    }
  }

  private async disableSecondarySubtitle(): Promise<void> {
    if (this.playerEngine === null) {
      this.secondarySubtitleIndex = -1
      return
    }
    const previousIndex = this.secondarySubtitleIndex
    this.secondarySubtitleIndex = -1
    try {
      await this.waitForSubtitleMenuCommit()
      await this.playerEngine.setSecondarySubtitle(-1)
      this.showHudText('已关闭副字幕')
    } catch (_err) {
      this.secondarySubtitleIndex = previousIndex
      this.showHudText('关闭副字幕失败')
    }
  }

  private setSubtitleFontSizeFromMenu(value: number): void {
    const supportedSizes: number[] = [16, 18, 20, 22, 24]
    let closest = SUBTITLE_FONT_SIZE_DEFAULT
    let distance = Number.MAX_VALUE
    for (let i = 0; i < supportedSizes.length; i++) {
      const currentDistance = Math.abs(value - supportedSizes[i])
      if (currentDistance < distance) {
        closest = supportedSizes[i]
        distance = currentDistance
      }
    }
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_SIZE, closest)
    PreferencesStore.getInstance().setNumber(PREFS_KEY_SUBTITLE_FONT_SIZE, closest).catch((_err: void) => {})
  }

  private setSubtitleOutlineFromMenu(enabled: boolean): void {
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, enabled)
    PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, enabled).catch((_err: void) => {})
  }

  private setSubtitleTimeOffsetFromMenu(value: number): void {
    const normalized = Math.max(-5000, Math.min(5000, Math.round(value / 100) * 100))
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, normalized)
    PreferencesStore.getInstance().setNumber(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, normalized).catch((_err: void) => {})
    if (this.playerEngine !== null) {
      this.playerEngine.setSubtitleDelay(normalized).catch((_err: Error) => {
        logger.warn('同步 MPV 字幕偏移失败')
      })
    }
  }

  private setSubtitleBottomOffsetFromMenu(value: number): void {
    const normalized = Math.max(0, Math.min(96, Math.round(value / 4) * 4))
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_BOTTOM_OFFSET, normalized)
    PreferencesStore.getInstance().setNumber(PREFS_KEY_SUBTITLE_BOTTOM_OFFSET, normalized).catch((_err: void) => {})
  }

  private buildTrackTitle(track: PlayerTrack): string {
    if (track.name.length > 0) {
      return track.name
    }
    if (track.language.length > 0) {
      return track.language
    }
    return track.type === PlayerTrackType.audio ? '音轨 ' + String(track.index) : '字幕 ' + String(track.index)
  }

  private buildTrackDetail(track: PlayerTrack): string {
    const parts: string[] = []
    if (track.language.length > 0 && track.name !== track.language) {
      parts.push(track.language)
    }
    if (track.codec.length > 0) {
      parts.push(track.codec)
    }
    if (track.channelCount > 0) {
      parts.push(track.channelCount + ' 声道')
    }
    if (track.sampleRate > 0) {
      parts.push((track.sampleRate / 1000).toFixed(1) + ' kHz')
    }
    return parts.length > 0 ? parts.join(' · ') : '内嵌媒体轨'
  }

  private buildAudioTrackSummary(track: PlayerTrack): string {
    const parts: string[] = []
    parts.push(this.getAudioLanguageLabel(track))
    if (track.codec.length > 0) {
      parts.push(track.codec.toUpperCase())
    }
    if (track.channelCount > 0) {
      parts.push(String(track.channelCount) + 'ch')
    }
    if (track.sampleRate > 0) {
      parts.push((track.sampleRate / 1000).toFixed(1) + ' kHz')
    }
    return parts.join(' · ')
  }

  private getAudioLanguageLabel(track: PlayerTrack): string {
    const language = track.language.trim().toLowerCase()
    if (language === 'jpn' || language === 'ja' || language === 'jp' || language === 'japanese') {
      return '日语'
    }
    if (language === 'zho' || language === 'chi' || language === 'zh' || language === 'cmn' ||
      language === 'chinese') {
      return '中文'
    }
    if (language === 'eng' || language === 'en' || language === 'english') {
      return '英语'
    }
    if (language === 'kor' || language === 'ko' || language === 'korean') {
      return '韩语'
    }
    if (language === 'fra' || language === 'fre' || language === 'fr' || language === 'french') {
      return '法语'
    }
    if (language === 'deu' || language === 'ger' || language === 'de' || language === 'german') {
      return '德语'
    }
    if (language.length > 0) {
      return track.language
    }
    if (track.name.length > 0) {
      return track.name
    }
    return '音轨 ' + String(track.index)
  }

  private async selectPlayerTrack(track: PlayerTrack): Promise<void> {
    if (this.playerEngine === null) {
      return
    }
    try {
      await this.playerEngine.selectTrack(track.index)
      await this.refreshPlayerTracks()
      if (track.type === PlayerTrackType.audio) {
        this.showAudioTrackSheet = false
        this.showHudText('已切换音轨')
      } else {
        this.showSubtitleTrackSheet = false
        this.showHudText('已切换字幕')
      }
    } catch (err) {
      logger.warn('切换媒体轨道失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('切换轨道失败')
    }
  }

  private async disableSelectedSubtitleTracks(): Promise<void> {
    const subtitles = this.getTracksByType(PlayerTrackType.subtitle)
    this.externalSubtitleText = ''
    this.secondarySubtitleIndex = -1
    this.setSubtitleMenuSelection('off')
    this.subtitleEnabled = false
    this.setPrimarySubtitleSelectionImmediately(-1)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_ENABLED, false)
    PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_ENABLED, false).catch((_err: void) => {})
    this.stopExternalSubtitleClock()

    try {
      if (this.playerEngine !== null) {
        for (let i = 0; i < subtitles.length; i++) {
          if (subtitles[i].selected) {
            await this.playerEngine.deselectTrack(subtitles[i].index)
          }
        }
        // MPV 外挂字幕并不总能及时出现在轨道列表中；-1 会被 MPV 映射为 sid=no。
        await this.playerEngine.deselectTrack(-1)
        await this.playerEngine.setSecondarySubtitle(-1).catch((_err: Error) => {})
        await this.refreshPlayerTracks()
      }
      await this.persistExternalSubtitleBinding()
      this.showHudText('已关闭字幕')
    } catch (err) {
      logger.warn('关闭字幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('关闭字幕失败')
    }
  }

  private closeAllSubtitlesAndSheet(): void {
    this.showSubtitleTrackSheet = false
    this.subtitleMenuSection = 'primary'
    this.disableSelectedSubtitleTracks()
  }

  private async enableExternalSubtitle(): Promise<void> {
    if (!this.hasLoadedExternalSubtitle()) {
      return
    }
    const previousEnabled = this.subtitleEnabled
    this.setSubtitleMenuSelection('external')
    this.subtitleEnabled = true
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_ENABLED, true)
    PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_ENABLED, true).catch((_err: void) => {})
    try {
      const tracks = this.getTracksByType(PlayerTrackType.subtitle)
      let restored = false
      for (let i = 0; i < tracks.length; i++) {
        if (tracks[i].name === this.externalSubtitleFileName) {
          if (this.playerEngine !== null) {
            await this.playerEngine.selectTrack(tracks[i].index)
          }
          restored = true
          break
        }
      }
      if (!restored && this.isAdvancedAssSubtitle(this.externalSubtitleFileName) && this.playerEngine !== null) {
        await this.playerEngine.addExternalSubtitle(this.externalSubtitleUri, this.externalSubtitleFileName)
        await this.refreshPlayerTracks()
      }
      if (this.externalSubtitleCues.length > 0) {
        this.syncExternalSubtitleClock(this.positionMs, this.isPlaying)
      }
      this.showHudText('已开启外挂字幕')
    } catch (err) {
      this.setSubtitleMenuSelection('off')
      this.subtitleEnabled = previousEnabled
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_ENABLED, previousEnabled)
      PreferencesStore.getInstance().setBoolean(PREFS_KEY_SUBTITLE_ENABLED, previousEnabled).catch((_err: void) => {})
      logger.warn('重新开启外挂字幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('开启外挂字幕失败')
    }
  }

  private async pickAndAddExternalSubtitle(): Promise<void> {
    if (this.playerEngine === null || !this.hasEngine) {
      this.showHudText('播放器尚未就绪')
      return
    }
    try {
      const context = getContext(this) as common.UIAbilityContext
      const result = await LocalFilePicker.pickSubtitleFile(context)
      if (result === null) {
        return
      }

      // ASS/SSA 的定位、动画、描边、字体与逐字效果必须由 libass 渲染。
      // ArkUI 文本回退会剥离所有覆写标签，只用于普通文本字幕。
      if (this.isAdvancedAssSubtitle(result.fileName)) {
        await this.playerEngine.addExternalSubtitle(result.uri, result.fileName)
        this.externalSubtitleCues = []
        this.externalSubtitleText = ''
        this.externalSubtitleFileName = result.fileName
        this.externalSubtitleUri = result.uri
        this.setSubtitleMenuSelection('external')
        this.externalSubtitleRestoreToken++
        await this.refreshPlayerTracks()
        await this.persistExternalSubtitleBinding()
        this.showHudText('已加载特效字幕：' + result.fileName)
        logger.info('MPV libass 特效字幕加载成功: %{public}s', result.fileName)
        return
      }

      const cues = ExternalSubtitleParser.load(result.uri)
      if (cues.length === 0) {
        throw new Error('未识别到可显示的文本字幕')
      }
      this.externalSubtitleCues = cues
      this.externalSubtitleFileName = result.fileName
      this.externalSubtitleUri = result.uri
      this.setSubtitleMenuSelection('external')
      this.externalSubtitleRestoreToken++
      this.syncExternalSubtitleClock(this.positionMs, this.isPlaying)
      await this.persistExternalSubtitleBinding()
      this.showHudText('已加载字幕：' + result.fileName)
      logger.info('ArkUI 外挂字幕加载成功: cues=%{public}d', cues.length)
    } catch (err) {
      logger.warn('加载外挂字幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('加载字幕失败')
    }
  }

  private async setKeepScreenOn(keepScreenOn: boolean): Promise<void> {
    if (this.keepScreenOnRequested === keepScreenOn && this.keepScreenOnEnabled === keepScreenOn) {
      return
    }
    this.keepScreenOnRequested = keepScreenOn
    const requestToken = ++this.keepScreenOnRequestToken
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const mainWindow = await window.getLastWindow(context)
      if (requestToken !== this.keepScreenOnRequestToken) {
        return
      }
      await mainWindow.setWindowKeepScreenOn(keepScreenOn)
      this.keepScreenOnEnabled = keepScreenOn
      if (requestToken !== this.keepScreenOnRequestToken) {
        this.setKeepScreenOn(this.keepScreenOnRequested)
        return
      }
      logger.info('Local screen keep-on changed: %{public}s', String(keepScreenOn))
    } catch (_err) {
      logger.warn('Failed to set local screen keep-on: %{public}s', String(keepScreenOn))
    }
  }

  private syncKeepScreenOnWithPlayback(): void {
    const shouldKeepScreenOn = this.playerKeepScreenOn && this.isPageAlive && this.appInForeground && this.isPlaying &&
      !this.shouldKeepPlaybackForPiP()
    this.setKeepScreenOn(shouldKeepScreenOn)
  }

  private handlePlayerKeyEvent(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return
    }

    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (this.isFullScreen) {
        this.toggleFullScreen()
      }
      return
    }

    if (this.showDanmakuSettingsPanel || this.showDanmakuSettingsSheet) {
      return
    }

    switch (event.keyCode) {
      case KeyCode.KEYCODE_SPACE:
        this.togglePlayPause()
        this.showHudText(this.isPlaying ? '播放' : '暂停')
        break
      case KeyCode.KEYCODE_DPAD_LEFT:
        this.seekTo(Math.max(this.positionMs - 5000, 0))
        this.showHudText('后退 5 秒')
        break
      case KeyCode.KEYCODE_DPAD_RIGHT:
        this.seekTo(Math.min(this.positionMs + 5000, this.durationMs))
        this.showHudText('前进 5 秒')
        break
      case KeyCode.KEYCODE_DPAD_UP:
        this.changePlayerVolume(0.05)
        break
      case KeyCode.KEYCODE_DPAD_DOWN:
        this.changePlayerVolume(-0.05)
        break
      default:
        break
    }
  }

  private changePlayerVolume(delta: number): void {
    const nextVolume = Math.max(0, Math.min(1, this.volume + delta))
    this.volume = nextVolume
    this.requestSystemMediaVolume(nextVolume)
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setVolume(nextVolume)
    }
    this.showHudText(`音量 ${Math.round(nextVolume * 100)}%`)
  }

  private requestSystemMediaVolume(volume: number): void {
    const normalizedVolume = this.clampUnitValue(volume)
    this.volume = normalizedVolume
    this.pendingVolumeValue = normalizedVolume
    const now = Date.now()
    const elapsed = now - this.lastVolumeApplyMs
    if (elapsed >= 80) {
      this.applySystemMediaVolume(normalizedVolume)
      return
    }
    if (this.volumeApplyTimer >= 0) {
      return
    }
    this.volumeApplyTimer = setTimeout(() => {
      this.volumeApplyTimer = -1
      if (this.pendingVolumeValue >= 0) {
        this.applySystemMediaVolume(this.pendingVolumeValue)
      }
    }, 80 - elapsed)
  }

  private async applySystemMediaVolume(volume: number): Promise<void> {
    this.lastVolumeApplyMs = Date.now()
    const normalizedVolume = this.clampUnitValue(volume)
    try {
      const manager = this.getAudioManager()
      const minLevel = await this.getMediaVolumeMinLevel(manager)
      const maxLevel = await this.getMediaVolumeMaxLevel(manager)
      if (maxLevel <= minLevel) {
        logger.warn('系统媒体音量范围无效: %{public}d-%{public}d', minLevel, maxLevel)
        return
      }
      const targetLevel = Math.round(minLevel + normalizedVolume * (maxLevel - minLevel))
      await manager.setVolume(audio.AudioVolumeType.MEDIA, targetLevel)
      logger.info('已设置系统媒体音量: level=%{public}d range=%{public}d-%{public}d',
        targetLevel, minLevel, maxLevel)
    } catch (err) {
      logger.warn('设置系统媒体音量失败: %{public}s', String(err))
    }
  }

  private async loadSystemMediaVolume(): Promise<void> {
    try {
      const manager = this.getAudioManager()
      const minLevel = await this.getMediaVolumeMinLevel(manager)
      const maxLevel = await this.getMediaVolumeMaxLevel(manager)
      if (maxLevel <= minLevel) {
        return
      }
      const currentLevel = await manager.getVolume(audio.AudioVolumeType.MEDIA)
      this.volume = this.clampUnitValue((currentLevel - minLevel) / (maxLevel - minLevel))
      logger.info('已读取系统媒体音量: level=%{public}d range=%{public}d-%{public}d',
        currentLevel, minLevel, maxLevel)
    } catch (err) {
      logger.warn('读取系统媒体音量失败: %{public}s', String(err))
    }
  }

  private getAudioManager(): audio.AudioManager {
    if (this.audioManager === null) {
      this.audioManager = audio.getAudioManager()
    }
    return this.audioManager
  }

  private async getMediaVolumeMinLevel(manager: audio.AudioManager): Promise<number> {
    if (this.mediaVolumeMinLevel < 0) {
      this.mediaVolumeMinLevel = await manager.getMinVolume(audio.AudioVolumeType.MEDIA)
    }
    return this.mediaVolumeMinLevel
  }

  private async getMediaVolumeMaxLevel(manager: audio.AudioManager): Promise<number> {
    if (this.mediaVolumeMaxLevel < 0) {
      this.mediaVolumeMaxLevel = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA)
    }
    return this.mediaVolumeMaxLevel
  }

  private clampUnitValue(value: number): number {
    if (value < 0) {
      return 0
    }
    if (value > 1) {
      return 1
    }
    return value
  }

  private clearVolumeApplyTimer(): void {
    if (this.volumeApplyTimer >= 0) {
      clearTimeout(this.volumeApplyTimer)
      this.volumeApplyTimer = -1
    }
  }

  private shouldIgnoreTransientRebuildZeroState(state: PlayerState): boolean {
    if (this.liveStartPositionMs < PLAYER_REBUILD_RESUME_GUARD_MS || state.positionMs >= 1000 || state.completed || state.error.length > 0) {
      return false
    }
    return state.stateName === 'creating' ||
      state.stateName === 'initialized' ||
      state.stateName === 'prepared' ||
      state.stateName === 'playing'
  }

  /**
   * The existing mpv instance is deliberately reused for queue changes so the
   * XComponent NativeWindow keeps a single EGL owner. During `loadfile replace`,
   * callbacks from the outgoing file can still arrive briefly. Do not let
   * those callbacks overwrite the incoming item's independent resume point.
   */
  private shouldIgnorePendingQueueSwitchState(state: PlayerState): boolean {
    if (this.pendingQueueTargetUri.length === 0) {
      return false
    }
    if (this.pendingQueueTargetUri !== this.videoUri) {
      this.pendingQueueTargetUri = ''
      this.pendingQueueStartPositionMs = 0
      this.queueSwitchSawPreparing = false
      return false
    }
    if (state.stateName === 'creating' || state.stateName === 'initialized' ||
      state.stateName === 'preparing' || state.stateName === 'prepared') {
      this.queueSwitchSawPreparing = true
      this.positionMs = this.pendingQueueStartPositionMs
      this.durationMs = 0
      return true
    }
    if (!this.queueSwitchSawPreparing) {
      logger.info('Ignore outgoing queue state: target=%{public}s state=%{public}s position=%{public}d',
        this.videoFileName, state.stateName, state.positionMs)
      return true
    }
    if (state.stateName === 'playing' || state.stateName === 'paused' ||
      state.stateName === 'completed' || state.stateName === 'error') {
      logger.info('Queue target state accepted: target=%{public}s state=%{public}s start=%{public}d',
        this.videoFileName, state.stateName, this.pendingQueueStartPositionMs)
      this.pendingQueueTargetUri = ''
      this.pendingQueueStartPositionMs = 0
      this.queueSwitchSawPreparing = false
      return false
    }
    return true
  }

  private cacheLivePlaybackPosition(positionMs: number): void {
    const targetUrl = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUri
    if (targetUrl.length === 0 || positionMs <= 0) {
      return
    }
    AppStorage.setOrCreate(PLAYER_LIVE_URL_KEY, targetUrl)
    AppStorage.setOrCreate(PLAYER_LIVE_POSITION_KEY, positionMs)
  }

  private clearLivePlaybackPosition(): void {
    this.liveStartPositionMs = 0
    AppStorage.setOrCreate(PLAYER_LIVE_POSITION_KEY, 0)
  }

  private shouldSyncPlaybackSessionState(state: PlayerState): boolean {
    const now = Date.now()
    const stateChanged = state.stateName !== this.lastPlaybackSessionStateName ||
      state.playing !== this.lastPlaybackSessionPlaying ||
      state.completed ||
      state.error.length > 0
    const positionChanged = this.lastPlaybackSessionPositionMs < 0 ||
      Math.abs(state.positionMs - this.lastPlaybackSessionPositionMs) >= 1000
    const durationChanged = state.durationMs > 0 &&
      Math.abs(state.durationMs - this.lastPlaybackSessionDurationMs) >= 1000
    const timedSync = now - this.lastPlaybackSessionSyncMs >= 1000

    if (!stateChanged && !durationChanged && (!positionChanged || !timedSync)) {
      return false
    }

    this.lastPlaybackSessionSyncMs = now
    this.lastPlaybackSessionStateName = state.stateName
    this.lastPlaybackSessionPlaying = state.playing
    this.lastPlaybackSessionPositionMs = state.positionMs
    if (state.durationMs > 0) {
      this.lastPlaybackSessionDurationMs = state.durationMs
    }
    return true
  }

  private stopPlaybackBeforeLeaving(): void {
    this.isPlaying = false
    if (this.playerEngine !== null) {
      try {
        this.playerEngine.stop()
      } catch (err) {
        logger.warn('Stop local player before leaving failed')
      }
    }
    this.playerEngine = null
    this.hasEngine = false
  }

  private seekTo(positionMs: number): void {
    this.positionMs = positionMs
    this.syncExternalSubtitleClock(positionMs, this.isPlaying)
    this.liveStartPositionMs = positionMs
    if (positionMs > 0) {
      this.lastKnownPositionMs = positionMs
      this.lastHistorySaveMs = Date.now()
      this.cacheLivePlaybackPosition(positionMs)
      this.saveLocalHistory()
    } else {
      this.clearLivePlaybackPosition()
    }
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.seek(positionMs)
    }
    if (this.durationMs > 0 && positionMs < this.durationMs - 1000) {
      // Seeking away from EOF starts a new playback pass. Allow completion and
      // auto-next to be handled again when this pass reaches the end.
      this.completionHandledForUrl = ''
    }
  }

  private normalizeResumePosition(positionMs: number, durationMs: number): number {
    if (positionMs <= 0) {
      return 0
    }
    if (durationMs <= 0) {
      return positionMs
    }
    const clampedPosition = Math.min(positionMs, durationMs)
    const remainingMs = durationMs - clampedPosition
    if (remainingMs <= COMPLETED_RESUME_RESTART_WINDOW_MS ||
      clampedPosition / durationMs >= COMPLETED_RESUME_RESTART_RATIO) {
      return 0
    }
    return clampedPosition
  }

  private toggleDanmaku(): void {
    if (this.danmakuManager !== null) {
      this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
    }
  }

  private setDanmakuEnabled(enabled: boolean): void {
    if (this.isDanmakuEnabled === enabled) {
      return
    }
    if (this.danmakuManager === null) {
      this.isDanmakuEnabled = enabled
      return
    }

    const managerEnabled = this.danmakuManager.getIsDanmakuEnabled()
    if (managerEnabled !== enabled) {
      this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
    } else {
      this.isDanmakuEnabled = enabled
    }
  }

  private toggleControls(): void {
    this.isControlVisible = !this.isControlVisible
    if (this.isControlVisible) {
      this.startAutoHideTimer()
    } else {
      this.pauseAutoHideTimer()
    }
  }

  private showControlsWithAutoHide(): void {
    this.isControlVisible = true
    this.startAutoHideTimer()
  }

  private shouldShowBottomControlLayer(): boolean {
    return this.isControlVisible && !this.hideBottomControlsForFullscreenTransition
  }

  /** 隐藏态的控件可能仍处在渲染树中；所有控制按钮统一以此阻断命中。 */
  private isPlayerControlActionAllowed(): boolean {
    return this.isControlVisible && !this.hideBottomControlsForFullscreenTransition
  }

  private prepareFullscreenControlTransition(): void {
    this.suppressControlAnimation = true
    this.hideBottomControlsForFullscreenTransition = true
    this.isControlVisible = true
    this.showAspectModePanel = false
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.pauseAutoHideTimer()
  }

  private finishFullscreenControlTransition(): void {
    this.isAnimatingFullscreen = false
    this.hideBottomControlsForFullscreenTransition = false
    this.showControlsWithAutoHide()
    this.schedulePlayerAspectSync()
    setTimeout(() => {
      this.suppressControlAnimation = false
    }, 80)
  }

  /**
   * Keep the original SURFACE node on screen and let the system window rotation be the only
   * geometry animation. A second ArkUI width/height animation would run before or after the
   * physical rotation and make one fullscreen switch look like two disconnected transitions.
   */
  private runFullscreenOneShotTransition(fullScreen: boolean, lockLandscape: boolean): void {
    this.clearFullscreenTransitionTimer()
    this.isFullScreen = fullScreen
    this.setFullScreenMode(fullScreen, lockLandscape)
    logger.info('Fullscreen one-shot rotation started: target=%{public}s', String(fullScreen))
    this.fullscreenTransitionTimer = setTimeout(() => {
      this.fullscreenTransitionTimer = -1
      if (!this.isPageAlive) {
        return
      }
      this.finishFullscreenControlTransition()
      logger.info('Fullscreen one-shot rotation settled: target=%{public}s', String(fullScreen))
    }, this.FULLSCREEN_ROTATION_SETTLE_MS)
  }

  private clearFullscreenTransitionTimer(): void {
    if (this.fullscreenTransitionTimer >= 0) {
      clearTimeout(this.fullscreenTransitionTimer)
      this.fullscreenTransitionTimer = -1
    }
  }

  private schedulePlayerAspectSync(): void {
    if (this.playerLayoutSyncTimer >= 0) {
      clearTimeout(this.playerLayoutSyncTimer)
      this.playerLayoutSyncTimer = -1
    }
    this.playerLayoutSyncTimer = setTimeout(() => {
      this.playerLayoutSyncTimer = -1
      if (!this.isPageAlive || !this.hasEngine || this.playerEngine === null) {
        return
      }
      this.playerEngine.setAspectMode(this.currentAspectMode)
      logger.info('布局稳定后已同步播放器画面比例: %{public}s', String(this.currentAspectMode))
    }, 180)
  }

  private clearPlayerAspectSyncTimer(): void {
    if (this.playerLayoutSyncTimer >= 0) {
      clearTimeout(this.playerLayoutSyncTimer)
      this.playerLayoutSyncTimer = -1
    }
  }

  private getControlAnimationDuration(): number {
    return this.suppressControlAnimation ? 0 : 260
  }

  private setPlaybackSpeed(newSpeed: number): void {
    this.speed = newSpeed
    this.speedLabel = this.formatPlaybackSpeed(newSpeed)
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(newSpeed)
    }
    if (this.danmakuManager !== null) {
      const renderer = this.danmakuManager.getRenderer()
      if (renderer !== null) {
        renderer.setPlaybackSpeed(newSpeed)
      }
    }
  }

  private async startPiP(): Promise<boolean> {
    if (this.pipManager.isActive() || this.pipManager.isCreating()) {
      return true
    }
    if (this.xComponentController === null) {
      logger.warn('PiP: XComponentController not available')
      return false
    }
    this.pauseAutoHideTimer()
    const context = getContext(this) as common.UIAbilityContext
    const contentWidth = this.videoWidth > 0 ? this.videoWidth : 1920
    const contentHeight = this.videoHeight > 0 ? this.videoHeight : 1080
    const isWideContent = contentWidth > contentHeight
    const controlGroups: Array<PiPWindow.VideoPlayControlGroup> = [
      PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT
    ]
    const success = await this.pipManager.createAndStart(
      context, this.xComponentController, contentWidth, contentHeight, controlGroups,
      isWideContent ? 2 : 1)
    if (success) {
      this.keepPlaybackForPiP = true
      this.isRestoringFromPiP = false
      this.isPiPActive = true
      this.pipManager.updatePlaybackState(this.isPlaying)
      this.pipManager.setNextPreviousEnabled(false, false)
    }
    return success
  }

  private async startPiPFromControl(): Promise<void> {
    if (!this.hasEngine || this.xComponentController === null) {
      this.showHudText('播放器尚未就绪')
      return
    }
    const success = await this.startPiP()
    if (!success) {
      this.showHudText('画中画启动失败')
    }
  }

  private formatPlaybackSpeed(value: number): string {
    return value % 1 === 0 ? value.toFixed(0) + 'x' : value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '') + 'x'
  }

  private seekByConfiguredSeconds(forward: boolean): void {
    if (!this.hasEngine || this.durationMs <= 0) {
      return
    }
    const seconds = normalizeSeekSeconds(this.playerSeekSeconds)
    const offsetMs = forward ? seconds * 1000 : -seconds * 1000
    const targetMs = Math.max(0, Math.min(this.positionMs + offsetMs, this.durationMs))
    this.seekTo(targetMs)
    this.showHudText(forward ? '前进 ' + seconds + ' 秒' : '后退 ' + seconds + ' 秒')
  }

  private registerPlaybackSessionActions(): void {
    const actions = new PlaybackSessionActions()
    actions.onPlay = () => {
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
      }
    }
    actions.onPause = () => {
      if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
        this.playerEngine.pause()
        this.isPlaying = false
      }
    }
    actions.onSeek = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    actions.onFastForward = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    actions.onRewind = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    this.playbackSessionStore.setActions(actions, 'local-player')
    this.syncPlaybackSessionMedia()
  }

  private syncPlaybackSessionMedia(): void {
    const url = this.videoUri.length > 0 ? this.videoUri : this.playbackOptions.url
    if (url.length === 0) {
      return
    }
    this.playbackSessionStore.updateMedia(url, this.videoFileName.length > 0 ? this.videoFileName : '本地视频',
      '', '', this.durationMs, this.positionMs, false, false, true, 'local-player')
  }

  private buildPiPCallbacks(): PiPCallbacks {
    const callbacks = new PiPCallbacks()
    callbacks.onPlay = () => {
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
        this.pipManager.updatePlaybackState(true)
      }
    }
    callbacks.onPause = () => {
      if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
        this.playerEngine.pause()
        this.isPlaying = false
        this.pipManager.updatePlaybackState(false)
      }
    }
    callbacks.onFastForward = () => {
      if (this.hasEngine && this.playerEngine !== null) {
        this.seekTo(Math.min(this.positionMs + normalizeSeekSeconds(this.playerSeekSeconds) * 1000, this.durationMs))
      }
    }
    callbacks.onFastBackward = () => {
      if (this.hasEngine && this.playerEngine !== null) {
        this.seekTo(Math.max(this.positionMs - normalizeSeekSeconds(this.playerSeekSeconds) * 1000, 0))
      }
    }
    callbacks.onRestore = () => {
      this.isPageAlive = true
      this.keepPlaybackForPiP = false
      this.isRestoringFromPiP = true
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
      }
      this.isPiPActive = false
      this.syncKeepScreenOnWithPlayback()
    }
    callbacks.onPiPStopped = () => {
      if (this.isRestoringFromPiP) {
        this.isRestoringFromPiP = false
        this.keepPlaybackForPiP = false
        this.isPiPActive = false
        return
      }
      if (this.keepPlaybackForPiP) {
        this.stopPlaybackBeforeLeaving()
      }
      this.keepPlaybackForPiP = false
      this.isPiPActive = false
      this.syncKeepScreenOnWithPlayback()
    }
    return callbacks
  }

  private toggleFullScreen(): void {
    if (this.isAnimatingFullscreen) {
      return
    }
    this.isAnimatingFullscreen = true
    this.prepareFullscreenControlTransition()

    this.runFullscreenOneShotTransition(!this.isFullScreen, true)
  }

  /** Local videos open directly in landscape fullscreen; the user can still exit with the normal control. */
  private enterFullscreenOnOpen(): void {
    if (this.videoUri.length === 0 || this.isFullScreen) {
      return
    }
    this.isFullScreen = true
    this.setFullScreenMode(true, true)
  }

  private async setFullScreenMode(fullScreen: boolean, lockLandscape: boolean = true): Promise<void> {
    AppStorage.setOrCreate('playerFullScreen', fullScreen)
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (fullScreen) {
        mainWindow.setWindowSystemBarEnable([])
        if (lockLandscape && this.isPhoneDevice()) {
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE)
        }
        mainWindow.enableLandscapeMultiWindow().catch((err: BusinessError) => {
          logger.warn('enableLandscapeMultiWindow failed: %{public}d', err.code)
        })
      } else {
        mainWindow.setWindowSystemBarEnable(['status', 'navigation'])
        if (this.isPhoneDevice()) {
          // The reference player requests a concrete portrait target. Restoring UNSPECIFIED
          // makes WMS choose the target again and can add an avoidable visual correction.
          await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        } else {
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
        }
        mainWindow.disableLandscapeMultiWindow().catch((err: BusinessError) => {
          logger.warn('disableLandscapeMultiWindow failed: %{public}d', err.code)
        })
      }
    } catch (_err) {
      logger.warn('Failed to toggle fullscreen mode')
    }
  }

  private handlePlayerAreaChange(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return
    }
    // 旋转中会出现短暂的中间尺寸（如 373 × 373）；仅在布局稳定后同步画面模式。
    this.schedulePlayerAspectSync()
  }

  private isPhoneDevice(): boolean {
    return this.screenWidthVp < 600
  }

  private async requestWindowBrightness(brightness: number): Promise<void> {
    this.screenBrightness = brightness
    this.schedulePageBrightnessPreferenceSave(brightness)
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const mainWindow = await window.getLastWindow(context)
      await mainWindow.setWindowBrightness(brightness)
    } catch (_err) {
      logger.warn('Failed to apply window brightness')
    }
  }

  /** 仅持久化播放器页面的亮度偏好，不修改系统全局亮度。 */
  private schedulePageBrightnessPreferenceSave(brightness: number): void {
    this.pendingPageBrightness = brightness
    if (this.pageBrightnessSaveTimer >= 0) {
      return
    }
    this.pageBrightnessSaveTimer = setTimeout(() => {
      this.pageBrightnessSaveTimer = -1
      this.flushPageBrightnessPreference()
    }, PLAYER_PAGE_BRIGHTNESS_SAVE_DELAY_MS)
  }

  private flushPageBrightnessPreference(): void {
    if (this.pageBrightnessSaveTimer >= 0) {
      clearTimeout(this.pageBrightnessSaveTimer)
      this.pageBrightnessSaveTimer = -1
    }
    if (this.pendingPageBrightness < 0) {
      return
    }
    const brightness = this.pendingPageBrightness
    this.pendingPageBrightness = -1
    PreferencesStore.getInstance().setNumber(PREFS_KEY_PLAYER_PAGE_BRIGHTNESS, brightness)
      .catch((_err: void) => {})
  }

  /** 重新进入播放页时恢复上次页面亮度；没有偏好则继续跟随系统。 */
  private async restoreSavedPageBrightness(): Promise<void> {
    try {
      const brightness = await PreferencesStore.getInstance()
        .getNumber(PREFS_KEY_PLAYER_PAGE_BRIGHTNESS, -1)
      if (brightness >= 0.05 && brightness <= 1) {
        await this.requestWindowBrightness(brightness)
      }
    } catch (_err) {
      // 无历史偏好时保持窗口跟随系统亮度。
    }
  }

  /** -1 代表取消页面亮度覆盖，恢复控制中心所设置的系统亮度。 */
  private async restoreSystemBrightness(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const mainWindow = await window.getLastWindow(context)
      await mainWindow.setWindowBrightness(-1)
      logger.info('Local player page brightness restored to system brightness')
    } catch (_err) {
      logger.warn('Failed to restore system brightness')
    }
  }

  private applyAspectMode(mode: VideoAspectMode): void {
    this.currentAspectMode = mode
    PreferencesStore.getInstance().setNumber('videoAspectModeV2', mode).catch((_err: void) => {})
  }

  private async loadAspectModePreference(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      // V1 persisted values were produced while the mpv output ignored the
      // intended aspect semantics.  Start the corrected implementation in
      // contain mode once, then persist subsequent user choices under V2.
      const savedMode = await prefs.getNumber('videoAspectModeV2', VideoAspectMode.contain)
      this.currentAspectMode = VideoAspectModeHelper.fromValue(savedMode)
    } catch (_err) {
      this.currentAspectMode = VideoAspectMode.contain
    }
  }

  private async loadPlayerAutoPiPPreference(): Promise<void> {
    try {
      this.playerAutoPiP = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_PLAYER_AUTO_PIP,
        PLAYER_AUTO_PIP_DEFAULT
      )
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, this.playerAutoPiP)
    } catch (_err) {
      this.playerAutoPiP = PLAYER_AUTO_PIP_DEFAULT
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, PLAYER_AUTO_PIP_DEFAULT)
    }
  }

  private async loadPlaybackPreferences(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      this.playerDefaultSpeed = normalizePlayerSpeed(await prefs.getNumber(PREFS_KEY_PLAYER_DEFAULT_SPEED, PLAYER_DEFAULT_SPEED))
      this.playerSeekSeconds = normalizeSeekSeconds(await prefs.getNumber(PREFS_KEY_PLAYER_SEEK_SECONDS, PLAYER_SEEK_SECONDS_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_DEFAULT_SPEED, this.playerDefaultSpeed)
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_SEEK_SECONDS, this.playerSeekSeconds)
      this.applyDefaultPlaybackSpeed()
      this.syncKeepScreenOnWithPlayback()
    } catch (_err) {
      // Defaults are already populated in AppStorage during ability creation.
    }
  }

  private applyDefaultPlaybackSpeed(): void {
    const targetSpeed = normalizePlayerSpeed(this.playerDefaultSpeed)
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(targetSpeed)
    }
    this.speed = targetSpeed
    this.speedLabel = targetSpeed % 1 === 0 ? targetSpeed.toFixed(0) + 'x' : targetSpeed.toFixed(2).replace(/0+$/, '').replace(/\.$/, '') + 'x'
  }

  private startTemporarySpeed(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.temporarySpeedRestoreValue = this.speed
      this.playerEngine.setSpeed(3.0)
      this.speed = 3.0
      this.speedLabel = '3x'
    }
  }

  private endTemporarySpeed(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      const targetSpeed = this.speed === 3.0 ? this.temporarySpeedRestoreValue : this.speed
      this.playerEngine.setSpeed(targetSpeed)
      this.speed = targetSpeed
      this.speedLabel = targetSpeed % 1 === 0 ? targetSpeed.toFixed(0) + 'x' : targetSpeed.toFixed(1) + 'x'
    }
  }

  private openDanmakuSettings(): void {
    this.danmakuSettingsOpenVersion++
    if (this.isFullScreen) {
      this.showDanmakuSettingsPanel = true
    } else {
      this.showDanmakuSettingsSheet = true
    }
    this.pauseAutoHideTimer()
  }

  private openDanmakuManageSheet(): void {
    logger.info('Open local danmaku manage sheet')
    this.showDanmakuManageSheet = true
    this.showHudText('弹幕')
    this.pauseAutoHideTimer()
  }

  private runAfterDanmakuManageClosed(action: () => void): void {
    this.showDanmakuManageSheet = false
    setTimeout(() => {
      action()
    }, 80)
  }

  private handleDanmakuPrimaryAction(): void {
    if (this.danmakuFileName.length > 0) {
      this.openDanmakuManageSheet()
      return
    }
    this.pickAndLoadLocalDanmaku()
  }

  private closeDanmakuSettings(): void {
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.startAutoHideTimer()
  }

  private onDanmakuSettingsVersionChanged(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.reloadSettings()
    }
  }

  private async pickAndLoadLocalDanmaku(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const fileResult: LocalFileResult | null = await LocalFilePicker.pickDanmakuFile(context)
      if (fileResult === null) {
        return
      }
      const parseResult: LocalDanmakuParseResult | null = this.parseLocalDanmakuResult(fileResult)
      if (parseResult === null) return

      if (this.danmakuManager !== null && this.danmakuManager.hasDanmakuData()) {
        this.pendingDanmakuItems = parseResult.items
        this.pendingDanmakuFileName = fileResult.fileName
        this.pendingDanmakuFormat = this.formatFormatLabel(parseResult.format)
        this.pendingDanmakuUri = fileResult.uri
        this.showDanmakuLoadDialog = true
      } else {
        this.applyParsedDanmaku(fileResult.fileName, fileResult.uri, parseResult)
        this.showHudText('加载 ' + parseResult.items.length + ' 条弹幕 (' + this.danmakuLoadedFormat + ')')
        this.saveLocalHistory()
      }
    } catch (err) {
      logger.error('加载本地弹幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('加载本地弹幕失败')
    }
  }

  private applyPendingDanmaku(append: boolean): void {
    if (this.danmakuManager !== null) {
      if (append) {
        this.danmakuManager.appendLocalDanmaku(this.pendingDanmakuItems)
        this.danmakuLoadedCount += this.pendingDanmakuItems.length
        this.showHudText('追加 ' + this.pendingDanmakuItems.length + ' 条弹幕')
      } else {
        this.danmakuOffsetMs = 0
        this.danmakuManager.resetDanmakuOffset()
        this.danmakuManager.loadLocalDanmaku(this.pendingDanmakuItems)
        this.danmakuLoadedCount = this.pendingDanmakuItems.length
        this.showHudText('替换为 ' + this.pendingDanmakuItems.length + ' 条弹幕')
      }
      this.danmakuFileName = this.pendingDanmakuFileName
      this.danmakuLoadedFormat = this.pendingDanmakuFormat
      this.danmakuUri = this.pendingDanmakuUri
      this.saveLocalHistory()
    }
    this.pendingDanmakuItems = []
    this.pendingDanmakuFileName = ''
    this.pendingDanmakuFormat = ''
    this.pendingDanmakuUri = ''
  }

  private async pickVideoFile(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const videoResult = await LocalFilePicker.pickVideoFile(context)
      if (videoResult === null) {
        return
      }
      this.videoUri = videoResult.uri
      this.videoFileName = videoResult.fileName
      this.videoFileSize = videoResult.fileSize
      const pickedItem = new PlaybackQueueItem()
      pickedItem.uri = videoResult.uri
      pickedItem.name = videoResult.fileName
      pickedItem.size = videoResult.fileSize
      this.playbackQueue = [pickedItem]
      this.currentQueueIndex = 0
      this.positionMs = 0
      this.durationMs = 0
      this.lastKnownPositionMs = 0
      this.clearLivePlaybackPosition()
      this.playbackErrorText = ''
      this.clearDanmakuState()
      const options = new PlaybackOptions()
      options.url = this.videoUri
      options.isLocalFile = true
      options.localFileSize = this.videoFileSize
      this.playbackOptions = options
      logger.info('选择本地视频: %{public}s', videoResult.fileName)
    } catch (err) {
      logger.error('选择视频文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('选择视频文件失败')
    }
  }

  private async authorizeCurrentVideo(): Promise<void> {
    if (this.videoUri.length === 0) {
      return
    }
    try {
      const context = getContext(this) as common.UIAbilityContext
      const authorized = await LocalFilePicker.ensureReadableUri(this.videoUri) ||
        await LocalFilePicker.authorizeExistingUri(context, this.videoUri)
      if (!authorized) {
        this.showHudText('授权失败')
        return
      }
      this.playbackErrorText = ''
      const options = new PlaybackOptions()
      options.url = this.videoUri
      options.isLocalFile = true
      options.localFileSize = this.videoFileSize
      if (this.lastKnownPositionMs > 0) {
        options.startPositionMs = this.lastKnownPositionMs
      }
      this.playbackOptions = options
      this.showHudText('授权成功')
    } catch (err) {
      logger.warn('重新授权本地视频失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('授权失败')
    }
  }

  private canAuthorizeCurrentVideo(): boolean {
    return this.videoUri.length > 0
  }

  private showHudText(text: string): void {
    this.hudText = text
    this.showHud = true
    this.clearHudTimer()
    this.hudTimer = setTimeout(() => {
      this.showHud = false
    }, 1500)
  }

  private startAutoHideTimer(): void {
    this.pauseAutoHideTimer()
    this.controlHideTimer = setTimeout(() => {
      this.isControlVisible = false
    }, 5000)
  }

  private pauseAutoHideTimer(): void {
    if (this.controlHideTimer >= 0) {
      clearTimeout(this.controlHideTimer)
      this.controlHideTimer = -1
    }
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer)
      this.hudTimer = -1
    }
  }

  private adjustDanmakuOffset(deltaMs: number): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.applyDanmakuOffset(deltaMs)
      this.danmakuOffsetMs = this.danmakuManager.getCurrentOffsetMs()
      this.showHudText('弹幕偏移 ' + this.formatOffset(this.danmakuOffsetMs))
      this.saveLocalHistory()
    }
  }

  private resetDanmakuOffset(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.resetDanmakuOffset()
      this.danmakuOffsetMs = 0
      this.showHudText('弹幕偏移已重置')
      this.saveLocalHistory()
    }
  }

  /** Saves progress; only an actual exit refreshes the history cover at the current frame. */
  private async saveLocalHistory(captureExitFrame: boolean = false): Promise<void> {
    if (this.videoFileName.length === 0) {
      return
    }
    try {
      if (this.playerEngine !== null) {
        const latestState = this.playerEngine.getState()
        if (latestState.positionMs > this.positionMs) {
          this.positionMs = latestState.positionMs
        }
        if (latestState.positionMs > this.lastKnownPositionMs) {
          this.lastKnownPositionMs = latestState.positionMs
        }
        if (latestState.durationMs > this.durationMs) {
          this.durationMs = latestState.durationMs
        }
      }
      if (this.positionMs <= 0 && this.lastKnownPositionMs > 0) {
        this.positionMs = this.lastKnownPositionMs
      }
      if (this.durationMs > 0 && this.positionMs <= 0) {
        logger.info('Skip local history save with zero position: name=%{public}s duration=%{public}d',
          this.videoFileName, this.durationMs)
        return
      }
      const record = new LocalVideoRecord()
      record.fileUri = this.videoUri
      record.fileName = this.videoFileName
      record.fileSize = this.videoFileSize
      record.durationMs = this.durationMs
      record.positionMs = this.playerRememberPosition ? this.positionMs : 0
      if (captureExitFrame) {
        record.coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(this.videoUri, this.videoFileName, this.videoFileSize, this.positionMs)
      }
      record.lastPlayedAt = Date.now()
      record.danmakuFileName = this.danmakuFileName
      record.danmakuUri = this.danmakuUri
      record.danmakuOffsetMs = this.danmakuOffsetMs
      record.danmakuFormat = this.danmakuLoadedFormat
      record.danmakuCount = this.danmakuLoadedCount
      record.externalSubtitleFileName = this.externalSubtitleFileName
      record.externalSubtitleUri = this.externalSubtitleUri
      record.createdAt = Date.now()
      logger.info('Save local history: name=%{public}s position=%{public}d duration=%{public}d',
        this.videoFileName, this.positionMs, this.durationMs)
      await this.localVideoHistoryStore.upsert(record)
    } catch (err) {
      logger.warn('保存本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  /** Saves the subtitle selection immediately, including before first playback progress exists. */
  private async persistExternalSubtitleBinding(): Promise<void> {
    if (this.videoUri.length === 0 || this.videoFileName.length === 0) {
      return
    }
    try {
      await this.localVideoHistoryStore.updateExternalSubtitleBinding(
        this.videoUri, this.videoFileName, this.videoFileSize,
        this.externalSubtitleFileName, this.externalSubtitleUri)
      logger.info('已持久化外挂字幕选择: video=%{public}s subtitle=%{public}s',
        this.videoFileName, this.externalSubtitleFileName)
    } catch (err) {
      logger.warn('持久化外挂字幕选择失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async restoreExternalSubtitleFromHistory(): Promise<void> {
    const targetVideoUri = this.videoUri
    if (targetVideoUri.length === 0 || this.externalSubtitleRestoreAttemptedForUrl === targetVideoUri ||
      this.externalSubtitleRestoreInProgressForUrl === targetVideoUri) {
      return
    }
    this.externalSubtitleRestoreInProgressForUrl = targetVideoUri
    const restoreToken = ++this.externalSubtitleRestoreToken
    try {
      const record = await this.localVideoHistoryStore.getByFileIdentity(
        targetVideoUri, this.videoFileName, this.videoFileSize)
      if (record === null || record.externalSubtitleUri.length === 0) {
        this.externalSubtitleRestoreAttemptedForUrl = targetVideoUri
        return
      }

      if (this.isAdvancedAssSubtitle(record.externalSubtitleFileName)) {
        if (this.playerEngine === null || !this.hasEngine) {
          return
        }
        await this.playerEngine.addExternalSubtitle(record.externalSubtitleUri, record.externalSubtitleFileName)
        if (!this.isPageAlive || targetVideoUri !== this.videoUri || restoreToken !== this.externalSubtitleRestoreToken) {
          return
        }
        this.externalSubtitleCues = []
        this.externalSubtitleText = ''
        this.externalSubtitleFileName = record.externalSubtitleFileName
        this.externalSubtitleUri = record.externalSubtitleUri
        this.setSubtitleMenuSelection(this.subtitleEnabled ? 'external' : 'off')
        await this.refreshPlayerTracks()
        this.externalSubtitleRestoreAttemptedForUrl = targetVideoUri
        logger.info('已自动恢复 MPV 特效字幕: video=%{public}s subtitle=%{public}s',
          this.videoFileName, this.externalSubtitleFileName)
        return
      }

      const cues = ExternalSubtitleParser.load(record.externalSubtitleUri)
      if (cues.length === 0) {
        throw new Error('未识别到可显示的文本字幕')
      }
      if (!this.isPageAlive || targetVideoUri !== this.videoUri || restoreToken !== this.externalSubtitleRestoreToken) {
        return
      }
      this.externalSubtitleCues = cues
      this.externalSubtitleFileName = record.externalSubtitleFileName
      this.externalSubtitleUri = record.externalSubtitleUri
      this.setSubtitleMenuSelection(this.subtitleEnabled ? 'external' : 'off')
      this.syncExternalSubtitleClock(this.positionMs, this.isPlaying)
      this.externalSubtitleRestoreAttemptedForUrl = targetVideoUri
      logger.info('已自动恢复外挂字幕: video=%{public}s subtitle=%{public}s cues=%{public}d',
        this.videoFileName, this.externalSubtitleFileName, cues.length)
    } catch (err) {
      if (!this.isPageAlive || targetVideoUri !== this.videoUri || restoreToken !== this.externalSubtitleRestoreToken) {
        return
      }
      logger.warn('自动恢复外挂字幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      // 恢复失败可能只是播放器尚未完成初始化或短暂文件访问失败，不能据此删除已保存选择。
    } finally {
      if (this.externalSubtitleRestoreInProgressForUrl === targetVideoUri) {
        this.externalSubtitleRestoreInProgressForUrl = ''
      }
    }
  }

  private isAdvancedAssSubtitle(fileName: string): boolean {
    const lowerName = fileName.toLowerCase()
    return lowerName.endsWith('.ass') || lowerName.endsWith('.ssa')
  }

  private restoreDanmakuFromHistory(): void {
    if (this.danmakuUri.length === 0 || this.danmakuFileName.length === 0 || this.danmakuManager === null) {
      return
    }
    LocalFilePicker.ensureReadableUri(this.danmakuUri).then((readable: boolean) => {
      if (!readable) {
        this.showHudText('弹幕文件需要重新选择')
        this.clearDanmakuState()
        return
      }
      const fileResult = LocalFilePicker.readDanmakuFileByUri(this.danmakuUri, this.danmakuFileName)
      if (fileResult === null) {
        this.showHudText('弹幕恢复失败')
        this.clearDanmakuState()
        return
      }
      const parseResult: LocalDanmakuParseResult = DanmakuFileParser.parse(fileResult.fileName, fileResult.content)
      if (parseResult.errorMessage.length > 0 || parseResult.items.length === 0) {
        this.showHudText('弹幕恢复失败')
        this.clearDanmakuState()
        return
      }
      this.danmakuLoadedFormat = this.danmakuLoadedFormat.length > 0 ? this.danmakuLoadedFormat : this.formatFormatLabel(parseResult.format)
      this.danmakuLoadedCount = parseResult.items.length
      if (this.danmakuManager !== null) {
        this.danmakuManager.loadLocalDanmaku(parseResult.items)
        if (this.danmakuOffsetMs !== 0) {
          this.danmakuManager.applyDanmakuOffset(this.danmakuOffsetMs)
        }
      }
      logger.info('历史弹幕恢复成功: %{public}s count=%{public}d', this.danmakuFileName, parseResult.items.length)
      this.saveLocalHistory()
    }).catch((err: Error) => {
      logger.warn('历史弹幕授权恢复失败: %{public}s', err.message)
      this.clearDanmakuState()
    })
  }

  private clearDanmakuState(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.clearLocalDanmaku()
    }
    this.danmakuFileName = ''
    this.danmakuUri = ''
    this.danmakuOffsetMs = 0
    this.danmakuLoadedFormat = ''
    this.danmakuLoadedCount = 0
  }

  private parseLocalDanmakuResult(fileResult: LocalFileResult): LocalDanmakuParseResult | null {
    const parseResult: LocalDanmakuParseResult = DanmakuFileParser.parse(fileResult.fileName, fileResult.content)
    if (parseResult.errorMessage.length > 0) {
      this.showHudText('弹幕解析失败: ' + parseResult.errorMessage)
      return null
    }
    if (parseResult.items.length === 0) {
      this.showHudText('弹幕文件为空')
      return null
    }
    return parseResult
  }

  private applyParsedDanmaku(fileName: string, uri: string, parseResult: LocalDanmakuParseResult): void {
    this.danmakuFileName = fileName
    this.danmakuUri = uri
    this.danmakuLoadedFormat = this.formatFormatLabel(parseResult.format)
    this.danmakuLoadedCount = parseResult.items.length
    this.danmakuOffsetMs = 0
    if (this.danmakuManager !== null) {
      this.danmakuManager.resetDanmakuOffset()
      this.danmakuManager.loadLocalDanmaku(parseResult.items)
    }
  }

  private ensurePlaybackQueueForCurrentVideo(): void {
    if (this.playbackQueue.length === 0) {
      const item = new PlaybackQueueItem()
      item.uri = this.videoUri
      item.name = this.videoFileName
    item.size = this.videoFileSize
    item.positionMs = this.historySeekMs > 0 ? this.historySeekMs : 0
    item.durationMs = this.historyDurationMs
      this.playbackQueue = [item]
      this.currentQueueIndex = 0
      return
    }
    if (this.currentQueueIndex >= 0 && this.currentQueueIndex < this.playbackQueue.length &&
      this.playbackQueue[this.currentQueueIndex].uri === this.videoUri) {
      return
    }
    for (let i = 0; i < this.playbackQueue.length; i++) {
      if (this.playbackQueue[i].uri === this.videoUri) {
        this.currentQueueIndex = i
        return
      }
    }
    const item = new PlaybackQueueItem()
    item.uri = this.videoUri
    item.name = this.videoFileName
    item.size = this.videoFileSize
    this.playbackQueue = [item]
    this.currentQueueIndex = 0
  }

  private getPlaybackQueueLabel(): string {
    if (this.playbackQueue.length === 0 || this.currentQueueIndex < 0) {
      return '无列表'
    }
    return String(this.currentQueueIndex + 1) + ' / ' + String(this.playbackQueue.length)
  }

  private playPreviousQueueItem(): void {
    if (this.currentQueueIndex <= 0) {
      promptAction.showToast({ message: '已经是第一集了' })
      return
    }
    this.playQueueItem(this.currentQueueIndex - 1, false)
  }

  private playNextQueueItem(autoPlay: boolean): void {
    const nextIndex = this.currentQueueIndex + 1
    if (nextIndex >= this.playbackQueue.length) {
      if (!autoPlay) {
        promptAction.showToast({ message: '已经是最后一集了' })
      }
      return
    }
    this.playQueueItem(nextIndex, autoPlay)
  }

  private async playQueueItem(index: number, autoPlay: boolean): Promise<void> {
    if (index < 0 || index >= this.playbackQueue.length) {
      return
    }
    const item = this.playbackQueue[index]
    if (!await LocalFilePicker.ensureReadableUri(item.uri)) {
      this.showHudText('下一个视频暂时不可访问')
      return
    }
    this.captureCurrentQueueProgress()
    const startPositionMs = this.normalizeResumePosition(item.positionMs, item.durationMs)
    this.pendingQueueTargetUri = item.uri
    this.pendingQueueStartPositionMs = startPositionMs
    this.queueSwitchSawPreparing = false
    this.showPlaybackQueue = false
    this.currentQueueIndex = index
    this.videoUri = item.uri
    this.videoFileName = item.name
    this.videoFileSize = item.size
    this.positionMs = 0
    this.durationMs = 0
    this.lastKnownPositionMs = startPositionMs
    this.clearLivePlaybackPosition()
    this.liveStartPositionMs = startPositionMs
    this.playbackErrorText = ''
    this.externalSubtitleCues = []
    this.externalSubtitleText = ''
    this.externalSubtitleFileName = ''
    this.externalSubtitleUri = ''
    this.setSubtitleMenuSelection('off')
    this.externalSubtitleRestoreAttemptedForUrl = ''
    this.externalSubtitleRestoreInProgressForUrl = ''
    this.externalSubtitleRestoreToken++
    this.stopExternalSubtitleClock()
    this.availableTracks = []
    this.tracksLoadedForUrl = ''
    this.videoInfoLoadedForUrl = ''
    this.videoCodec = ''
    this.videoFrameRate = 0
    this.videoBitrate = 0
    this.videoDecoder = ''
    this.videoDynamicRange = ''
    this.completionHandledForUrl = ''
    const options = new PlaybackOptions()
    options.url = item.uri
    options.isLocalFile = true
    options.localFileSize = item.size
    options.startPositionMs = startPositionMs
    this.playbackOptions = options
    this.showHudText(autoPlay ? '正在播放下一项' : '已切换视频')
  }

  private captureCurrentQueueProgress(): void {
    if (this.currentQueueIndex < 0 || this.currentQueueIndex >= this.playbackQueue.length) {
      return
    }
    const currentItem = this.playbackQueue[this.currentQueueIndex]
    if (currentItem.uri !== this.videoUri) {
      return
    }
    let currentPositionMs = this.positionMs
    let currentDurationMs = this.durationMs
    if (this.playerEngine !== null) {
      const state = this.playerEngine.getState()
      if (state.positionMs >= 0) {
        currentPositionMs = state.positionMs
      }
      if (state.durationMs > 0) {
        currentDurationMs = state.durationMs
      }
    }
    currentItem.positionMs = Math.max(0, currentPositionMs)
    currentItem.durationMs = Math.max(0, currentDurationMs)
    logger.info('Captured queue progress: index=%{public}d position=%{public}d duration=%{public}d',
      this.currentQueueIndex, currentItem.positionMs, currentItem.durationMs)
  }

  private hasVideoInfo(): boolean {
    return this.videoCodec.length > 0 || (this.videoWidth > 0 && this.videoHeight > 0) ||
      this.videoFrameRate > 0 || this.videoBitrate > 0 || this.videoDecoder.length > 0 ||
      this.videoDynamicRange.length > 0
  }

  private formatVideoCodec(): string {
    const codec = this.videoCodec.toLowerCase()
    if (codec.indexOf('hevc') >= 0 || codec.indexOf('h265') >= 0) {
      return 'HEVC'
    }
    if (codec.indexOf('h264') >= 0 || codec.indexOf('avc') >= 0) {
      return 'H.264'
    }
    if (codec.indexOf('av1') >= 0) {
      return 'AV1'
    }
    if (codec.indexOf('vp9') >= 0) {
      return 'VP9'
    }
    return this.videoCodec.toUpperCase()
  }

  private formatVideoFrameRate(): string {
    const rounded = Math.round(this.videoFrameRate * 100) / 100
    return (Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2).replace(/0+$/, '').replace(/\.$/, '')) + 'fps'
  }

  private formatVideoBitrate(): string {
    if (this.videoBitrate >= 1000000) {
      const mbps = Math.round(this.videoBitrate / 100000) / 10
      return (Number.isInteger(mbps) ? String(mbps) : mbps.toFixed(1)) + 'Mbps'
    }
    return String(Math.round(this.videoBitrate / 1000)) + 'Kbps'
  }

  private getAspectModeLabel(): string {
    return VideoAspectModeHelper.getLabel(this.currentAspectMode)
  }

  private formatFileSize(size: number): string {
    if (size <= 0) {
      return '未知大小'
    }
    const mb = size / 1024 / 1024
    if (mb < 1024) {
      return mb.toFixed(mb >= 100 ? 0 : 1) + ' MB'
    }
    const gb = mb / 1024
    return gb.toFixed(gb >= 100 ? 0 : 1) + ' GB'
  }

  private formatOffset(ms: number): string {
    if (ms === 0) {
      return '0s'
    }
    const sign = ms > 0 ? '+' : ''
    const absMs = Math.abs(ms)
    if (absMs >= 1000) {
      const seconds = absMs / 1000
      return sign + (seconds % 1 === 0 ? seconds.toFixed(0) : seconds.toFixed(1)) + 's'
    }
    return sign + absMs + 'ms'
  }

  private formatFormatLabel(format: string): string {
    if (format === 'bilibili-xml') {
      return 'B站 XML'
    }
    if (format === 'dandan-json') {
      return '弹弹 JSON'
    }
    if (format === 'ass') {
      return 'ASS'
    }
    return format.toUpperCase()
  }

  private buildCurrentDanmakuText(): string {
    if (this.danmakuFileName.length === 0) {
      return '未加载弹幕，支持 B站 XML / 弹弹 JSON / ASS'
    }
    let text = this.danmakuLoadedFormat.length > 0 ? this.danmakuLoadedFormat : '本地弹幕'
    if (this.danmakuLoadedCount > 0) {
      text += ' · ' + this.danmakuLoadedCount + ' 条'
    }
    if (this.danmakuOffsetMs !== 0) {
      text += ' · ' + this.formatOffset(this.danmakuOffsetMs)
    }
    text += ' · ' + this.danmakuFileName
    return text
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    if (hours > 0) {
      return hours + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
    }
    return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
  }
}
