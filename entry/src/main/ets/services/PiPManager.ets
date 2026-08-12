import { PiPWindow } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('PiPManager')

export class PiPCallbacks {
  onPlay?: () => void
  onPause?: () => void
  onNext?: () => void
  onPrevious?: () => void
  onFastForward?: () => void
  onFastBackward?: () => void
  onRestore?: () => void
  onPiPStopped?: () => void
}

export class PiPManager {
  private static instance: PiPManager | null = null

  private pipController: PiPWindow.PiPController | null = null
  private callbacks: PiPCallbacks = new PiPCallbacks()
  private _isActive: boolean = false
  private _isCreating: boolean = false
  private xComponentController: XComponentController | null = null
  private context: Context | null = null
  private lastContentWidth: number = 0
  private lastContentHeight: number = 0

  static getInstance(): PiPManager {
    if (PiPManager.instance === null) {
      PiPManager.instance = new PiPManager()
    }
    return PiPManager.instance
  }

  isActive(): boolean {
    return this._isActive
  }

  isCreating(): boolean {
    return this._isCreating
  }

  static isPiPSupported(): boolean {
    try {
      return PiPWindow.isPiPEnabled()
    } catch (err) {
      const businessError = err as BusinessError
      logger.warn('isPiPEnabled threw error: %{public}d - %{public}s',
        businessError.code, businessError.message)
      return false
    }
  }

  setCallbacks(callbacks: PiPCallbacks): void {
    this.callbacks = callbacks
  }

  async createAndStart(context: Context, xComponentController: XComponentController,
    contentWidth: number, contentHeight: number,
    controlGroups: Array<PiPWindow.VideoPlayControlGroup>,
    defaultWindowSizeType?: number): Promise<boolean> {
    if (this._isActive || this._isCreating) {
      logger.warn('PiP already active or creating')
      return false
    }

    if (!PiPManager.isPiPSupported()) {
      logger.warn('PiP not supported on this device')
      return false
    }

    this._isCreating = true
    this.context = context
    this.xComponentController = xComponentController
    this.lastContentWidth = contentWidth
    this.lastContentHeight = contentHeight

    try {
      const config: PiPWindow.PiPConfiguration = {
        context: context as common.UIAbilityContext,
        componentController: xComponentController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: contentWidth > 0 ? contentWidth : 1920,
        contentHeight: contentHeight > 0 ? contentHeight : 1080,
        controlGroups: controlGroups,
        defaultWindowSizeType: defaultWindowSizeType
      }

      this.pipController = await PiPWindow.create(config)
      this.registerPipListeners()
      await this.pipController.startPiP()
      this._isCreating = false
      logger.info('PiP started successfully')
      return true
    } catch (err) {
      const businessError = err as BusinessError
      logger.warn('PiP create/start failed: %{public}d - %{public}s',
        businessError.code, businessError.message)
      this.cleanup()
      return false
    }
  }

  async stopPiP(): Promise<void> {
    if (this.pipController === null) {
      return
    }
    try {
      await this.pipController.stopPiP()
    } catch (err) {
      const businessError = err as BusinessError
      logger.debug('stopPiP failed: %{public}d - %{public}s', businessError.code, businessError.message)
    }
    this.cleanup()
  }

  destroyPiP(): void {
    if (this.pipController !== null) {
      this.unregisterPipListeners()
      this.pipController = null
    }
    this._isActive = false
    this._isCreating = false
    this.xComponentController = null
    this.context = null
  }

  updatePlaybackState(playing: boolean): void {
    if (this.pipController === null) {
      return
    }
    try {
      this.pipController.updatePiPControlStatus(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE
      )
    } catch (err) {
      logger.debug('updatePlaybackState failed')
    }
  }

  updateContentSize(width: number, height: number): void {
    if (this.pipController === null || width <= 0 || height <= 0) {
      return
    }
    if (width === this.lastContentWidth && height === this.lastContentHeight) {
      return
    }
    this.lastContentWidth = width
    this.lastContentHeight = height
    try {
      this.pipController.updateContentSize(width, height)
    } catch (err) {
      logger.debug('updateContentSize failed')
    }
  }

  setNextPreviousEnabled(hasNext: boolean, hasPrevious: boolean): void {
    if (this.pipController === null) {
      return
    }
    try {
      if (hasNext) {
        this.pipController.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_NEXT, true)
      } else {
        this.pipController.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_NEXT, false)
      }
      if (hasPrevious) {
        this.pipController.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_PREVIOUS, true)
      } else {
        this.pipController.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_PREVIOUS, false)
      }
    } catch (err) {
      logger.debug('setNextPreviousEnabled failed')
    }
  }

  private registerPipListeners(): void {
    if (this.pipController === null) {
      return
    }

    this.pipController.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
      logger.info('PiP stateChange: state=%{public}d reason=%{public}s', state, reason)
      switch (state) {
        case PiPWindow.PiPState.STARTED:
          this._isActive = true
          break
        case PiPWindow.PiPState.ABOUT_TO_RESTORE:
          if (this.callbacks.onRestore !== undefined) {
            this.callbacks.onRestore()
          }
          break
        case PiPWindow.PiPState.STOPPED:
          if (this.callbacks.onPiPStopped !== undefined) {
            this.callbacks.onPiPStopped()
          }
          this.cleanup()
          break
        case PiPWindow.PiPState.ERROR:
          logger.warn('PiP error')
          this.cleanup()
          break
        default:
          break
      }
    })

    this.pipController.on('controlPanelActionEvent',
      (event: PiPWindow.PiPActionEventType, status?: number) => {
        logger.info('PiP controlPanelActionEvent: event=%{public}s status=%{public}s',
          event, String(status))
        if (event === 'playbackStateChanged') {
          if (status === PiPWindow.PiPControlStatus.PLAY) {
            if (this.callbacks.onPlay !== undefined) {
              this.callbacks.onPlay()
            }
          } else {
            if (this.callbacks.onPause !== undefined) {
              this.callbacks.onPause()
            }
          }
        } else if (event === 'nextVideo') {
          if (this.callbacks.onNext !== undefined) {
            this.callbacks.onNext()
          }
        } else if (event === 'previousVideo') {
          if (this.callbacks.onPrevious !== undefined) {
            this.callbacks.onPrevious()
          }
        } else if (event === 'fastForward') {
          if (this.callbacks.onFastForward !== undefined) {
            this.callbacks.onFastForward()
          }
        } else if (event === 'fastBackward') {
          if (this.callbacks.onFastBackward !== undefined) {
            this.callbacks.onFastBackward()
          }
        }
      })
  }

  private unregisterPipListeners(): void {
    if (this.pipController === null) {
      return
    }
    try {
      this.pipController.off('stateChange')
      this.pipController.off('controlPanelActionEvent')
    } catch (_err) {
    }
  }

  private cleanup(): void {
    this.unregisterPipListeners()
    this.pipController = null
    this._isActive = false
    this._isCreating = false
  }
}
