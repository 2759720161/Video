import { PreferencesStore } from './PreferencesStore'
import { MediaSourceStore } from './MediaSourceStore'
import { HomeSourcePolicy } from '../services/library/HomeSourcePolicy'

export const ACTIVE_HOME_SOURCE_KEY: string = 'activeHomeSourceId'

export class ActiveSourceStore {
  private static tail: Promise<void> = Promise.resolve()

  static async restore(): Promise<string> {
    let result = ''
    const task = ActiveSourceStore.tail.then(async () => {
      const saved = await PreferencesStore.getInstance().getStringStrict(ACTIVE_HOME_SOURCE_KEY, 'local')
      result = HomeSourcePolicy.resolve(saved, await MediaSourceStore.getAllStrict())
      if (result.length === 0) throw new Error('没有可用的首页服务')
      // A successful strict read distinguishes removal/disable from storage failure.
      if (result !== saved) await PreferencesStore.getInstance().setStringStrict(ACTIVE_HOME_SOURCE_KEY, result)
      AppStorage.setOrCreate(ACTIVE_HOME_SOURCE_KEY, result)
    })
    ActiveSourceStore.tail = task.catch(() => {})
    await task
    return result
  }

  static async select(sourceId: string): Promise<void> {
    const task = ActiveSourceStore.tail.then(async () => {
      const source = await MediaSourceStore.getById(sourceId)
      if (source === null || !HomeSourcePolicy.canSelect(source)) throw new Error('服务不可用或已停用')
      await PreferencesStore.getInstance().setStringStrict(ACTIVE_HOME_SOURCE_KEY, source.id)
      AppStorage.setOrCreate(ACTIVE_HOME_SOURCE_KEY, source.id)
    })
    ActiveSourceStore.tail = task.catch(() => {})
    return task
  }
}
