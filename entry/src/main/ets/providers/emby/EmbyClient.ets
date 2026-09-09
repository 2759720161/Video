import { http } from '@kit.NetworkKit'
import {
  EmbyItem,
  EmbyPlaybackContext,
  EmbyPlaybackRoute,
  EmbyServerConfig
} from './EmbyModels'

const EMBY_CLIENT_NAME: string = 'Yingxia'
const EMBY_DEVICE_NAME: string = 'HarmonyOS'
const EMBY_CLIENT_VERSION: string = '1.0.0'

export class EmbyClient {
  private config: EmbyServerConfig

  constructor(config: EmbyServerConfig) {
    this.config = config
  }

  static async login(serverUrl: string, userName: string, password: string,
    existingDeviceId: string = ''): Promise<EmbyServerConfig> {
    const config = new EmbyServerConfig()
    config.baseUrl = EmbyClient.normalizeBaseUrl(serverUrl)
    const normalizedDeviceId = EmbyClient.normalizeText(existingDeviceId)
    const normalizedUserName = EmbyClient.normalizeText(userName)
    config.deviceId = normalizedDeviceId.length > 0 ? normalizedDeviceId : EmbyClient.createDeviceId()
    const client = new EmbyClient(config)
    const publicInfo = await client.requestObject('/System/Info/Public', http.RequestMethod.GET, null, false)
    const body: Record<string, Object> = {
      'Username': normalizedUserName,
      'Pw': password
    }
    const auth = await client.requestObject('/Users/AuthenticateByName', http.RequestMethod.POST, body, false)
    const user = EmbyClient.readObject(auth, 'User')
    config.serverId = EmbyClient.readString(auth, 'ServerId', EmbyClient.readString(publicInfo, 'Id'))
    config.serverName = EmbyClient.readString(publicInfo, 'ServerName')
    config.serverVersion = EmbyClient.readString(publicInfo, 'Version')
    config.userId = EmbyClient.readString(user, 'Id')
    config.userName = EmbyClient.readString(user, 'Name', normalizedUserName)
    config.accessToken = EmbyClient.readString(auth, 'AccessToken')
    if (!config.isValid()) {
      throw new Error('Emby 登录响应缺少用户或令牌信息')
    }
    return config
  }

  async getLibraries(): Promise<EmbyItem[]> {
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Views?IncludeExternalContent=false'
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  async getItem(itemId: string): Promise<EmbyItem | null> {
    const normalizedItemId = EmbyClient.normalizeText(itemId)
    if (normalizedItemId.length === 0) return null
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items/' + encodeURIComponent(normalizedItemId) +
      '?Fields=Overview%2CPrimaryImageAspectRatio%2CParentId&EnableImages=true&EnableUserData=true'
    const value = await this.requestObject(path, http.RequestMethod.GET)
    const items = this.parseItems({ 'Items': [value] })
    return items.length === 0 ? null : items[0]
  }

  async searchItems(keyword: string, limit: number = 50): Promise<EmbyItem[]> {
    const query = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?SearchTerm=' +
      encodeURIComponent(EmbyClient.normalizeText(keyword)) + '&Recursive=true&Limit=' + Math.max(1, limit) +
      '&Fields=Overview%2CPrimaryImageAspectRatio%2CParentId&EnableImages=true&EnableUserData=true'
    return this.parseItems(await this.requestObject(query, http.RequestMethod.GET))
  }

  async getItems(parentId: string, limit: number = 0, recursive: boolean = false,
    itemTypes: string = '', sortBy: string = 'SortName', sortOrder: string = 'Ascending'): Promise<EmbyItem[]> {
    const normalizedParentId = EmbyClient.normalizeText(parentId)
    const query: string[] = [
      'ParentId=' + encodeURIComponent(normalizedParentId),
      'Recursive=' + (recursive ? 'true' : 'false'),
      'SortBy=' + encodeURIComponent(sortBy),
      'SortOrder=' + encodeURIComponent(sortOrder),
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId',
      'EnableImages=true',
      'EnableUserData=true',
      'ImageTypeLimit=1'
    ]
    const normalizedItemTypes = EmbyClient.normalizeText(itemTypes)
    if (normalizedItemTypes.length > 0) {
      query.push('IncludeItemTypes=' + encodeURIComponent(normalizedItemTypes))
    }
    if (limit > 0) {
      query.push('Limit=' + limit)
    }
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  /**
   * Returns the actual media entries inside a library instead of its immediate
   * child folders/ Series and movies are deliberately selected so a TV library
   * is rendered as newest-first poster cards rather than a second folder tree/
   */
  async getLibraryItems(parentId: string, limit: number = 0, collectionType: string = ''): Promise<EmbyItem[]> {
    const normalizedType = EmbyClient.normalizeText(collectionType).toLowerCase()
    let itemTypes = 'Series,Movie'
    if (normalizedType === 'tvshows') {
      itemTypes = 'Series'
    } else if (normalizedType === 'movies') {
      itemTypes = 'Movie'
    } else if (normalizedType === 'musicvideos' || normalizedType === 'homevideos') {
      itemTypes = 'Video'
    }
    return await this.getItems(parentId, limit, true, itemTypes, 'DateCreated', 'Descending')
  }

  async getResumeItems(limit: number = 12): Promise<EmbyItem[]> {
    const query: string[] = [
      'Recursive=true',
      'MediaTypes=Video',
      'Limit=' + Math.max(1, limit),
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId',
      'EnableImages=true',
      'EnableUserData=true',
      'ImageTypeLimit=1'
    ]
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items/Resume?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  async getLatestItems(limit: number = 16): Promise<EmbyItem[]> {
    const query: string[] = [
      'Recursive=true',
      'IncludeItemTypes=Movie%2CSeries%2CEpisode%2CVideo',
      'SortBy=DateCreated',
      'SortOrder=Descending',
      'Fields=Overview%2CPrimaryImageAspectRatio%2CParentId',
      'EnableImages=true',
      'EnableUserData=true',
      'ImageTypeLimit=1'
    ]
    if (limit > 0) {
      query.push('Limit=' + limit)
    }
    const path = '/Users/' + encodeURIComponent(this.config.userId) + '/Items?' + query.join('&')
    const response = await this.requestObject(path, http.RequestMethod.GET)
    return this.parseItems(response)
  }

  imageUrl(item: EmbyItem, maxWidth: number = 500): string {
    if (item.imageItemId.length === 0 || item.primaryImageTag.length === 0) {
      return ''
    }
    return this.config.baseUrl + '/Items/' + encodeURIComponent(item.imageItemId) + '/Images/Primary' +
      '?maxWidth=' + maxWidth + '&quality=85&tag=' + encodeURIComponent(item.primaryImageTag) +
      '&api_key=' + encodeURIComponent(this.config.accessToken)
  }

  async getPlaybackRoute(item: EmbyItem): Promise<EmbyPlaybackRoute> {
    const path = '/Items/' + encodeURIComponent(item.id) + '/PlaybackInfo?UserId=' +
      encodeURIComponent(this.config.userId)
    const response = await this.requestObject(path, http.RequestMethod.GET)
    const sourceValues = EmbyClient.readObjectArray(response, 'MediaSources')
    if (sourceValues.length === 0) {
      throw new Error('Emby 未返回可播放的媒体源')
    }
    const source = sourceValues[0]
    const mediaSourceId = EmbyClient.readString(source, 'Id', item.id)
    const playSessionId = EmbyClient.readString(response, 'PlaySessionId', EmbyClient.createSessionId())
    const directStreamUrl = EmbyClient.readString(source, 'DirectStreamUrl')
    let url = directStreamUrl.length > 0 ? this.absoluteUrl(directStreamUrl) : ''
    if (url.length === 0) {
      const container = EmbyClient.safeContainer(EmbyClient.readString(source, 'Container', item.container))
      url = this.config.baseUrl + '/Videos/' + encodeURIComponent(item.id) + '/stream/' + container +
        '?static=true&MediaSourceId=' + encodeURIComponent(mediaSourceId) +
        '&PlaySessionId=' + encodeURIComponent(playSessionId)
    }
    url = EmbyClient.appendQuery(url, 'api_key', this.config.accessToken)
    const route = new EmbyPlaybackRoute()
    route.url = url
    route.context.itemId = item.id
    route.context.mediaSourceId = mediaSourceId
    route.context.playSessionId = playSessionId
    route.context.playMethod = 'DirectStream'
    return route
  }

  async reportPlayback(endpoint: string, context: EmbyPlaybackContext, positionMs: number,
    durationMs: number, playing: boolean, speed: number, eventName: string = ''): Promise<void> {
    const normalizedDurationMs = Number.isFinite(durationMs) && durationMs > 0 ? Math.floor(durationMs) : 0
    let normalizedPositionMs = Number.isFinite(positionMs) ? Math.max(0, Math.floor(positionMs)) : 0
    if (normalizedDurationMs > 0) normalizedPositionMs = Math.min(normalizedPositionMs, normalizedDurationMs)
    const normalizedSpeed = Number.isFinite(speed) && speed > 0 ? speed : 1
    const body: Record<string, Object> = {
      'QueueableMediaTypes': ['Video'],
      'CanSeek': true,
      'ItemId': context.itemId,
      'MediaSourceId': context.mediaSourceId,
      'IsPaused': !playing,
      'IsMuted': false,
      'PositionTicks': normalizedPositionMs * 10000,
      'PlayMethod': context.playMethod,
      'PlaySessionId': context.playSessionId,
      'PlaylistIndex': 0,
      'PlaylistLength': 1,
      'PlaybackRate': normalizedSpeed
    }
    if (normalizedDurationMs > 0) {
      body['RunTimeTicks'] = normalizedDurationMs * 10000
    }
    if (eventName.length > 0) {
      body['EventName'] = eventName
    }
    await this.requestObject(endpoint, http.RequestMethod.POST, body)
  }

  async logout(): Promise<void> {
    await this.requestObject('/Sessions/Logout', http.RequestMethod.POST, {})
  }

  private async requestObject(path: string, method: http.RequestMethod,
    body: Record<string, Object> | null = null, authenticated: boolean = true): Promise<Record<string, Object>> {
    const request = http.createHttp()
    try {
      const headers: Record<string, string> = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Emby-Authorization': this.authorizationHeader(authenticated)
      }
      if (authenticated && this.config.accessToken.length > 0) {
        headers['X-Emby-Token'] = this.config.accessToken
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      }
      if (body !== null) {
        options.extraData = JSON.stringify(body)
      }
      const response = await request.request(this.config.baseUrl + path, options)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (response.responseCode === 401) {
          throw new Error('用户名、密码或 Emby 登录状态无效')
        }
        throw new Error('Emby 请求失败（HTTP ' + response.responseCode + '）')
      }
      const raw = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      if (raw.length === 0) {
        return {}
      }
      const parsed: Object = JSON.parse(raw)
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Emby 响应格式无效')
      }
      return parsed as Record<string, Object>
    } finally {
      request.destroy()
    }
  }

  private authorizationHeader(authenticated: boolean): string {
    const parts: string[] = [
      'Client="' + EMBY_CLIENT_NAME + '"',
      'Device="' + EMBY_DEVICE_NAME + '"',
      'DeviceId="' + this.config.deviceId + '"',
      'Version="' + EMBY_CLIENT_VERSION + '"'
    ]
    if (authenticated && this.config.userId.length > 0) {
      parts.push('UserId="' + this.config.userId + '"')
    }
    return 'Emby ' + parts.join(', ')
  }

  private parseItems(response: Record<string, Object>): EmbyItem[] {
    const values = EmbyClient.readObjectArray(response, 'Items')
    const items: EmbyItem[] = []
    for (let i = 0; i < values.length; i++) {
      const value = values[i]
      const item = new EmbyItem()
      item.id = EmbyClient.readString(value, 'Id')
      item.name = EmbyClient.readString(value, 'Name')
      item.type = EmbyClient.readString(value, 'Type')
      item.parentId = EmbyClient.readString(value, 'ParentId')
      item.collectionType = EmbyClient.readString(value, 'CollectionType')
      item.isFolder = EmbyClient.readBoolean(value, 'IsFolder') || EmbyClient.isFolderType(item.type)
      item.runTimeTicks = EmbyClient.readNumber(value, 'RunTimeTicks')
      item.productionYear = EmbyClient.readNumber(value, 'ProductionYear')
      item.indexNumber = EmbyClient.readNumber(value, 'IndexNumber')
      item.parentIndexNumber = EmbyClient.readNumber(value, 'ParentIndexNumber')
      item.seriesName = EmbyClient.readString(value, 'SeriesName')
      item.overview = EmbyClient.readString(value, 'Overview')
      item.container = EmbyClient.readString(value, 'Container')
      item.primaryImageTag = EmbyClient.readString(value, 'PrimaryImageTag')
      item.imageItemId = item.id
      if (item.primaryImageTag.length === 0) {
        item.primaryImageTag = EmbyClient.readString(EmbyClient.readObject(value, 'ImageTags'), 'Primary')
      }
      if (item.primaryImageTag.length === 0) {
        item.primaryImageTag = EmbyClient.readString(value, 'SeriesPrimaryImageTag')
        item.imageItemId = EmbyClient.readString(value, 'SeriesId', item.id)
      }
      const userData = EmbyClient.readObject(value, 'UserData')
      item.userData.playbackPositionTicks = EmbyClient.readNumber(userData, 'PlaybackPositionTicks')
      item.userData.playedPercentage = EmbyClient.readNumber(userData, 'PlayedPercentage')
      item.userData.played = EmbyClient.readBoolean(userData, 'Played')
      if (item.id.length > 0 && item.name.length > 0) {
        items.push(item)
      }
    }
    return items
  }

  private absoluteUrl(path: string): string {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path
    }
    const lowerPath = path.toLowerCase()
    if (lowerPath === '/emby' || lowerPath.startsWith('/emby/')) {
      const marker = this.config.baseUrl.toLowerCase().lastIndexOf('/emby')
      return (marker >= 0 ? this.config.baseUrl.substring(0, marker) : this.config.baseUrl) + path
    }
    return this.config.baseUrl + (path.startsWith('/') ? path : '/' + path)
  }

  static normalizeBaseUrl(value: string): string {
    let baseUrl = EmbyClient.normalizeText(value)
    const scheme = baseUrl.toLowerCase()
    if (!scheme.startsWith('http://') && !scheme.startsWith('https://')) {
      baseUrl = 'http://' + baseUrl
    }
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1)
    }
    const urlParts = baseUrl.match(/^(https?):\/\/([^/]+)(.*)$/i)
    if (urlParts !== null) {
      baseUrl = urlParts[1].toLowerCase() + '://' + urlParts[2].toLowerCase() + urlParts[3]
    }
    if (!baseUrl.toLowerCase().endsWith('/emby')) {
      baseUrl += '/emby'
    }
    return baseUrl
  }

  private static createDeviceId(): string {
    return 'yingxia-' + Date.now() + '-' + Math.floor(Math.random() * 1000000000)
  }

  private static createSessionId(): string {
    return String(Date.now()) + String(Math.floor(Math.random() * 1000000000))
  }

  private static appendQuery(url: string, key: string, value: string): string {
    if (url.indexOf(key + '=') >= 0) {
      return url
    }
    return url + (url.indexOf('?') >= 0 ? '&' : '?') + key + '=' + encodeURIComponent(value)
  }

  private static safeContainer(value: string): string {
    const normalized = value.toLowerCase().split(',')[0]
    return /^[a-z0-9]+$/.test(normalized) ? normalized : 'mp4'
  }

  private static isFolderType(type: string): boolean {
    return type === 'CollectionFolder' || type === 'Folder' || type === 'UserView' ||
      type === 'Series' || type === 'Season' || type === 'BoxSet' || type === 'Playlist'
  }

  private static readString(value: Record<string, Object>, key: string, fallback: string = ''): string {
    return typeof value[key] === 'string' ? value[key] as string : fallback
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static readNumber(value: Record<string, Object>, key: string): number {
    return typeof value[key] === 'number' && Number.isFinite(value[key] as number) ? value[key] as number : 0
  }

  private static readBoolean(value: Record<string, Object>, key: string): boolean {
    return typeof value[key] === 'boolean' ? value[key] as boolean : false
  }

  private static readObject(value: Record<string, Object>, key: string): Record<string, Object> {
    const nested = value[key]
    return nested !== null && typeof nested === 'object' ? nested as Record<string, Object> : {}
  }

  private static readObjectArray(value: Record<string, Object>, key: string): Array<Record<string, Object>> {
    const nested = value[key]
    if (!Array.isArray(nested)) return []
    const result: Array<Record<string, Object>> = []
    for (let i = 0; i < nested.length; i++) {
      const candidate = nested[i] as Object
      if (candidate !== null && typeof candidate === 'object' && !Array.isArray(candidate)) {
        result.push(candidate as Record<string, Object>)
      }
    }
    return result
  }
}
