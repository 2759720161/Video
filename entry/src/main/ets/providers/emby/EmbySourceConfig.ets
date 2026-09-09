import { EmbyServerConfig } from './EmbyModels'

/** 负责来源 JSON 与 Emby 私有配置之间的边界转换。 */
export class EmbySourceConfigCodec {
  static encode(config: EmbyServerConfig): string {
    return JSON.stringify(config)
  }

  static decode(raw: string): EmbyServerConfig | null {
    if (typeof raw !== 'string' || raw.length === 0) return null
    try {
      const parsed = JSON.parse(raw) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null
      const value = parsed as Record<string, Object>
      const config = new EmbyServerConfig()
      config.baseUrl = EmbySourceConfigCodec.readString(value, 'baseUrl').trim()
      const scheme = config.baseUrl.toLowerCase()
      if (config.baseUrl.length > 0 && !scheme.startsWith('http://') && !scheme.startsWith('https://')) {
        config.baseUrl = 'http://' + config.baseUrl
      }
      config.baseUrl = config.baseUrl.replace(/\/+$/, '')
      const urlParts = config.baseUrl.match(/^(https?):\/\/([^/]+)(.*)$/i)
      if (urlParts !== null) {
        config.baseUrl = urlParts[1].toLowerCase() + '://' + urlParts[2].toLowerCase() + urlParts[3]
      }
      config.serverId = EmbySourceConfigCodec.readString(value, 'serverId').trim()
      config.serverName = EmbySourceConfigCodec.readString(value, 'serverName').trim()
      config.serverVersion = EmbySourceConfigCodec.readString(value, 'serverVersion').trim()
      config.userId = EmbySourceConfigCodec.readString(value, 'userId').trim()
      config.userName = EmbySourceConfigCodec.readString(value, 'userName').trim()
      config.accessToken = EmbySourceConfigCodec.readString(value, 'accessToken').trim()
      config.deviceId = EmbySourceConfigCodec.readString(value, 'deviceId').trim()
      if (!/^https?:\/\/[^\s]+$/i.test(config.baseUrl)) return null
      if (!config.baseUrl.toLowerCase().endsWith('/emby')) config.baseUrl += '/emby'
      return config.isValid() ? config : null
    } catch (_err) {
      return null
    }
  }

  private static readString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }
}
