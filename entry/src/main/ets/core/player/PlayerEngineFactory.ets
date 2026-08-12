import { IPlayerEngine } from './IPlayerEngine'
import { AVPlayerEngine } from './AVPlayerEngine'
import { isMpvNapiLoaded, MpvPlayerEngine } from './MpvPlayerEngine'

export type EngineType = 'avplayer' | 'mpv'

/** MPV is preferred on arm64 devices; AVPlayer remains the safe fallback. */
export class PlayerEngineFactory {
  static async create(): Promise<IPlayerEngine> {
    return PlayerEngineFactory.createByType('mpv')
  }

  static createByType(engineType: string): IPlayerEngine {
    if (engineType === 'mpv' && isMpvNapiLoaded()) {
      return new MpvPlayerEngine()
    }
    return new AVPlayerEngine()
  }

  static async createWithFallback(engineType: string): Promise<IPlayerEngine> {
    return PlayerEngineFactory.createByType(engineType)
  }

  static getAvailableEngines(): string[] {
    return isMpvNapiLoaded() ? ['mpv', 'avplayer'] : ['avplayer']
  }
}
