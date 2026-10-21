import type { CatNodeProvider } from '../../providers/catvod/CatNodeProvider'
import type { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'

/** 首页标题与内容共享同一份来源目录和当前选择。 */
export class CatVodHomeNavigation {
  sourceId: string = ''
  sites: CatNodeSite[] = []
  selectedKey: string = ''
  loading: boolean = true
  heroVisible: boolean = false
  heroSurface: string = ''
  provider: CatNodeProvider | null = null
}
