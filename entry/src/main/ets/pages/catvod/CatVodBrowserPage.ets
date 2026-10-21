import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'
import { MediaSourceStore } from '../../store/MediaSourceStore'
import { PageLoadingState } from '../../components/common/PageLoadingState'
import { PageErrorState } from '../../components/common/PageErrorState'
import { CatVodContent } from './CatVodContent'
import { buildTitleBarOptions, HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'

@Entry
@Component
struct CatVodBrowserPage {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) materialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State private source: MediaSourceInstance | null = null
  @State private error: string = ''
  private alive: boolean = true
  private scroller: Scroller = new Scroller()
  aboutToAppear(): void { this.alive = true; void this.load() }
  aboutToDisappear(): void { this.alive = false }

  private async load(): Promise<void> {
    this.error = ''
    try {
      const params = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined
      const id = params !== undefined && typeof params['sourceId'] === 'string' ? params['sourceId'] as string : ''
      const source = await MediaSourceStore.getById(id)
      if (!this.alive) return
      if (source === null || !source.enabled || !['catvod', 'catnode'].includes(source.providerType)) throw new Error('猫源不可用或已停用')
      this.source = source
    } catch (err) { if (this.alive) this.error = err instanceof Error ? err.message : '读取来源失败' }
  }

  build() {
    HdsNavigation() {
      if (this.error.length > 0) PageErrorState({ title: '来源暂不可用', message: this.error, onRetry: () => { void this.load() } })
      else if (this.source === null) PageLoadingState({ title: '正在读取来源', minHeight: 300 })
      else CatVodContent({ source: this.source, scroller: this.scroller })
    }.width('100%').height('100%').mode(NavigationMode.Stack)
      .titleBar(buildTitleBarOptions(this.source?.name ?? '猫源', this.materialLevel))
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).backgroundColor(Color.Transparent)
      .bindToScrollable([this.scroller])
  }
}
