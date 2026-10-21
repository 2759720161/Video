/** Index 是容器流编号，不能直接作为播放内核的轨道编号。 */
export class EmbyMediaTrack {
  index: number = -1
  type: string = ''
  language: string = ''
  title: string = ''
  codec: string = ''
  channels: number = 0
  isExternal: boolean = false
  isDefault: boolean = false

  label(): string {
    const languages: Record<string, string> = {
      'zh': '中文', 'zho': '中文', 'chi': '中文', 'cmn': '普通话', 'yue': '粤语',
      'en': '英语', 'eng': '英语', 'ja': '日语', 'jpn': '日语', 'ko': '韩语', 'kor': '韩语',
      'fr': '法语', 'fra': '法语', 'fre': '法语', 'de': '德语', 'deu': '德语', 'ger': '德语',
      'es': '西班牙语', 'spa': '西班牙语', 'ru': '俄语', 'rus': '俄语'
    }
    const language = this.language.toLowerCase().split('-')[0]
    return languages[language] || this.title || (language !== 'und' ? this.language : '') ||
      (this.type === 'Audio' ? '音轨 ' : '字幕 ') + String(this.index + 1)
  }

  detail(): string {
    return [this.codec.toUpperCase(), this.channels > 0 ? String(this.channels) + 'ch' : '',
      this.title.length > 0 && this.title !== this.label() ? this.title : ''].filter((s: string) => s.length > 0).join(' · ')
  }
}

/** Emby PlaybackInfo 中一个可选的媒体源。 */
export class EmbyMediaSource {
  id: string = ''
  name: string = ''
  container: string = ''
  bitrate: number = 0
  supportsDirectPlay: boolean = false
  supportsDirectStream: boolean = false
  supportsTranscoding: boolean = false
  directPlayUrl: string = ''
  directStreamUrl: string = ''
  transcodingUrl: string = ''
  requiredHttpHeaders: Record<string, string> = {}
  tracks: EmbyMediaTrack[] = []
  defaultAudioIndex: number = -1
  defaultSubtitleIndex: number = -1
}

/** 对 PlaybackInfo 响应进行一次结构化解析，Provider 不再直接依赖裸 JSON。 */
export class EmbyPlaybackInfo {
  playSessionId: string = ''
  mediaSources: EmbyMediaSource[] = []

  static parse(value: Record<string, Object>): EmbyPlaybackInfo {
    const result = new EmbyPlaybackInfo()
    result.playSessionId = EmbyPlaybackInfo.readString(value, 'PlaySessionId')
    const rawSources = value['MediaSources']
    if (!Array.isArray(rawSources)) return result
    for (let i = 0; i < rawSources.length; i++) {
      const raw = rawSources[i] as Object
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) continue
      const source = raw as Record<string, Object>
      const media = new EmbyMediaSource()
      media.id = EmbyPlaybackInfo.readString(source, 'Id')
      media.name = EmbyPlaybackInfo.readString(source, 'Name')
      media.container = EmbyPlaybackInfo.readString(source, 'Container')
      media.bitrate = EmbyPlaybackInfo.readNumber(source, 'Bitrate')
      media.supportsDirectPlay = EmbyPlaybackInfo.readBoolean(source, 'SupportsDirectPlay')
      media.supportsDirectStream = EmbyPlaybackInfo.readBoolean(source, 'SupportsDirectStream')
      media.supportsTranscoding = EmbyPlaybackInfo.readBoolean(source, 'SupportsTranscoding')
      media.directPlayUrl = EmbyPlaybackInfo.readString(source, 'DirectPlayUrl')
      media.directStreamUrl = EmbyPlaybackInfo.readString(source, 'DirectStreamUrl')
      media.transcodingUrl = EmbyPlaybackInfo.readString(source, 'TranscodingUrl')
      media.defaultAudioIndex = EmbyPlaybackInfo.readIndex(source, 'DefaultAudioStreamIndex')
      media.defaultSubtitleIndex = EmbyPlaybackInfo.readIndex(source, 'DefaultSubtitleStreamIndex')
      const streams = source['MediaStreams']
      if (Array.isArray(streams)) {
        for (let j = 0; j < streams.length; j++) {
          const rawStream = streams[j] as Object
          if (rawStream === null || typeof rawStream !== 'object' || Array.isArray(rawStream)) continue
          const stream = rawStream as Record<string, Object>
          const track = new EmbyMediaTrack()
          track.index = EmbyPlaybackInfo.readIndex(stream, 'Index')
          track.type = EmbyPlaybackInfo.readString(stream, 'Type')
          if (track.index < 0 || (track.type !== 'Audio' && track.type !== 'Subtitle')) continue
          track.language = EmbyPlaybackInfo.readString(stream, 'Language')
          track.title = EmbyPlaybackInfo.readString(stream, 'Title')
          track.codec = EmbyPlaybackInfo.readString(stream, 'Codec')
          track.channels = EmbyPlaybackInfo.readNumber(stream, 'Channels')
          track.isExternal = EmbyPlaybackInfo.readBoolean(stream, 'IsExternal')
          track.isDefault = EmbyPlaybackInfo.readBoolean(stream, 'IsDefault')
          media.tracks.push(track)
        }
      }
      media.tracks.sort((left: EmbyMediaTrack, right: EmbyMediaTrack) => left.index - right.index)
      const headers = source['RequiredHttpHeaders']
      if (headers !== null && typeof headers === 'object' && !Array.isArray(headers)) {
        const rawHeaders = headers as Record<string, Object>
        const keys = Object.keys(rawHeaders)
        for (let j = 0; j < keys.length; j++) {
          const key = keys[j]
          const header = rawHeaders[key]
          if (typeof header === 'string' && key.trim().length > 0) media.requiredHttpHeaders[key.trim()] = header.trim()
        }
      }
      result.mediaSources.push(media)
    }
    return result
  }

  private static readString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? (value[key] as string).trim() : ''
  }

  private static readIndex(value: Record<string, Object>, key: string): number {
    const candidate = value[key]
    return typeof candidate === 'number' && Number.isInteger(candidate) && candidate >= 0 ? candidate : -1
  }

  private static readNumber(value: Record<string, Object>, key: string): number {
    const candidate = value[key]
    return typeof candidate === 'number' && Number.isFinite(candidate) && candidate > 0 ? Math.floor(candidate) : 0
  }

  private static readBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }
}
