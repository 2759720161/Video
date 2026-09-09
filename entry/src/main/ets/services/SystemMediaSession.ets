import { common, wantAgent } from '@kit.AbilityKit'
import { avSession } from '@kit.AVSessionKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { NowPlayingSnapshot, NowPlayingStore } from './NowPlayingStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('SystemMediaSession')
const SESSION_TAG = 'VideoPlayer'
const DEFAULT_SKIP_MS = 10000

/**
 * Bridges the app-wide playback store to HarmonyOS system media controls.
 * The AVSession is kept at ability scope so it remains available while the
 * player page is covered by the home screen or another application.
 */
export class SystemMediaSession {
  private static instance: SystemMediaSession | null = null
  private readonly nowPlayingStore: NowPlayingStore = NowPlayingStore.getInstance()
  private session: avSession.AVSession | null = null
  private subscriptionId: number = -1
  private initializeTask: Promise<void> | null = null
  private syncTail: Promise<void> = Promise.resolve()
  private abilityContext: common.UIAbilityContext | null = null
  private backgroundTaskActive: boolean = false
  private backgroundTaskCancelHandler: ((info: backgroundTaskManager.ContinuousTaskCancelInfo) => void) | null = null
  private destroyed: boolean = false

  static getInstance(): SystemMediaSession {
    if (SystemMediaSession.instance === null) {
      SystemMediaSession.instance = new SystemMediaSession()
    }
    return SystemMediaSession.instance
  }

  initialize(context: common.UIAbilityContext): void {
    if (this.destroyed || this.initializeTask !== null || this.session !== null) {
      return
    }
    this.abilityContext = context
    this.registerBackgroundTaskCancellation()
    this.initializeTask = this.createSession(context).catch((err: Error) => {
      logger.warn('Initialize AVSession failed: %{public}s', err.message)
    }).finally(() => {
      this.initializeTask = null
    })
  }

  async destroy(): Promise<void> {
    this.destroyed = true
    await this.syncTail.catch(() => undefined)
    await this.syncBackgroundTask(false)
    if (this.subscriptionId >= 0) {
      this.nowPlayingStore.unsubscribe(this.subscriptionId)
      this.subscriptionId = -1
    }
    if (this.backgroundTaskCancelHandler !== null) {
      try {
        backgroundTaskManager.off('continuousTaskCancel', this.backgroundTaskCancelHandler)
      } catch (err) {
        logger.debug('Unregister audio task cancellation listener failed: %{public}s', String(err))
      }
      this.backgroundTaskCancelHandler = null
    }
    const current = this.session
    this.session = null
    if (current !== null) {
      try {
        current.off('play')
        current.off('pause')
        current.off('stop')
        current.off('playNext')
        current.off('playPrevious')
        current.off('fastForward')
        current.off('rewind')
        current.off('seek')
        await current.destroy()
      } catch (err) {
        logger.warn('Destroy AVSession failed: %{public}s', String(err))
      }
    }
  }

  private async createSession(context: common.UIAbilityContext): Promise<void> {
    const session = await avSession.createAVSession(context, SESSION_TAG, 'video')
    if (this.destroyed) {
      await session.destroy()
      return
    }
    this.session = session
    this.registerControls(session)
    this.subscriptionId = this.nowPlayingStore.subscribe((snapshot: NowPlayingSnapshot) => {
      void this.syncSnapshot(snapshot)
    })
    try {
      await session.activate()
      await this.syncSnapshot(this.nowPlayingStore.getSnapshot())
    } catch (err) {
      if (this.subscriptionId >= 0) {
        this.nowPlayingStore.unsubscribe(this.subscriptionId)
        this.subscriptionId = -1
      }
      if (this.session === session) {
        this.session = null
      }
      try {
        await session.destroy()
      } catch (destroyErr) {
        logger.debug('Rollback AVSession failed: %{public}s', String(destroyErr))
      }
      throw new Error(err instanceof Error ? err.message : String(err))
    }
  }

  private registerBackgroundTaskCancellation(): void {
    if (this.backgroundTaskCancelHandler !== null) {
      return
    }
    const handler = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      this.backgroundTaskActive = false
      logger.warn('Audio playback task cancelled: %{public}s', String(info.reason))
      if (this.nowPlayingStore.getSnapshot().playing) {
        this.nowPlayingStore.requestPause()
      }
    }
    try {
      backgroundTaskManager.on('continuousTaskCancel', handler)
      this.backgroundTaskCancelHandler = handler
    } catch (err) {
      logger.debug('Register audio task cancellation listener failed: %{public}s', String(err))
    }
  }

  private registerControls(session: avSession.AVSession): void {
    session.on('play', () => this.nowPlayingStore.requestPlay())
    session.on('pause', () => this.nowPlayingStore.requestPause())
    session.on('stop', () => this.nowPlayingStore.requestPause())
    session.on('playNext', () => this.nowPlayingStore.requestNext())
    session.on('playPrevious', () => this.nowPlayingStore.requestPrevious())
    session.on('seek', (position: number) => {
      this.nowPlayingStore.requestSeek(Math.max(0, position))
    })
    session.on('fastForward', (time?: number) => {
      const snapshot = this.nowPlayingStore.getSnapshot()
      const delta = time !== undefined && time > 0 ? time : DEFAULT_SKIP_MS
      const target = snapshot.durationMs > 0 ? Math.min(snapshot.durationMs, snapshot.positionMs + delta) : snapshot.positionMs + delta
      this.nowPlayingStore.requestFastForward(target)
    })
    session.on('rewind', (time?: number) => {
      const snapshot = this.nowPlayingStore.getSnapshot()
      const delta = time !== undefined && time > 0 ? time : DEFAULT_SKIP_MS
      this.nowPlayingStore.requestRewind(Math.max(0, snapshot.positionMs - delta))
    })
  }

  private syncSnapshot(snapshot: NowPlayingSnapshot): Promise<void> {
    // AVSession setters are asynchronous. Serialize them so a delayed
    // position update cannot overwrite a newer media or playback state.
    this.syncTail = this.syncTail.catch(() => undefined).then(() => this.applySnapshot(snapshot))
    return this.syncTail
  }

  private async applySnapshot(snapshot: NowPlayingSnapshot): Promise<void> {
    const session = this.session
    if (session === null || this.destroyed) {
      return
    }
    const assetId = snapshot.url.length > 0 ? snapshot.url : 'video-player'
    const metadata: avSession.AVMetadata = {
      assetId: assetId,
      title: snapshot.title.length > 0 ? snapshot.title : '视频',
      subtitle: snapshot.subtitle,
      duration: Math.max(0, snapshot.durationMs),
      mediaImage: snapshot.cover.length > 0 ? snapshot.cover : undefined,
      skipIntervals: avSession.SkipIntervals.SECONDS_10
    }
    if (snapshot.hasPrevious) {
      metadata.previousAssetId = 'previous'
    }
    if (snapshot.hasNext) {
      metadata.nextAssetId = 'next'
    }
    try {
      await session.setAVMetadata(metadata)
      const playbackState: avSession.AVPlaybackState = {
        state: snapshot.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: Math.max(0, snapshot.positionMs),
          updateTime: Date.now()
        },
        speed: snapshot.speed > 0 ? snapshot.speed : 1,
        duration: Math.max(0, snapshot.durationMs),
        videoWidth: Math.max(0, snapshot.videoWidth),
        videoHeight: Math.max(0, snapshot.videoHeight)
      }
      await session.setAVPlaybackState(playbackState)
      await this.syncBackgroundTask(snapshot.playing && snapshot.url.length > 0)
    } catch (err) {
      logger.debug('Sync AVSession snapshot failed: %{public}s', String(err))
    }
  }

  private async syncBackgroundTask(shouldRun: boolean): Promise<void> {
    const context = this.abilityContext
    if (context === null || shouldRun === this.backgroundTaskActive) {
      return
    }
    if (!shouldRun) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(context)
      } catch (err) {
        logger.debug('Stop audio playback task failed: %{public}s', String(err))
      }
      this.backgroundTaskActive = false
      return
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'com.yingxia.hmos', abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      const agent = await wantAgent.getWantAgent(info)
      await backgroundTaskManager.startBackgroundRunning(context, ['audioPlayback'], agent)
      this.backgroundTaskActive = true
    } catch (err) {
      logger.warn('Start audio playback task failed: %{public}s', String(err))
    }
  }
}
