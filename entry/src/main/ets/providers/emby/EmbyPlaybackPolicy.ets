import { EmbyMediaSource } from './EmbyPlaybackInfo'
import { PreferencesStore } from '../../store/PreferencesStore'

export enum EmbyPlaybackMode {
  AUTO = 'auto',
  DIRECT = 'direct',
  TRANSCODE = 'transcode'
}

export const PREFS_KEY_EMBY_PLAYBACK_MODE: string = 'embyPlaybackMode'
export const EMBY_PLAYBACK_MODE_DEFAULT: EmbyPlaybackMode = EmbyPlaybackMode.AUTO

/** 根据用户模式和服务端能力选择最合适的 PlaybackInfo 媒体源。 */
export class EmbyPlaybackPolicy {
  static normalizeMode(value: string): EmbyPlaybackMode {
    switch (value.trim().toLowerCase()) {
      case EmbyPlaybackMode.DIRECT: return EmbyPlaybackMode.DIRECT
      case EmbyPlaybackMode.TRANSCODE: return EmbyPlaybackMode.TRANSCODE
      default: return EmbyPlaybackMode.AUTO
    }
  }

  static async loadMode(): Promise<EmbyPlaybackMode> {
    const stored = await PreferencesStore.getInstance().getString(PREFS_KEY_EMBY_PLAYBACK_MODE,
      EMBY_PLAYBACK_MODE_DEFAULT)
    return EmbyPlaybackPolicy.normalizeMode(stored)
  }

  static selectSource(sources: EmbyMediaSource[], mode: EmbyPlaybackMode = EmbyPlaybackMode.AUTO): EmbyMediaSource {
    if (sources.length === 0) throw new Error('Emby 未返回可播放的媒体源')
    if (mode !== EmbyPlaybackMode.TRANSCODE) {
      for (let i = 0; i < sources.length; i++) {
        if (sources[i].directPlayUrl.length > 0 || sources[i].directStreamUrl.length > 0 ||
          sources[i].supportsDirectPlay || sources[i].supportsDirectStream) {
          return sources[i]
        }
      }
    }
    if (mode !== EmbyPlaybackMode.DIRECT) {
      for (let i = 0; i < sources.length; i++) {
        if (sources[i].transcodingUrl.length > 0 || sources[i].supportsTranscoding) return sources[i]
      }
    }
    return sources[0]
  }
}
