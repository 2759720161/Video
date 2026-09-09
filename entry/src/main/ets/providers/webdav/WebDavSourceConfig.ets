export class WebDavSourceConfig {
  baseUrl: string = ''
  userName: string = ''
  password: string = ''
  rootPath: string = '/'
}

export class WebDavSourceConfigCodec {
  static decode(raw: string): WebDavSourceConfig | null {
    if (typeof raw !== 'string' || raw.length === 0) return null
    try {
      const parsed = JSON.parse(raw) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null
      const value = parsed as Record<string, Object>
      const config = new WebDavSourceConfig()
      config.baseUrl = WebDavSourceConfigCodec.read(value, 'baseUrl')
      config.userName = WebDavSourceConfigCodec.read(value, 'userName')
      config.password = WebDavSourceConfigCodec.read(value, 'password')
      config.rootPath = WebDavSourceConfigCodec.read(value, 'rootPath') || '/'
      return WebDavSourceConfigCodec.normalize(config) ? config : null
    } catch (_) { return null }
  }

  /** 只持久化非敏感字段；旧 password 字段仍由 decode 读取供迁移使用。 */
  static encode(config: WebDavSourceConfig): string {
    return JSON.stringify({
      baseUrl: config.baseUrl,
      userName: config.userName,
      rootPath: config.rootPath
    })
  }

  /** 统一持久化格式，避免重启后因尾斜杠或相对根路径导致地址漂移。 */
  static normalize(config: WebDavSourceConfig): boolean {
    config.baseUrl = WebDavSourceConfigCodec.normalizeText(config.baseUrl)
      .replace(/\/+$/, '')
    if (!/^https?:\/\/[^\s]+$/i.test(config.baseUrl)) return false
    const urlParts = config.baseUrl.match(/^(https?):\/\/([^/]+)(.*)$/i)
    if (urlParts !== null) {
      config.baseUrl = urlParts[1].toLowerCase() + '://' + urlParts[2].toLowerCase() + urlParts[3]
    }
    let root = WebDavSourceConfigCodec.normalizeText(config.rootPath).replace(/\\/g, '/')
    if (root.length === 0) root = '/'
    if (!root.startsWith('/')) root = '/' + root
    root = root.replace(/\/+/g, '/')
    if (root.length > 1) root = root.replace(/\/+$/, '') + '/'
    config.rootPath = root
    config.userName = WebDavSourceConfigCodec.normalizeText(config.userName)
    return true
  }

  private static read(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
