import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import { IPlayerEngine, PlaybackOptions, PlayerState, PlayerTrack, PlayerTrackType, VideoAspectMode, VideoMediaInfo } from './IPlayerEngine'
import { Logger } from '../../utils/Logger'

const logger = new Logger('AVPlayerEngine')
const INITIAL_SEEK_REGRESSION_TOLERANCE_MS: number = 1200
const INITIAL_SEEK_GUARD_WINDOW_MS: number = 5000
const INITIAL_SEEK_CORRECTION_INTERVAL_MS: number = 600
const INITIAL_SEEK_MAX_CORRECTIONS: number = 2

export class AVPlayerEngine implements IPlayerEngine {
  private avPlayer: media.AVPlayer | null = null
  private state: PlayerState = new PlayerState()
  private stateCallback: ((state: PlayerState) => void) | null = null
  private externalSubtitleCallback: ((text: string) => void) | null = null
  private surfaceId: string = ''
  private currentOptions: PlaybackOptions | null = null
  private prepareTimeoutTimer: number = -1
  private readonly prepareTimeoutMs: number = 12000
  private pendingAspectMode: VideoAspectMode | null = null
  private pendingInitialPlayAfterSeek: boolean = false
  private pendingInitialSeekMs: number = -1
  private initialSeekGuardTargetMs: number = -1
  private initialSeekGuardUntilMs: number = 0
  private initialSeekCorrectionCount: number = 0
  private lastInitialSeekCorrectionAtMs: number = 0
  private initialSeekFallbackTimer: number = -1
  private progressPollingTimer: number = -1
  private localSourceFile: fileIo.File | null = null
  /** Kept open while AVPlayer reads an externally selected subtitle. */
  private externalSubtitleFile: fileIo.File | null = null
  private isLoadingExternalSubtitle: boolean = false
  private externalSubtitleError: string = ''
  private prepareGeneration: number = 0

  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId
    if (this.avPlayer !== null && surfaceId.length > 0) {
      try {
        this.avPlayer.surfaceId = surfaceId
        logger.info('AVPlayer surface rebound: %{public}s', surfaceId)
      } catch (_err) {
        logger.warn('AVPlayer surface rebind failed')
      }
    }
  }

  prepare(options: PlaybackOptions): void {
    const generation = ++this.prepareGeneration
    this.clearPrepareTimeout()
    this.clearInitialSeekState()
    this.clearInitialSeekGuard()
    this.closeExternalSubtitleFile()
    this.closeLocalSourceFile()
    this.releaseActivePlayer()
    this.resetState()
    this.currentOptions = options
    this.state.stateName = 'creating'
    this.notifyStateChange()

    this.logStreamMetadata(options)
    this.prepareWithUrl(options, generation)
  }

  private prepareWithUrl(options: PlaybackOptions, generation: number): void {
    media.createAVPlayer().then(async (player: media.AVPlayer) => {
      if (generation !== this.prepareGeneration || this.currentOptions !== options) {
        logger.info('AVPlayer create result ignored because playback target is stale')
        try {
          player.release()
        } catch (_err) {
        }
        return
      }
      this.avPlayer = player
      this.registerListeners()
      if (options.url.length > 0) {
        try {
          if (options.isLocalFile) {
            const file = fileIo.openSync(options.url, fileIo.OpenMode.READ_ONLY)
            const length = options.localFileSize > 0 ? options.localFileSize : fileIo.statSync(file.fd).size
            player.fdSrc = {
              fd: file.fd,
              offset: 0,
              length: length
            }
            this.localSourceFile = file
            logger.info('Set AVPlayer fdSrc for local file: fd=%{public}d, length=%{public}d', file.fd, length)
          } else {
            const requestHeaders = this.buildMediaSourceHeaders(options)
            if (Object.keys(requestHeaders).length > 0) {
              const source = media.createMediaSourceWithUrl(options.url, requestHeaders)
              await player.setMediaSource(source)
              logger.info('AVPlayer media source configured with headers: count=%{public}d',
                Object.keys(requestHeaders).length)
            } else {
              player.url = options.url
              logger.info('AVPlayer direct URL source configured')
            }
          }
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err)
          logger.error('Set AVPlayer source failed: %{public}s', msg)
          this.failPlayback('AVPlayer set source failed: ' + msg)
        }
      }
    }).catch((err: Error) => {
      if (generation !== this.prepareGeneration) {
        return
      }
      this.failPlayback('Create AVPlayer failed: ' + err.message)
    })
  }

  private buildMediaSourceHeaders(options: PlaybackOptions): Record<string, string> {
    const headers: Record<string, string> = {}
    const sourceKeys = Object.keys(options.headers)
    for (let i = 0; i < sourceKeys.length; i++) {
      const key = sourceKeys[i]
      const normalizedKey = this.normalizeMediaHeaderName(key)
      const value = options.headers[key]
      if (normalizedKey.length > 0 && value !== undefined && value.trim().length > 0) {
        headers[normalizedKey] = value.trim()
      }
    }
    if (options.referer.length > 0 && headers['Referer'] === undefined) {
      headers['Referer'] = options.referer
    }
    if (options.userAgent.length > 0 && headers['User-Agent'] === undefined) {
      headers['User-Agent'] = options.userAgent
    }
    return headers
  }

  private normalizeMediaHeaderName(key: string): string {
    switch (key.trim().toLowerCase()) {
      case 'cookie':
        return 'Cookie'
      case 'referer':
      case 'referrer':
        return 'Referer'
      case 'user-agent':
        return 'User-Agent'
      case 'origin':
        return 'Origin'
      case 'accept':
        return 'Accept'
      case 'accept-language':
        return 'Accept-Language'
      default:
        return ''
    }
  }

  private logStreamMetadata(options: PlaybackOptions): void {
    if (options.streamMetadata === null || options.streamMetadata.isEmpty()) {
      return
    }
    logger.info('AVPlayer stream metadata: %{public}s', options.streamMetadata.summary())
    if (options.streamMetadata.hasDolbyVision || options.streamMetadata.hasHdrCodecHint) {
      logger.warn('AVPlayer stream has HDR/Dolby codec hints; playback depends on device decoder/display')
    }
  }

  private registerListeners(): void {
    if (!this.avPlayer) {
      return
    }

    this.avPlayer.on('stateChange', (avState: string) => {
      this.state.stateName = avState
      switch (avState) {
        case 'idle':
          this.state.playing = false
          this.state.buffering = false
          break
        case 'initialized':
          if (this.avPlayer && this.surfaceId) {
            this.avPlayer.surfaceId = this.surfaceId
          }
          if (this.avPlayer) {
            this.startPrepareTimeout()
            this.avPlayer.prepare().catch((err: Error) => {
              this.clearPrepareTimeout()
              const msg = err instanceof Error ? err.message : String(err)
              logger.error('AVPlayer prepare promise failed: %{public}s', msg)
              this.failPlayback('AVPlayer prepare failed: ' + msg)
            })
          }
          break
        case 'prepared':
          this.clearPrepareTimeout()
          this.state.playing = false
          this.state.buffering = false
          if (this.avPlayer) {
            this.state.durationMs = this.avPlayer.duration
            const w = this.avPlayer.width
            const h = this.avPlayer.height
            if (w > 0 && h > 0) {
              this.state.videoWidth = w
              this.state.videoHeight = h
              logger.info('AVPlayer video size: %{public}dx%{public}d', w, h)
            }
          }
          if (this.avPlayer && this.currentOptions !== null && this.currentOptions.startPositionMs > 0) {
            const startPos = this.currentOptions.startPositionMs
            this.seekBeforeInitialPlay(startPos)
          } else if (this.avPlayer) {
            this.avPlayer.play()
          }
          if (this.pendingAspectMode !== null) {
            this.setAspectMode(this.pendingAspectMode)
          }
          break
        case 'playing':
          this.state.playing = true
          this.state.buffering = false
          this.startProgressPolling()
          break
        case 'paused':
          this.state.playing = false
          this.stopProgressPolling()
          break
        case 'completed':
          this.state.playing = false
          this.state.completed = true
          this.stopProgressPolling()
          break
        case 'stopped':
          this.state.playing = false
          this.stopProgressPolling()
          break
        case 'released':
          this.clearPrepareTimeout()
          this.clearInitialSeekState()
          this.clearInitialSeekGuard()
          this.state.playing = false
          this.stopProgressPolling()
          break
        case 'error':
          this.clearPrepareTimeout()
          this.clearInitialSeekState()
          this.clearInitialSeekGuard()
          this.state.playing = false
          this.stopProgressPolling()
          this.state.error = 'Player error'
          break
        default:
          break
      }
      this.notifyStateChange()
    })

    this.avPlayer.on('timeUpdate', (time: number) => {
      if (this.shouldRejectInitialSeekRegression(time, 'timeUpdate')) {
        return
      }
      this.state.positionMs = time
      this.notifyStateChange()
    })

    this.avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.state.buffering = true
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.state.buffering = false
      } else if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
        if (value >= 0) {
          this.state.bufferMs = Math.floor(this.state.durationMs * value / 100)
        }
      } else if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        this.state.bufferMs = value
      }
      this.notifyStateChange()
    })

    this.avPlayer.on('seekDone', (seekDoneTime: number) => {
      this.handleSeekDone(seekDoneTime)
    })

    this.avPlayer.on('subtitleUpdate', (info: media.SubtitleInfo) => {
      if (this.externalSubtitleCallback !== null) {
        this.externalSubtitleCallback(info.text ?? '')
      }
    })

    this.avPlayer.on('error', (err: Error) => {
      this.clearPrepareTimeout()
      this.clearInitialSeekState()
      this.clearInitialSeekGuard()
      const msg = err instanceof Error ? err.message : String(err)
      if (this.isLoadingExternalSubtitle) {
        this.externalSubtitleError = msg
        logger.warn('AVPlayer external subtitle rejected: %{public}s', msg)
        return
      }
      logger.error('AVPlayer error callback: %{public}s', msg)
      this.state.error = msg.length > 0 ? 'AVPlayer error: ' + msg : 'AVPlayer error (check URL format and network)'
      this.state.stateName = 'error'
      this.notifyStateChange()
    })
  }

  private seekBeforeInitialPlay(positionMs: number): void {
    if (!this.avPlayer) {
      return
    }
    try {
      logger.info('AVPlayer initial seek before play: %{public}dms', positionMs)
      this.pendingInitialPlayAfterSeek = true
      this.pendingInitialSeekMs = positionMs
      this.startInitialSeekGuard(positionMs)
      this.avPlayer.seek(positionMs, media.SeekMode.SEEK_CLOSEST)
      this.startInitialSeekFallbackTimer()
    } catch (err) {
      logger.warn('AVPlayer initial seek threw, fallback to direct play: %{public}s',
        err instanceof Error ? err.message : String(err))
      this.clearInitialSeekState()
      if (this.avPlayer) {
        this.avPlayer.play()
      }
    }
  }

  private handleSeekDone(seekDoneTime: number): void {
    if (seekDoneTime >= 0) {
      this.state.positionMs = seekDoneTime
      if (this.pendingInitialPlayAfterSeek && this.pendingInitialSeekMs > 0) {
        this.startInitialSeekGuard(this.pendingInitialSeekMs)
      }
      this.notifyStateChange()
    }
    if (!this.pendingInitialPlayAfterSeek) {
      return
    }
    logger.info('AVPlayer initial seek done: %{public}dms', seekDoneTime)
    this.playAfterInitialSeek()
  }

  private playAfterInitialSeek(): void {
    this.clearInitialSeekState()
    if (!this.avPlayer || this.state.stateName === 'released' || this.state.stateName === 'error') {
      return
    }
    this.avPlayer.play()
  }

  play(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.play()
        this.state.playing = true
        this.state.stateName = 'playing'
        this.startProgressPolling()
        this.notifyStateChange()
      } catch (e) {
        this.state.error = 'play error'
        this.notifyStateChange()
      }
    }
  }

  pause(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.pause()
        this.state.playing = false
        this.state.stateName = 'paused'
        this.stopProgressPolling()
        this.notifyStateChange()
      } catch (e) {
        this.state.error = 'pause error'
        this.notifyStateChange()
      }
    }
  }

  stop(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.stop()
      } catch (e) {
        this.state.error = 'stop error'
      }
    }
  }

  seek(positionMs: number): void {
    if (this.avPlayer) {
      this.clearInitialSeekGuard()
      this.state.positionMs = positionMs
      this.notifyStateChange()
      this.avPlayer.seek(positionMs, media.SeekMode.SEEK_CLOSEST)
    }
  }

  setSpeed(speed: number): void {
    if (this.avPlayer) {
      let playbackSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
      let normalizedSpeed = 1.0
      if (speed <= 0.25) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_25_X
        normalizedSpeed = 0.25
      } else if (speed <= 0.5) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_50_X
        normalizedSpeed = 0.5
      } else if (speed <= 0.75) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
        normalizedSpeed = 0.75
      } else if (speed <= 1.0) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
        normalizedSpeed = 1.0
      } else if (speed <= 1.25) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
        normalizedSpeed = 1.25
      } else if (speed <= 1.75) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
        normalizedSpeed = 1.75
      } else {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
        normalizedSpeed = 2.0
      }
      this.avPlayer.setSpeed(playbackSpeed)
      this.state.speed = normalizedSpeed
      this.notifyStateChange()
    }
  }

  setVolume(volume: number): void {
    if (this.avPlayer) {
      const normalizedVolume = Math.max(0, Math.min(1, volume))
      this.avPlayer.setVolume(normalizedVolume)
      this.state.volume = normalizedVolume
      this.notifyStateChange()
    }
  }

  setAspectMode(mode: VideoAspectMode): void {
    this.pendingAspectMode = mode
    if (this.avPlayer !== null) {
      try {
        const modeName = this.getAspectModeName(mode)
        const scaleType = this.getVideoScaleType(mode)
        this.avPlayer.videoScaleType = scaleType
        this.pendingAspectMode = null
        logger.info('AVPlayer setAspectMode ok: mode=%{public}s, params=videoScaleType=%{public}d',
          modeName, scaleType)
      } catch (err) {
        logger.warn('AVPlayer setAspectMode failed: %{public}s', String(err))
      }
    }
  }

  async getVideoInfo(): Promise<VideoMediaInfo> {
    const info = new VideoMediaInfo()
    const tracks = await this.getTracks()
    for (let i = 0; i < tracks.length; i++) {
      if (tracks[i].type === PlayerTrackType.video) {
        info.codec = tracks[i].codec
        break
      }
    }
    return info
  }

  async getTracks(): Promise<PlayerTrack[]> {
    if (this.avPlayer === null) {
      return []
    }
    try {
      const descriptions = await this.avPlayer.getTrackDescription()
      const selectedTracks = await this.avPlayer.getSelectedTracks()
      const tracks: PlayerTrack[] = []
      for (let i = 0; i < descriptions.length; i++) {
        const description = descriptions[i]
        const type = this.resolveTrackType(this.readNumber(description, media.MediaDescriptionKey.MD_KEY_TRACK_TYPE))
        if (type === null) {
          continue
        }
        const track = new PlayerTrack()
        track.index = this.readNumber(description, media.MediaDescriptionKey.MD_KEY_TRACK_INDEX)
        track.type = type
        track.name = this.readString(description, media.MediaDescriptionKey.MD_KEY_TRACK_NAME)
        track.language = this.readString(description, media.MediaDescriptionKey.MD_KEY_LANGUAGE)
        track.codec = this.readString(description, media.MediaDescriptionKey.MD_KEY_CODEC_MIME)
        track.channelCount = this.readNumber(description, media.MediaDescriptionKey.MD_KEY_AUD_CHANNEL_COUNT)
        track.sampleRate = this.readNumber(description, media.MediaDescriptionKey.MD_KEY_AUD_SAMPLE_RATE)
        track.selected = selectedTracks.indexOf(track.index) >= 0
        tracks.push(track)
      }
      return tracks
    } catch (err) {
      logger.warn('AVPlayer read tracks failed: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  async selectTrack(index: number): Promise<void> {
    if (this.avPlayer !== null && index >= 0) {
      await this.avPlayer.selectTrack(index)
    }
  }

  async setSecondarySubtitle(_index: number): Promise<void> {
    throw new Error('当前播放内核不支持副字幕')
  }

  async setSubtitleDelay(_offsetMs: number): Promise<void> {
    // ArkUI fallback subtitles apply the delay in LocalPlayerPage's clock.
  }

  async deselectTrack(index: number): Promise<void> {
    if (this.avPlayer !== null && index >= 0) {
      await this.avPlayer.deselectTrack(index)
    }
  }

  async addExternalSubtitle(uri: string, _displayName?: string): Promise<void> {
    if (this.avPlayer === null || uri.length === 0) {
      throw new Error('播放器尚未就绪')
    }
    this.closeExternalSubtitleFile()
    this.externalSubtitleError = ''
    this.isLoadingExternalSubtitle = true
    let subtitleFile: fileIo.File | null = null
    try {
      subtitleFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const subtitleFd = subtitleFile.fd
      const length = fileIo.statSync(subtitleFd).size
      await this.avPlayer.addSubtitleFromFd(subtitleFd, 0, length)
      if (this.externalSubtitleError.length > 0) {
        throw new Error(this.externalSubtitleError)
      }
      this.externalSubtitleFile = subtitleFile
      subtitleFile = null
      logger.info('AVPlayer external subtitle configured from fd: %{public}d', subtitleFd)
    } catch (err) {
      throw new Error('AVPlayer 加载外挂字幕失败: ' + (err instanceof Error ? err.message : String(err)))
    } finally {
      this.isLoadingExternalSubtitle = false
      if (subtitleFile !== null) {
        try {
          fileIo.closeSync(subtitleFile)
        } catch (_err) {
          logger.warn('Close rejected external subtitle file failed')
        }
      }
    }
  }

  onExternalSubtitleChange(callback: (text: string) => void): void {
    this.externalSubtitleCallback = callback
  }

  private resolveTrackType(value: number): PlayerTrackType | null {
    if (value === media.MediaType.MEDIA_TYPE_AUD) return PlayerTrackType.audio
    if (value === media.MediaType.MEDIA_TYPE_SUBTITLE) return PlayerTrackType.subtitle
    if (value === media.MediaType.MEDIA_TYPE_VID) return PlayerTrackType.video
    return null
  }

  private readNumber(description: media.MediaDescription, key: media.MediaDescriptionKey): number {
    const value = description[key]
    return typeof value === 'number' ? value : 0
  }

  private readString(description: media.MediaDescription, key: media.MediaDescriptionKey): string {
    const value = description[key]
    return typeof value === 'string' ? value : ''
  }

  private getVideoScaleType(mode: VideoAspectMode): media.VideoScaleType {
    switch (mode) {
      case VideoAspectMode.contain:
        return media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT
      case VideoAspectMode.cover:
        return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP
      case VideoAspectMode.fill:
      default:
        return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT
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

  getState(): PlayerState {
    return this.state
  }

  onStateChange(callback: (state: PlayerState) => void): void {
    this.stateCallback = callback
  }

  release(): void {
    this.prepareGeneration++
    this.clearPrepareTimeout()
    this.clearInitialSeekState()
    this.stopProgressPolling()
    this.releaseActivePlayer()
    this.closeExternalSubtitleFile()
    this.closeLocalSourceFile()
    this.currentOptions = null
    this.resetState()
  }

  private releaseActivePlayer(): void {
    if (this.avPlayer !== null) {
      try {
        this.avPlayer.release()
      } catch (_err) {
        logger.warn('AVPlayer release failed')
      }
      this.avPlayer = null
    }
  }

  private startPrepareTimeout(): void {
    this.clearPrepareTimeout()
    this.prepareTimeoutTimer = setTimeout(() => {
      this.prepareTimeoutTimer = -1
      if (this.state.stateName === 'initialized' || this.state.stateName === 'creating') {
        const url = this.currentOptions !== null ? this.currentOptions.url.substring(0, 80) : ''
        logger.error('AVPlayer prepare timeout after %{public}dms: %{public}s',
          this.prepareTimeoutMs, url)
        this.failPlayback('AVPlayer prepare timeout')
      }
    }, this.prepareTimeoutMs)
  }

  private clearPrepareTimeout(): void {
    if (this.prepareTimeoutTimer >= 0) {
      clearTimeout(this.prepareTimeoutTimer)
      this.prepareTimeoutTimer = -1
    }
  }

  private startInitialSeekFallbackTimer(): void {
    this.clearInitialSeekFallbackTimer()
    this.initialSeekFallbackTimer = setTimeout(() => {
      this.initialSeekFallbackTimer = -1
      if (!this.pendingInitialPlayAfterSeek) {
        return
      }
      logger.warn('AVPlayer initial seek timeout, fallback to play: %{public}dms', this.pendingInitialSeekMs)
      this.playAfterInitialSeek()
    }, 1600)
  }

  private clearInitialSeekFallbackTimer(): void {
    if (this.initialSeekFallbackTimer >= 0) {
      clearTimeout(this.initialSeekFallbackTimer)
      this.initialSeekFallbackTimer = -1
    }
  }

  private clearInitialSeekState(): void {
    this.clearInitialSeekFallbackTimer()
    this.pendingInitialPlayAfterSeek = false
    this.pendingInitialSeekMs = -1
  }

  private startInitialSeekGuard(positionMs: number): void {
    if (positionMs <= 0) {
      return
    }
    this.initialSeekGuardTargetMs = positionMs
    this.initialSeekGuardUntilMs = Date.now() + INITIAL_SEEK_GUARD_WINDOW_MS
    this.initialSeekCorrectionCount = 0
    this.lastInitialSeekCorrectionAtMs = 0
  }

  private clearInitialSeekGuard(): void {
    this.initialSeekGuardTargetMs = -1
    this.initialSeekGuardUntilMs = 0
    this.initialSeekCorrectionCount = 0
    this.lastInitialSeekCorrectionAtMs = 0
  }

  private shouldRejectInitialSeekRegression(positionMs: number, source: string): boolean {
    if (this.initialSeekGuardTargetMs <= 0) {
      return false
    }
    const now = Date.now()
    if (now > this.initialSeekGuardUntilMs) {
      this.clearInitialSeekGuard()
      return false
    }
    if (positionMs >= this.initialSeekGuardTargetMs - INITIAL_SEEK_REGRESSION_TOLERANCE_MS) {
      return false
    }
    logger.warn('AVPlayer initial seek regression ignored: source=%{public}s pos=%{public}d target=%{public}d',
      source, positionMs, this.initialSeekGuardTargetMs)
    this.correctInitialSeekRegression(now)
    return true
  }

  private correctInitialSeekRegression(now: number): void {
    if (!this.avPlayer || this.initialSeekCorrectionCount >= INITIAL_SEEK_MAX_CORRECTIONS) {
      return
    }
    if (now - this.lastInitialSeekCorrectionAtMs < INITIAL_SEEK_CORRECTION_INTERVAL_MS) {
      return
    }
    this.initialSeekCorrectionCount++
    this.lastInitialSeekCorrectionAtMs = now
    try {
      logger.warn('AVPlayer initial seek correction: count=%{public}d target=%{public}d',
        this.initialSeekCorrectionCount, this.initialSeekGuardTargetMs)
      this.avPlayer.seek(this.initialSeekGuardTargetMs, media.SeekMode.SEEK_CLOSEST)
    } catch (err) {
      logger.warn('AVPlayer initial seek correction failed: %{public}s',
        err instanceof Error ? err.message : String(err))
    }
  }

  private startProgressPolling(): void {
    if (this.progressPollingTimer >= 0) {
      return
    }
    this.progressPollingTimer = setInterval(() => {
      this.pollPlayerProgress()
    }, 1000)
  }

  private stopProgressPolling(): void {
    if (this.progressPollingTimer >= 0) {
      clearInterval(this.progressPollingTimer)
      this.progressPollingTimer = -1
    }
  }

  private pollPlayerProgress(): void {
    if (this.avPlayer === null) {
      this.stopProgressPolling()
      return
    }
    try {
      const currentTime = this.avPlayer.currentTime
      const duration = this.avPlayer.duration
      let changed = false
      if (currentTime >= 0 && currentTime !== this.state.positionMs) {
        if (this.shouldRejectInitialSeekRegression(currentTime, 'poll')) {
          return
        }
        this.state.positionMs = currentTime
        changed = true
      }
      if (duration > 0 && duration !== this.state.durationMs) {
        this.state.durationMs = duration
        changed = true
      }
      if (changed) {
        this.notifyStateChange()
      }
    } catch (_err) {
      logger.warn('AVPlayer progress polling failed')
    }
  }

  private failPlayback(message: string): void {
    this.clearPrepareTimeout()
    this.clearInitialSeekState()
    this.clearInitialSeekGuard()
    this.stopProgressPolling()
    this.state.error = message
    this.state.stateName = 'error'
    this.state.playing = false
    this.notifyStateChange()
    if (this.avPlayer) {
      try {
        this.avPlayer.release()
      } catch (e) {
      }
      this.avPlayer = null
    }
    this.closeLocalSourceFile()
    this.closeExternalSubtitleFile()
  }

  private resetState(): void {
    this.state = new PlayerState()
  }

  private closeLocalSourceFile(): void {
    if (this.localSourceFile === null) {
      return
    }
    try {
      fileIo.closeSync(this.localSourceFile)
    } catch (_err) {
      logger.warn('Close local source file failed')
    }
    this.localSourceFile = null
  }

  private closeExternalSubtitleFile(): void {
    if (this.externalSubtitleFile === null) {
      return
    }
    try {
      fileIo.closeSync(this.externalSubtitleFile)
    } catch (_err) {
      logger.warn('Close external subtitle file failed')
    }
    this.externalSubtitleFile = null
  }

  private notifyStateChange(): void {
    if (this.stateCallback) {
      this.stateCallback(this.state)
    }
  }
}
