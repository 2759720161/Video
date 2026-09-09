import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { LocalVideoRecord } from '../models/LocalVideoRecord'
import { MediaItem } from '../core/media/MediaItem'
import { LocalProvider } from '../providers/local/LocalProvider'
import { ProviderPlaybackLauncher } from './ProviderPlaybackLauncher'

/** 本地文件选择/历史入口的应用服务；页面不构造播放器路由载荷。 */
export class LocalPlaybackLauncher {
  static async open(uiContext: UIContext, record: LocalVideoRecord, records: LocalVideoRecord[],
    fromBeginning: boolean = false, replace: boolean = false): Promise<void> {
    try {
      if (record === null || typeof record !== 'object' || Array.isArray(record)) {
        throw new Error('本地视频记录无效')
      }
      const provider = new LocalProvider(uiContext.getHostContext() as common.UIAbilityContext)
      const items: MediaItem[] = []
      let current: MediaItem | null = null
      const currentItem = typeof record.fileUri === 'string' && record.fileUri.length > 0
        ? provider.rememberRecord(record)
        : await provider.getItem(record.fileKey)
      if (currentItem === null) throw new Error('本地视频不存在，请重新选择')
      const sourceRecords: LocalVideoRecord[] = Array.isArray(records) ? records : []
      for (let i = 0; i < sourceRecords.length; i++) {
        const candidate = sourceRecords[i]
        if (candidate === null || typeof candidate !== 'object' || Array.isArray(candidate) ||
          typeof candidate.fileUri !== 'string' || candidate.fileUri.length === 0) continue
        const item = provider.rememberRecord(candidate)
        if (item.id === currentItem.id) {
          // 队列扫描项可能尚未合并历史；当前点击记录保留其续播点、封面和字幕绑定。
          items.push(currentItem)
          current = currentItem
        } else {
          items.push(item)
        }
      }
      await ProviderPlaybackLauncher.openWithProvider(uiContext, provider, current === null ? currentItem : current,
        items, fromBeginning, replace)
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '无法打开视频' })
    }
  }
}
