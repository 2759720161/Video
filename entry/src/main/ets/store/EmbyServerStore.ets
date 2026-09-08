import { EmbyServerConfig } from '../models/EmbyModels'
import { PreferencesStore } from './PreferencesStore'

const PREFS_KEY_EMBY_SERVER: string = 'embyServerConfigV1'
export const EMBY_SOURCE_VERSION_KEY: string = 'embySourceVersion'

export class EmbyServerStore {
  private static version: number = 0

  static async load(): Promise<EmbyServerConfig | null> {
    const raw = await PreferencesStore.getInstance().getString(PREFS_KEY_EMBY_SERVER, '')
    if (raw.length === 0) {
      return null
    }
    try {
      const value = JSON.parse(raw) as Record<string, Object>
      const config = new EmbyServerConfig()
      config.baseUrl = EmbyServerStore.readString(value, 'baseUrl')
      config.serverId = EmbyServerStore.readString(value, 'serverId')
      config.serverName = EmbyServerStore.readString(value, 'serverName')
      config.serverVersion = EmbyServerStore.readString(value, 'serverVersion')
      config.userId = EmbyServerStore.readString(value, 'userId')
      config.userName = EmbyServerStore.readString(value, 'userName')
      config.accessToken = EmbyServerStore.readString(value, 'accessToken')
      config.deviceId = EmbyServerStore.readString(value, 'deviceId')
      return config.isValid() ? config : null
    } catch (_err) {
      return null
    }
  }

  static async save(config: EmbyServerConfig): Promise<void> {
    await PreferencesStore.getInstance().setString(PREFS_KEY_EMBY_SERVER, JSON.stringify(config))
    EmbyServerStore.notifyChanged()
  }

  static async clear(): Promise<void> {
    await PreferencesStore.getInstance().delete(PREFS_KEY_EMBY_SERVER)
    EmbyServerStore.notifyChanged()
  }

  private static notifyChanged(): void {
    EmbyServerStore.version = Math.max(EmbyServerStore.version + 1, Date.now())
    if (!AppStorage.set<number>(EMBY_SOURCE_VERSION_KEY, EmbyServerStore.version)) {
      AppStorage.setOrCreate<number>(EMBY_SOURCE_VERSION_KEY, EmbyServerStore.version)
    }
  }

  private static readString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }
}
