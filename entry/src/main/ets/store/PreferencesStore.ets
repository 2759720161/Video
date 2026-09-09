import { preferences } from '@kit.ArkData';
import { Logger } from '../utils/Logger';
import { SettingsChangeSignal } from './SettingsChangeSignal';

const logger = new Logger('PreferencesStore');

const PREFS_NAME = 'kazumi_settings';

export class PreferencesStore {
  private prefs: preferences.Preferences | null = null;
  private static instance: PreferencesStore | null = null;
  private static mutationTail: Promise<void> = Promise.resolve();

  private constructor() {}

  static getInstance(): PreferencesStore {
    if (PreferencesStore.instance === null) {
      PreferencesStore.instance = new PreferencesStore();
    }
    return PreferencesStore.instance;
  }

  init(prefs: preferences.Preferences): void {
    this.prefs = prefs;
    logger.info('PreferencesStore initialized');
  }

  private getPrefs(): preferences.Preferences {
    if (this.prefs === null) {
      throw new Error('Preferences not initialized');
    }
    return this.prefs;
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    await PreferencesStore.mutationTail
    try {
      return await this.getPrefs().get(key, defaultValue) as string;
    } catch (err) {
      logger.error('getString failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return defaultValue;
    }
  }

  /** 关键配置读取使用严格模式，底层读取失败必须交给调用方处理。 */
  async getStringStrict(key: string, defaultValue: string = ''): Promise<string> {
    await PreferencesStore.mutationTail
    const value = await this.getPrefs().get(key, defaultValue)
    if (typeof value !== 'string') {
      throw new Error('Preference value is not a string: ' + key)
    }
    return value as string
  }

  async setString(key: string, value: string): Promise<void> {
    return PreferencesStore.enqueueMutation<void>(() => this.setStringInternal(key, value));
  }

  private async setStringInternal(key: string, value: string): Promise<void> {
    try {
      await this.getPrefs().put(key, value);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('setString failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  /** 关键配置使用严格写入，持久化失败必须交给调用方处理。 */
  async setStringStrict(key: string, value: string): Promise<void> {
    return PreferencesStore.enqueueMutation<void>(async () => {
      const prefs = this.getPrefs()
      await prefs.put(key, value)
      await prefs.flush()
      this.notifySettingChanged(key)
    })
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    await PreferencesStore.mutationTail
    try {
      return await this.getPrefs().get(key, defaultValue) as number;
    } catch (err) {
      logger.error('getNumber failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return defaultValue;
    }
  }

  async setNumber(key: string, value: number): Promise<void> {
    return PreferencesStore.enqueueMutation<void>(() => this.setNumberInternal(key, value));
  }

  private async setNumberInternal(key: string, value: number): Promise<void> {
    try {
      await this.getPrefs().put(key, value);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('setNumber failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    await PreferencesStore.mutationTail
    try {
      return await this.getPrefs().get(key, defaultValue) as boolean;
    } catch (err) {
      logger.error('getBoolean failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return defaultValue;
    }
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    return PreferencesStore.enqueueMutation<void>(() => this.setBooleanInternal(key, value));
  }

  private async setBooleanInternal(key: string, value: boolean): Promise<void> {
    try {
      await this.getPrefs().put(key, value);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('setBoolean failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async has(key: string): Promise<boolean> {
    await PreferencesStore.mutationTail
    try {
      return await this.getPrefs().has(key);
    } catch (err) {
      logger.error('has failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return false;
    }
  }

  async delete(key: string): Promise<void> {
    return PreferencesStore.enqueueMutation<void>(() => this.deleteInternal(key));
  }

  private async deleteInternal(key: string): Promise<void> {
    try {
      await this.getPrefs().delete(key);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('delete failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async clear(): Promise<void> {
    return PreferencesStore.enqueueMutation<void>(() => this.clearInternal());
  }

  private async clearInternal(): Promise<void> {
    try {
      await this.getPrefs().clear();
      await this.getPrefs().flush();
      SettingsChangeSignal.notifyDanmakuChanged();
    } catch (err) {
      logger.error('clear failed: %{public}s', JSON.stringify(err));
    }
  }

  private notifySettingChanged(key: string): void {
    if (SettingsChangeSignal.isDanmakuPreferenceKey(key)) {
      SettingsChangeSignal.notifyDanmakuChanged();
    }
  }

  private static enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = PreferencesStore.mutationTail.then(operation, operation)
    PreferencesStore.mutationTail = result.then(() => {}, () => {})
    return result
  }
}
