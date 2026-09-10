import { ProviderCapability } from '../../core/media/ProviderCapabilities'

export class ProviderRouteParams {
  sourceId: string = ''
  parentId: string = ''
  relativePath: string = ''
  title: string = ''
  view: string = ''
  libraryRoot: boolean = false
  collectionType: string = ''
}

export class ProviderDescriptor {
  type: string = ''
  displayName: string = ''
  category: string = ''
  description: string = ''
  /** Provider Gallery 使用的短用途描述。 */
  shortDescription: string = ''
  /** Provider Gallery 使用的一句话特征摘要。 */
  featureSummary: string = ''
  /** 品牌图标/色彩语义预留给 UI 层，不承载路由逻辑。 */
  brandKind: string = ''
  comingSoonText: string = ''
  iconKind: string = 'media'
  addRoute: string = ''
  editRoute: string = ''
  browserRoute: string = ''
  /** 仅描述该 Provider 是否允许创建多个来源实例。 */
  supportsMultipleInstances: boolean = true
  /** 内置来源与“单实例”无关；内置来源通常不展示用户管理菜单。 */
  builtIn: boolean = false
  /** 用户是否可以删除该 Provider 的来源实例。 */
  userRemovable: boolean = true
  /** 用户是否可以启用或停用该 Provider 的来源实例。 */
  userToggleable: boolean = true
  /** 用户是否可以在来源管理中调整该 Provider 的来源实例顺序。 */
  userReorderable: boolean = true
  enabled: boolean = true
  capabilities: ProviderCapability[] = []

  hasCapability(capability: ProviderCapability): boolean {
    return this.capabilities.indexOf(capability) >= 0
  }

  editParams(sourceId: string): ProviderRouteParams {
    const params = new ProviderRouteParams()
    params.sourceId = sourceId
    return params
  }

  browserParams(sourceId: string): ProviderRouteParams {
    const params = new ProviderRouteParams()
    if (this.type === 'local') {
      params.relativePath = ''
    } else {
      params.sourceId = sourceId
      if (this.type === 'webdav') params.parentId = ''
    }
    return params
  }

  /** 将首页分区标识转换成该 Provider 的浏览路由参数。 */
  sectionParams(sourceId: string, sectionId: string, sectionTitle: string = ''): ProviderRouteParams {
    const params = this.browserParams(sourceId)
    params.title = sectionTitle
    if (this.type === 'emby') {
      if (sectionId === 'latest') {
        params.view = 'latest'
      } else if (sectionId !== 'libraries') {
        params.parentId = sectionId
        params.libraryRoot = true
      }
    } else {
      params.parentId = sectionId
    }
    return params
  }
}
