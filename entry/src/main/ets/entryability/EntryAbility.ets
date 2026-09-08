import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { display, window } from '@kit.ArkUI'
import { PreferencesStore } from '../store/PreferencesStore'
import { RdbManager } from '../store/RdbManager'
import { FileStore } from '../store/FileStore'
import { UserDownloadFolder } from '../services/UserDownloadFolder'
import { PLAYER_AUTO_PIP_DEFAULT, PREFS_KEY_PLAYER_AUTO_PIP } from '../utils/PlayerAutoPiP'
import { PLAYER_AUTO_NEXT_DEFAULT, PREFS_KEY_PLAYER_AUTO_NEXT } from '../utils/PlayerAutoNext'
import {
  PLAYER_DEFAULT_SPEED,
  PLAYER_OPEN_ORIENTATION_DEFAULT,
  PLAYER_SEEK_SECONDS_DEFAULT,
  PREFS_KEY_PLAYER_DEFAULT_SPEED,
  PREFS_KEY_PLAYER_OPEN_ORIENTATION,
  PREFS_KEY_PLAYER_SEEK_SECONDS
} from '../utils/PlayerPlaybackPreferences'
import {
  PREFS_KEY_SUBTITLE_BOTTOM_OFFSET,
  PREFS_KEY_SUBTITLE_ENABLED,
  PREFS_KEY_SUBTITLE_FONT_BOLD,
  PREFS_KEY_SUBTITLE_FONT_COLOR,
  PREFS_KEY_SUBTITLE_FONT_SIZE,
  PREFS_KEY_SUBTITLE_OUTLINE_ENABLED,
  PREFS_KEY_SUBTITLE_RECENT_COLORS,
  PREFS_KEY_SUBTITLE_TIME_OFFSET_MS,
  SUBTITLE_BOTTOM_OFFSET_DEFAULT,
  SUBTITLE_ENABLED_DEFAULT,
  SUBTITLE_FONT_BOLD_DEFAULT,
  SUBTITLE_FONT_COLOR_DEFAULT,
  SUBTITLE_FONT_SIZE_DEFAULT,
  SUBTITLE_OUTLINE_ENABLED_DEFAULT,
  SUBTITLE_TIME_OFFSET_MS_DEFAULT
} from '../utils/SubtitlePreferences'
import { HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../utils/HdsPageStyle'
import {
  BOTTOM_TAB_ANIMATION_HIDDEN_KEY,
  BOTTOM_TAB_ANIMATION_TOKEN_KEY,
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  BOTTOM_TAB_SHOW_ANIMATION_DEFAULT,
  PREFS_KEY_BOTTOM_TAB_AUTO_HIDE,
  PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION
} from '../utils/BottomTabAutoHide'
import { Logger } from '../utils/Logger'
import {
  HIDE_MEDIA_CARDS_DEFAULT,
  PREFS_KEY_HIDE_CONTINUE_WATCHING,
  PREFS_KEY_HIDE_LOCAL_MEDIA
} from '../utils/MediaVisibilityPreferences'

const logger = new Logger('EntryAbility')

export default class EntryAbility extends UIAbility {
  private density: number = 3

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('currentTab', 0)
    AppStorage.setOrCreate('topSafeHeight', 0)
    AppStorage.setOrCreate('bottomSafeHeight', 0)
    AppStorage.setOrCreate('screenWidthVp', 360)
    AppStorage.setOrCreate('screenHeightVp', 720)
    AppStorage.setOrCreate('appInForeground', true)
    AppStorage.setOrCreate('playerFullScreen', false)
    AppStorage.setOrCreate('playerPageActive', false)
    AppStorage.setOrCreate('appRdbReady', false)
    AppStorage.setOrCreate('bottomTabAutoHide', BOTTOM_TAB_AUTO_HIDE_DEFAULT)
    AppStorage.setOrCreate('bottomTabShowAnimation', BOTTOM_TAB_SHOW_ANIMATION_DEFAULT)
    AppStorage.setOrCreate('bottomTabOffset', 0)
    AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_TOKEN_KEY, 0)
    AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_HIDDEN_KEY, false)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, PLAYER_AUTO_PIP_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_NEXT, PLAYER_AUTO_NEXT_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_DEFAULT_SPEED, PLAYER_DEFAULT_SPEED)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_SEEK_SECONDS, PLAYER_SEEK_SECONDS_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_OPEN_ORIENTATION, PLAYER_OPEN_ORIENTATION_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_HIDE_LOCAL_MEDIA, HIDE_MEDIA_CARDS_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_HIDE_CONTINUE_WATCHING, HIDE_MEDIA_CARDS_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_ENABLED, SUBTITLE_ENABLED_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_SIZE, SUBTITLE_FONT_SIZE_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_BOLD, SUBTITLE_FONT_BOLD_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_COLOR, SUBTITLE_FONT_COLOR_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_RECENT_COLORS, '[]')
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_BOTTOM_OFFSET, SUBTITLE_BOTTOM_OFFSET_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, SUBTITLE_OUTLINE_ENABLED_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, SUBTITLE_TIME_OFFSET_MS_DEFAULT)
    AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, HDS_MATERIAL_LEVEL_DEFAULT)

    // The home library can start scanning as soon as the first page is shown.
    // Initialize its thumbnail cache before any asynchronous store setup.
    try {
      FileStore.getInstance().init(this.context)
    } catch (err) {
      logger.warn('Initialize local file storage failed: %{public}s', String(err))
    }

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      logger.warn('Set initial color mode failed: %{public}s', String(err))
    }
    this.initStores()
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const mainWindow = windowStage.getMainWindowSync()
    mainWindow.setWindowLayoutFullScreen(true)
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000', statusBarContentColor: '#000000',
      navigationBarColor: '#00000000', navigationBarContentColor: '#000000'
    })
    this.updateMetrics(mainWindow)
    mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate('topSafeHeight', data.area.topRect.height / this.density)
        AppStorage.setOrCreate('bottomSafeHeight', data.area.bottomRect.height / this.density)
      }
    })
    mainWindow.on('windowSizeChange', () => this.updateMetrics(mainWindow))
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) logger.error('Load main page failed: %{public}s', err.message)
    })
  }

  onForeground(): void {
    AppStorage.setOrCreate('appInForeground', true)
  }

  onBackground(): void {
    AppStorage.setOrCreate('appInForeground', false)
  }

  private updateMetrics(mainWindow: window.Window): void {
    const current = display.getDefaultDisplaySync()
    this.density = current.densityPixels > 0 ? current.densityPixels : 3
    const width = current.width / this.density
    const height = current.height / this.density
    AppStorage.setOrCreate('screenWidthVp', Math.min(width, height))
    AppStorage.setOrCreate('screenHeightVp', Math.max(width, height))
    try {
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      AppStorage.setOrCreate('topSafeHeight', area.topRect.height / this.density)
      AppStorage.setOrCreate('bottomSafeHeight', area.bottomRect.height / this.density)
    } catch (_) {}
  }

  private async initStores(): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(this.context, 'local_video_settings')
      PreferencesStore.getInstance().init(prefs)
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_PLAYER_AUTO_PIP, PLAYER_AUTO_PIP_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_NEXT, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_PLAYER_AUTO_NEXT, PLAYER_AUTO_NEXT_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_DEFAULT_SPEED, await PreferencesStore.getInstance().getNumber(PREFS_KEY_PLAYER_DEFAULT_SPEED, PLAYER_DEFAULT_SPEED))
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_SEEK_SECONDS, await PreferencesStore.getInstance().getNumber(PREFS_KEY_PLAYER_SEEK_SECONDS, PLAYER_SEEK_SECONDS_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_OPEN_ORIENTATION,
        await PreferencesStore.getInstance().getString(PREFS_KEY_PLAYER_OPEN_ORIENTATION,
          PLAYER_OPEN_ORIENTATION_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_HIDE_LOCAL_MEDIA, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_HIDE_LOCAL_MEDIA, HIDE_MEDIA_CARDS_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_HIDE_CONTINUE_WATCHING, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_HIDE_CONTINUE_WATCHING, HIDE_MEDIA_CARDS_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_ENABLED, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_SUBTITLE_ENABLED, SUBTITLE_ENABLED_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_SIZE, await PreferencesStore.getInstance().getNumber(PREFS_KEY_SUBTITLE_FONT_SIZE, SUBTITLE_FONT_SIZE_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_BOLD, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_SUBTITLE_FONT_BOLD, SUBTITLE_FONT_BOLD_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_FONT_COLOR, await PreferencesStore.getInstance().getString(PREFS_KEY_SUBTITLE_FONT_COLOR, SUBTITLE_FONT_COLOR_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_RECENT_COLORS, await PreferencesStore.getInstance().getString(PREFS_KEY_SUBTITLE_RECENT_COLORS, '[]'))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_BOTTOM_OFFSET, await PreferencesStore.getInstance().getNumber(PREFS_KEY_SUBTITLE_BOTTOM_OFFSET, SUBTITLE_BOTTOM_OFFSET_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, await PreferencesStore.getInstance().getBoolean(PREFS_KEY_SUBTITLE_OUTLINE_ENABLED, SUBTITLE_OUTLINE_ENABLED_DEFAULT))
      AppStorage.setOrCreate(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, await PreferencesStore.getInstance().getNumber(PREFS_KEY_SUBTITLE_TIME_OFFSET_MS, SUBTITLE_TIME_OFFSET_MS_DEFAULT))
      AppStorage.setOrCreate('bottomTabAutoHide', await PreferencesStore.getInstance().getBoolean(PREFS_KEY_BOTTOM_TAB_AUTO_HIDE, BOTTOM_TAB_AUTO_HIDE_DEFAULT))
      AppStorage.setOrCreate('bottomTabShowAnimation', await PreferencesStore.getInstance().getBoolean(PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION, BOTTOM_TAB_SHOW_ANIMATION_DEFAULT))
      AppStorage.setOrCreate('bottomTabOffset', 0)
      AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_TOKEN_KEY, 0)
      AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_HIDDEN_KEY, false)
      AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, await PreferencesStore.getInstance().getString(PREFS_KEY_HDS_MATERIAL_LEVEL, HDS_MATERIAL_LEVEL_DEFAULT))
    } catch (err) {
      logger.error('Initialize preferences failed: %{public}s', String(err))
    }
    try {
      await RdbManager.getInstance().init(this.context)
      AppStorage.setOrCreate('appRdbReady', true)
    } catch (err) {
      logger.error('Initialize local history database failed: %{public}s', String(err))
    }
    try {
      await UserDownloadFolder.ensureOwnFolder(this.context)
    } catch (err) {
      logger.warn('Initialize local file storage failed: %{public}s', String(err))
    }
  }
}
