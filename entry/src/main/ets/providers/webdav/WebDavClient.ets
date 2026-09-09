import { http } from '@kit.NetworkKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { buffer } from '@kit.ArkTS'
import { WebDavEntry } from './WebDavModels'
import { WebDavSourceConfig } from './WebDavSourceConfig'

export class WebDavClient {
  private config: WebDavSourceConfig
  private digestChallenge: Record<string, string> | null = null
  private digestNonce: string = ''
  private digestNonceCount: number = 0
  private digestProbeCompleted: boolean = false

  constructor(config: WebDavSourceConfig) { this.config = config }

  async list(path: string): Promise<WebDavEntry[]> {
    const url = this.resolveUrl(path)
    const propfind = '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><resourcetype/><getcontentlength/><getcontenttype/></prop></propfind>'
    let response = await this.request(url, await this.requestHeaders(url), 'PROPFIND', propfind)
    // Digest nonces may rotate while the app is open. Refresh the challenge
    // and retry a bounded number of times so directory browsing survives a
    // nonce change without risking an authentication loop.
    for (let attempt = 0; attempt < 2 && response.responseCode === 401; attempt++) {
      if (!this.updateDigestChallenge(response.header)) break
      response = await this.request(url, await this.requestHeaders(url), 'PROPFIND', propfind)
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      if (response.responseCode === 401) throw new Error('WebDAV 认证失败，请检查用户名和密码')
      if (response.responseCode === 403) throw new Error('WebDAV 访问被拒绝，请检查账号权限')
      if (response.responseCode === 404) throw new Error('WebDAV 路径不存在，请检查服务器地址和根路径')
      throw new Error('WebDAV 请求失败（HTTP ' + response.responseCode + '）')
    }
    const entries = this.parse(typeof response.result === 'string' ? response.result : '')
    for (let i = 0; i < entries.length; i++) {
      entries[i].href = this.resolveEntryHref(entries[i].href, url)
    }
    // Depth: 1 响应会包含请求目录本身；该节点不应作为可浏览的子目录返回。
    return entries.filter((entry: WebDavEntry) => !this.isCurrentCollectionHref(entry.href, url))
  }

  streamUrl(path: string): string { return this.resolveUrl(path) }

  async streamHeaders(path: string): Promise<Record<string, string>> {
    return this.resourceHeaders(path, true)
  }

  async subtitleHeaders(path: string): Promise<Record<string, string>> {
    return this.resourceHeaders(path, false)
  }

  private async resourceHeaders(path: string, includeRange: boolean): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'User-Agent': 'Yingxia-HarmonyOS-WebDAV'
    }
    if (includeRange) headers['Range'] = 'bytes=0-'
    const url = this.resolveUrl(path)
    await this.ensureDigestChallenge(url)
    const authorization = await this.authorizationFor(url, 'GET')
    if (authorization.length > 0) headers['Authorization'] = authorization
    return headers
  }

  private resolveUrl(path: string): string {
    const trimmed = WebDavClient.normalizeText(path)
    if (/^https?:\/\/[^\s]+$/i.test(trimmed)) return this.normalizeAbsoluteUrl(trimmed)
    const base = WebDavClient.normalizeText(this.config.baseUrl).replace(/\/+$/, '')
    const rootPath = WebDavClient.normalizeText(this.config.rootPath)
    const normalized = this.normalizePath(trimmed.length === 0 ? rootPath : trimmed)
    return base + normalized
  }

  private async requestHeaders(url: string): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Depth': '1', 'Content-Type': 'application/xml', 'Accept': 'application/xml'
    }
    const authorization = await this.authorizationFor(url)
    if (authorization.length > 0) headers['Authorization'] = authorization
    return headers
  }

  private async request(url: string, headers: Record<string, string>, method: string,
    extraData: string = '') {
    const request = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: method as http.RequestMethod,
        header: headers,
        extraData: extraData,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      }
      return await request.request(url, options)
    } finally {
      request.destroy()
    }
  }

  private async ensureDigestChallenge(url: string): Promise<void> {
    if (WebDavClient.normalizeText(this.config.userName).length === 0 ||
      this.digestChallenge !== null || this.digestProbeCompleted) return
    let response = await this.request(url, await this.requestHeaders(url), 'HEAD')
    // Some NAS devices include the challenge on a 405/501 response instead
    // of returning 401. Parse every probe response before falling back.
    if (this.updateDigestChallenge(response.header)) {
      this.digestProbeCompleted = true
      return
    }
    // Some NAS implementations reject HEAD but still expose the challenge on OPTIONS.
    if (response.responseCode === 405 || response.responseCode === 501) {
      response = await this.request(url, await this.requestHeaders(url), 'OPTIONS')
      if (this.updateDigestChallenge(response.header)) {
        this.digestProbeCompleted = true
        return
      }
    }
    // A few servers only advertise Digest on the actual media GET. Probe a
    // single byte so the player receives the final Authorization header while
    // avoiding a full download before playback starts.
    const getHeaders = await this.requestHeaders(url)
    getHeaders['Range'] = 'bytes=0-0'
    response = await this.request(url, getHeaders, 'GET')
    this.updateDigestChallenge(response.header)
    this.digestProbeCompleted = true
  }

  private async authorizationFor(url: string, method: string = 'PROPFIND'): Promise<string> {
    const userName = WebDavClient.normalizeText(this.config.userName)
    if (userName.length === 0) return ''
    if (this.digestChallenge !== null) {
      const digest = await this.createDigestAuthorization(url, this.digestChallenge, method)
      // A server may advertise an unsupported Digest algorithm or qop while
      // still allowing Basic. Do not send an empty Authorization header in
      // that case; retain the usable Basic fallback.
      if (digest.length > 0) return digest
    }
    return 'Basic ' + this.base64(userName + ':' + WebDavClient.safeText(this.config.password))
  }

  private updateDigestChallenge(headers: Object): boolean {
    const challenge = this.headerValue(headers, 'www-authenticate')
    const marker = challenge.toLowerCase().indexOf('digest ')
    if (marker < 0) return false
    const fields = this.parseDigestFields(challenge.substring(marker + 7))
    if (fields['realm'] === undefined || fields['nonce'] === undefined) return false
    this.digestChallenge = fields
    this.digestNonce = fields['nonce']
    this.digestNonceCount = 0
    return true
  }

  private headerValue(headers: Object, target: string): string {
    if (headers === null || typeof headers !== 'object' || Array.isArray(headers)) return ''
    const values = headers as Record<string, Object>
    const keys = Object.keys(values)
    let fallback = ''
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() !== target) continue
      const value = values[keys[i]]
      if (typeof value === 'string') {
        if (fallback.length === 0) fallback = value
        if (target === 'www-authenticate' && value.toLowerCase().indexOf('digest ') >= 0) return value
      }
      if (Array.isArray(value)) {
        for (let j = 0; j < value.length; j++) {
          if (typeof value[j] !== 'string') continue
          const text = value[j] as string
          if (fallback.length === 0) fallback = text
          if (target === 'www-authenticate' && text.toLowerCase().indexOf('digest ') >= 0) return text
        }
      }
    }
    return fallback
  }

  private parseDigestFields(raw: string): Record<string, string> {
    const fields: Record<string, string> = {}
    let index = 0
    while (index < raw.length) {
      while (index < raw.length && (raw[index] === ',' || raw[index] === ' ' || raw[index] === '\t')) index++
      const keyStart = index
      while (index < raw.length && raw[index] !== '=' && raw[index] !== ',') index++
      if (index >= raw.length || raw[index] !== '=') break
      const key = raw.substring(keyStart, index).trim().toLowerCase()
      index++
      let value = ''
      if (raw[index] === '"') {
        index++
        while (index < raw.length && raw[index] !== '"') {
          if (raw[index] === '\\' && index + 1 < raw.length) index++
          value += raw[index++]
        }
        if (index < raw.length) index++
      } else {
        const valueStart = index
        while (index < raw.length && raw[index] !== ',') index++
        value = raw.substring(valueStart, index).trim()
      }
      if (key.length > 0) fields[key] = value
    }
    return fields
  }

  private async createDigestAuthorization(url: string, fields: Record<string, string>, method: string): Promise<string> {
    const algorithm = (fields['algorithm'] || 'MD5').toUpperCase()
    const digestAlgorithm = algorithm.startsWith('SHA-256') ? 'SHA256' : algorithm.startsWith('MD5') ? 'MD5' : ''
    const realm = fields['realm'] || ''
    const nonce = fields['nonce'] || ''
    if (digestAlgorithm.length === 0 || realm.length === 0 || nonce.length === 0) return ''
    const uri = this.digestUri(url)
    const rawQop = fields['qop'] || ''
    const qopValues = rawQop.toLowerCase().split(',')
    let useAuthQop = false
    for (let i = 0; i < qopValues.length; i++) {
      if (qopValues[i].trim() === 'auth') useAuthQop = true
    }
    if (rawQop.length > 0 && !useAuthQop) return ''
    if (this.digestNonce !== nonce) {
      this.digestNonce = nonce
      this.digestNonceCount = 0
    }
    this.digestNonceCount += 1
    const nc = this.digestNonceCount.toString(16).padStart(8, '0')
    const cnonce = Date.now().toString(16) + this.digestNonceCount.toString(16)
    let ha1 = await this.hash(this.config.userName + ':' + realm + ':' + this.config.password, digestAlgorithm)
    if (algorithm.endsWith('-SESS')) ha1 = await this.hash(ha1 + ':' + nonce + ':' + cnonce, digestAlgorithm)
    const ha2 = await this.hash(method + ':' + uri, digestAlgorithm)
    const response = useAuthQop ? await this.hash(ha1 + ':' + nonce + ':' + nc + ':' + cnonce + ':auth:' + ha2, digestAlgorithm) :
      await this.hash(ha1 + ':' + nonce + ':' + ha2, digestAlgorithm)
    const values: string[] = [
      'username="' + this.quote(this.config.userName) + '"',
      'realm="' + this.quote(realm) + '"',
      'nonce="' + this.quote(nonce) + '"',
      'uri="' + this.quote(uri) + '"',
      'response="' + response + '"',
      'algorithm=' + algorithm
    ]
    if (fields['opaque'] !== undefined) values.push('opaque="' + this.quote(fields['opaque']) + '"')
    if (useAuthQop) values.push('qop=auth', 'nc=' + nc, 'cnonce="' + cnonce + '"')
    return 'Digest ' + values.join(', ')
  }

  private digestUri(url: string): string {
    const path = url.replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]+/i, '')
    return path.length > 0 ? path : '/'
  }

  private async hash(value: string, algorithm: string): Promise<string> {
    const digest = cryptoFramework.createMd(algorithm)
    await digest.update({ data: new Uint8Array(buffer.from(value, 'utf-8').buffer) })
    const data = (await digest.digest()).data
    let result = ''
    for (let i = 0; i < data.length; i++) result += data[i].toString(16).padStart(2, '0')
    return result
  }

  private quote(value: string): string { return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') }

  private normalizePath(path: string): string {
    let rawPath = WebDavClient.normalizeText(path)
    const schemeIndex = rawPath.indexOf('://')
    if (schemeIndex > 0) {
      const pathIndex = rawPath.indexOf('/', schemeIndex + 3)
      rawPath = pathIndex >= 0 ? rawPath.substring(pathIndex) : '/'
    }
    const parts = rawPath.replace(/\\/g, '/').split('/')
    const result: string[] = []
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length === 0 || parts[i] === '.') continue
      if (parts[i] === '..') { if (result.length > 0) result.pop(); continue }
      result.push(parts[i])
    }
    const normalized = '/' + result.join('/') + (rawPath.endsWith('/') && result.length > 0 ? '/' : '')
    // encodeURI 保留路径分隔符及已存在的百分号编码，同时处理中文和空格。
    // 文件名中的 # 和 ? 不能继续作为 URL 片段/查询分隔符。
    // encodeURI 会保留百分号，即使它后面不是合法的两位十六进制编码。
    // 这类 href 在部分 NAS 上确实会出现；将非法百分号编码为字面量，
    // 避免把 `%ZZ` 等内容直接交给 HTTP 客户端而导致整条 URL 无效。
    return encodeURI(normalized).replace(/#/g, '%23').replace(/\?/g, '%3F')
      .replace(/%(?![0-9A-Fa-f]{2})/g, '%25')
  }

  private base64(value: string): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let result = ''
    let index = 0
    const bytes = new Uint8Array(buffer.from(value, 'utf-8').buffer)
    while (index < bytes.length) {
      const first = bytes[index++]
      const second = index < bytes.length ? bytes[index++] : -1
      const third = index < bytes.length ? bytes[index++] : -1
      result += alphabet.charAt(first >> 2)
      result += alphabet.charAt(((first & 3) << 4) | (second < 0 ? 0 : second >> 4))
      result += second < 0 ? '=' : alphabet.charAt(((second & 15) << 2) | (third < 0 ? 0 : third >> 6))
      result += third < 0 ? '=' : alphabet.charAt(third & 63)
    }
    return result
  }

  private parse(xml: string): WebDavEntry[] {
    const entries: WebDavEntry[] = []
    const responses = xml.match(/<[^>]*response[^>]*>[\s\S]*?<\/[^>]*response>/gi) || []
    for (let i = 0; i < responses.length; i++) {
      const block = responses[i]
      const hrefMatch = block.match(/<[^>]*href[^>]*>([\s\S]*?)<\/[^>]*href>/i)
      if (hrefMatch === null) continue
      const entry = new WebDavEntry()
      entry.href = this.decodeXml(hrefMatch[1]).trim()
      const encodedName = entry.href.split('/').filter((part: string) => part.length > 0).pop() || entry.href
      try { entry.name = decodeURIComponent(encodedName) } catch (_) { entry.name = encodedName }
      entry.isFolder = /<[^>]*collection\s*\/?>/i.test(block)
      const sizeMatch = block.match(/<[^>]*getcontentlength[^>]*>(\d+)<\//i)
      entry.contentLength = sizeMatch === null ? 0 : Number(sizeMatch[1])
      const typeMatch = block.match(/<[^>]*getcontenttype[^>]*>([\s\S]*?)<\//i)
      entry.contentType = typeMatch === null ? '' : this.decodeXml(typeMatch[1]).trim()
      entries.push(entry)
    }
    return entries
  }

  private isCurrentCollectionHref(href: string, requestUrl: string): boolean {
    const current = this.comparablePath(requestUrl)
    const candidate = this.comparablePath(href)
    return current.length > 0 && candidate.length > 0 && current === candidate
  }

  /** 将非标准的相对 href 绑定到当前 PROPFIND 目录，避免丢失 rootPath。 */
  private resolveEntryHref(href: string, requestUrl: string): string {
    const value = WebDavClient.normalizeText(href)
    if (value.length === 0) return value
    if (/^https?:\/\/[^\s]+$/i.test(value)) return this.normalizeAbsoluteUrl(value)
    const originMatch = requestUrl.match(/^[a-z][a-z0-9+.-]*:\/\/[^/]+/i)
    const origin = originMatch === null ? '' : originMatch[0]
    if (value.startsWith('/')) return origin + this.normalizePath(value)
    const requestPath = requestUrl.replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]+/i, '')
    const slash = requestPath.lastIndexOf('/')
    const basePath = slash >= 0 ? requestPath.substring(0, slash + 1) : '/'
    return origin + this.normalizePath(basePath + value)
  }

  /** 规范化服务端返回的绝对 href，避免未编码的 #/? 被当作 URL 分隔符。 */
  private normalizeAbsoluteUrl(value: string): string {
    const match = value.match(/^([a-z][a-z0-9+.-]*:\/\/[^/]+)(\/.*)?$/i)
    if (match === null) return value
    return match[1] + this.normalizePath(match[2] === undefined ? '/' : match[2])
  }

  /** 将绝对或相对 href 归一为可比较的解码路径，兼容不同 WebDAV 服务端的响应形式。 */
  private comparablePath(value: string): string {
    let path = WebDavClient.normalizeText(value).replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]+/i, '')
    const suffixIndex = path.search(/[?#]/)
    if (suffixIndex >= 0) path = path.substring(0, suffixIndex)
    try { path = decodeURIComponent(path) } catch (_) {}
    path = path.replace(/\\/g, '/').replace(/\/+/g, '/')
    if (!path.startsWith('/')) path = '/' + path
    if (path.length > 1) path = path.replace(/\/+$/, '')
    return path
  }

  private decodeXml(value: string): string {
    return value.replace(/&quot;/g, '"').replace(/&apos;/g, "'")
      .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  }

  private static safeText(value: string): string {
    return typeof value === 'string' ? value : ''
  }

  private static normalizeText(value: string): string {
    return WebDavClient.safeText(value).trim()
  }
}
