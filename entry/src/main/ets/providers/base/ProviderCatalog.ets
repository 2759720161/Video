import { ProviderDescriptor } from './ProviderDescriptor'
import { ProviderCapability } from '../../core/media/ProviderCapabilities'

/** 页面路由和展示信息的唯一 Provider 注册表。 */
export class ProviderCatalog {
  private static descriptors: Map<string, ProviderDescriptor> = new Map()
  private static initialized: boolean = false

  static register(descriptor: ProviderDescriptor): void {
    const type = ProviderCatalog.normalize(descriptor.type).toLowerCase()
    if (type.length === 0) throw new Error('Provider descriptor type cannot be empty')
    descriptor.type = type
    ProviderCatalog.descriptors.set(type, descriptor)
  }

  static get(providerType: string): ProviderDescriptor | null {
    ProviderCatalog.ensureBuiltIns()
    return ProviderCatalog.descriptors.get(ProviderCatalog.normalize(providerType).toLowerCase()) || null
  }

  static getAddableProviders(): ProviderDescriptor[] {
    ProviderCatalog.ensureBuiltIns()
    const result: ProviderDescriptor[] = []
    ProviderCatalog.descriptors.forEach((descriptor: ProviderDescriptor) => {
      if (descriptor.enabled && descriptor.addRoute.length > 0) result.push(descriptor)
    })
    return result
  }

  /** Provider Gallery 同时展示可添加来源和已注册但尚未开放的来源。 */
  static getGalleryProviders(): ProviderDescriptor[] {
    ProviderCatalog.ensureBuiltIns()
    const result: ProviderDescriptor[] = []
    ProviderCatalog.descriptors.forEach((descriptor: ProviderDescriptor) => {
      if (descriptor.type !== 'local' && (descriptor.addRoute.length > 0 || descriptor.comingSoonText.length > 0)) {
        result.push(descriptor)
      }
    })
    return result
  }

  private static ensureBuiltIns(): void {
    if (ProviderCatalog.initialized) return
    ProviderCatalog.initialized = true
    const emby = new ProviderDescriptor()
    emby.type = 'emby'
    emby.displayName = 'Emby'
    emby.category = '媒体服务器'
    emby.description = '连接 Emby 媒体服务器，浏览并播放远程媒体。'
    emby.shortDescription = '家庭媒体服务器'
    emby.featureSummary = '电影、剧集、播放进度同步'
    emby.brandKind = 'emby'
    emby.iconKind = 'media'
    emby.addRoute = 'pages/sources/EmbySourceEditPage'
    emby.editRoute = emby.addRoute
    emby.browserRoute = 'pages/emby/EmbyLibraryPage'
    emby.capabilities = [ProviderCapability.HOME, ProviderCapability.BROWSE, ProviderCapability.SEARCH,
      ProviderCapability.DETAIL, ProviderCapability.RESUME, ProviderCapability.REMOTE_PROGRESS_SYNC,
      ProviderCapability.TRANSCODE, ProviderCapability.MULTI_VERSION, ProviderCapability.ARTWORK]
    ProviderCatalog.register(emby)
    const webdav = new ProviderDescriptor()
    webdav.type = 'webdav'
    webdav.displayName = 'WebDAV'
    webdav.category = '文件服务'
    webdav.description = '连接支持 WebDAV 的 NAS、服务器或网盘。'
    webdav.shortDescription = 'NAS / 网络文件服务器'
    webdav.featureSummary = '直接浏览和播放远程文件'
    webdav.brandKind = 'webdav'
    webdav.iconKind = 'folder'
    webdav.addRoute = 'pages/sources/WebDavSourceEditPage'
    webdav.editRoute = webdav.addRoute
    webdav.browserRoute = 'pages/sources/SourceBrowserPage'
    webdav.capabilities = [ProviderCapability.HOME, ProviderCapability.BROWSE, ProviderCapability.RESUME]
    ProviderCatalog.register(webdav)
    const jellyfin = new ProviderDescriptor()
    jellyfin.type = 'jellyfin'
    jellyfin.displayName = 'Jellyfin'
    jellyfin.category = '更多来源'
    jellyfin.shortDescription = '自托管媒体服务器'
    jellyfin.featureSummary = 'Jellyfin 媒体库支持即将加入'
    jellyfin.brandKind = 'jellyfin'
    jellyfin.comingSoonText = '即将支持'
    jellyfin.enabled = false
    ProviderCatalog.register(jellyfin)
    const smb = new ProviderDescriptor()
    smb.type = 'smb'
    smb.displayName = 'SMB'
    smb.category = '更多来源'
    smb.shortDescription = '局域网文件共享'
    smb.featureSummary = 'SMB 文件夹浏览支持即将加入'
    smb.brandKind = 'smb'
    smb.comingSoonText = '即将支持'
    smb.enabled = false
    ProviderCatalog.register(smb)
    const local = new ProviderDescriptor()
    local.type = 'local'
    local.displayName = '本地媒体'
    local.category = '本地'
    local.description = '浏览应用专属目录中的本地媒体文件。'
    local.iconKind = 'folder'
    local.browserRoute = 'pages/local/FolderPage'
    local.supportsMultipleInstances = false
    local.capabilities = [ProviderCapability.HOME, ProviderCapability.BROWSE, ProviderCapability.RESUME,
      ProviderCapability.ARTWORK]
    ProviderCatalog.register(local)
  }

  private static normalize(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
