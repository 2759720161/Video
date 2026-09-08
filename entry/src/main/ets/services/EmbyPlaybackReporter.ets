import { EmbyPlaybackContext } from '../models/EmbyModels'
import { EmbyClient } from '../network/EmbyClient'
import { EmbyServerStore } from '../store/EmbyServerStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('EmbyPlaybackReporter')

export class EmbyPlaybackReporter {
  private context: EmbyPlaybackContext

  constructor(context: EmbyPlaybackContext) {
    this.context = context
  }

  async started(positionMs: number, durationMs: number, playing: boolean, speed: number): Promise<void> {
    await this.report('/Sessions/Playing', positionMs, durationMs, playing, speed)
  }

  async progress(positionMs: number, durationMs: number, playing: boolean, speed: number,
    eventName: string = 'TimeUpdate'): Promise<void> {
    await this.report('/Sessions/Playing/Progress', positionMs, durationMs, playing, speed, eventName)
  }

  async stopped(positionMs: number, durationMs: number, speed: number): Promise<void> {
    await this.report('/Sessions/Playing/Stopped', positionMs, durationMs, false, speed)
  }

  private async report(endpoint: string, positionMs: number, durationMs: number, playing: boolean,
    speed: number, eventName: string = ''): Promise<void> {
    try {
      const config = await EmbyServerStore.load()
      if (config === null) {
        return
      }
      await new EmbyClient(config).reportPlayback(endpoint, this.context, positionMs, durationMs,
        playing, speed, eventName)
    } catch (err) {
      logger.warn('Emby playback report failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }
}
