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
  supportsMultipleInstances: boolean = true
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
