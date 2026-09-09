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

  private static readNumber(value: Record<string, Object>, key: string): number {
    const candidate = value[key]
    return typeof candidate === 'number' && Number.isFinite(candidate) && candidate > 0 ? Math.floor(candidate) : 0
  }

  private static readBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }
}
