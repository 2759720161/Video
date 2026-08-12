import { StreamMetadata } from './StreamMetadata'

export enum VideoAspectMode {
  contain = 0,
  cover = 1,
  fill = 2
}

export namespace VideoAspectModeHelper {
  export function getLabel(mode: VideoAspectMode): string {
    switch (mode) {
      case VideoAspectMode.contain: return '自动适应'
      case VideoAspectMode.cover: return '裁切填充'
      case VideoAspectMode.fill: return '拉伸填充'
      default: return '自动适应'
    }
  }

  export function fromValue(value: number): VideoAspectMode {
    if (value >= VideoAspectMode.contain && value <= VideoAspectMode.fill) {
      return value as VideoAspectMode
    }
    return VideoAspectMode.contain
  }
}

export interface IPlayerEngine {
  setSurfaceId(surfaceId: string): void
  prepare(options: PlaybackOptions): void
  play(): void
  pause(): void
  stop(): void
  seek(positionMs: number): void
  setSpeed(speed: number): void
  setVolume(volume: number): void
  setAspectMode(mode: VideoAspectMode): void
  getVideoInfo(): Promise<VideoMediaInfo>
  getTracks(): Promise<PlayerTrack[]>
  selectTrack(index: number): Promise<void>
  setSecondarySubtitle(index: number): Promise<void>
  setSubtitleDelay(offsetMs: number): Promise<void>
  deselectTrack(index: number): Promise<void>
  addExternalSubtitle(uri: string, displayName?: string): Promise<void>
  onExternalSubtitleChange(callback: (text: string) => void): void
  getState(): PlayerState
  onStateChange(callback: (state: PlayerState) => void): void
  release(): void
}

export class PlaybackOptions {
  url: string = ''
  headers: Record<string, string> = {}
  startPositionMs: number = 0
  referer: string = ''
  userAgent: string = ''
  proxy: string = ''
  streamMetadata: StreamMetadata | null = null
  isLocalFile: boolean = false
  localFileSize: number = 0
}

export class PlayerState {
  playing: boolean = false
  buffering: boolean = false
  positionMs: number = 0
  durationMs: number = 0
  bufferMs: number = 0
  volume: number = 1.0
  speed: number = 1.0
  completed: boolean = false
  error: string = ''
  stateName: string = 'idle'
  videoWidth: number = 0
  videoHeight: number = 0
}

export class VideoMediaInfo {
  codec: string = ''
  frameRate: number = 0
  bitrate: number = 0
  decoder: string = ''
  dynamicRange: string = ''
}

export enum PlayerTrackType {
  audio = 'audio',
  subtitle = 'subtitle',
  video = 'video'
}

export class PlayerTrack {
  index: number = -1
  type: PlayerTrackType = PlayerTrackType.audio
  name: string = ''
  language: string = ''
  codec: string = ''
  channelCount: number = 0
  sampleRate: number = 0
  selected: boolean = false
}
