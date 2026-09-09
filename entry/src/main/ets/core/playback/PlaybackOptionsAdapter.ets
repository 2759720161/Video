import { PlaybackOptions } from '../player/IPlayerEngine'
import type { PlaybackStream } from './PlaybackStream'

export class PlaybackOptionsAdapter {
  static fromStream(stream: PlaybackStream, positionMs: number): PlaybackOptions {
    const options = new PlaybackOptions()
    options.url = stream.url
    const sourceHeaders = stream.headers as Record<string, Object>
    const keys = sourceHeaders !== null && typeof sourceHeaders === 'object' && !Array.isArray(sourceHeaders)
      ? Object.keys(sourceHeaders) : []
    for (let i = 0; i < keys.length; i++) {
      const value = sourceHeaders[keys[i]]
      if (typeof value === 'string' && value.length > 0) options.headers[keys[i]] = value
    }
    options.referer = stream.referer
    options.userAgent = stream.userAgent
    options.proxy = stream.proxy
    options.isLocalFile = stream.isLocalFile
    options.localFileSize = stream.localFileSize
    options.startPositionMs = Number.isFinite(positionMs) ? Math.max(0, Math.floor(positionMs)) : 0
    return options
  }
}
