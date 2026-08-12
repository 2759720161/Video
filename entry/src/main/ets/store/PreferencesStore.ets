import { preferences } from '@kit.ArkData';
import { Logger } from '../utils/Logger';
import { SettingsChangeSignal } from './SettingsChangeSignal';

const logger = new Logger('PreferencesStore');

const PREFS_NAME = 'kazumi_settings';

export class PreferencesStore {
  private prefs: preferences.Preferences | null = null;
  private static instance: PreferencesStore | null = null;

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
    try {
      return await this.getPrefs().get(key, defaultValue) as string;
    } catch (err) {
      logger.error('getString failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return defaultValue;
    }
  }

  async setString(key: string, value: string): Promise<void> {
    try {
      await this.getPrefs().put(key, value);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('setString failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    try {
      return await this.getPrefs().get(key, defaultValue) as number;
    } catch (err) {
      logger.error('getNumber failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return defaultValue;
    }
  }

  async setNumber(key: string, value: number): Promise<void> {
    try {
      await this.getPrefs().put(key, value);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('setNumber failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    try {
      return await this.getPrefs().get(key, defaultValue) as boolean;
    } catch (err) {
      logger.error('getBoolean failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return defaultValue;
    }
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    try {
      await this.getPrefs().put(key, value);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('setBoolean failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async has(key: string): Promise<boolean> {
    try {
      return await this.getPrefs().has(key);
    } catch (err) {
      logger.error('has failed for %{public}s: %{public}s', key, JSON.stringify(err));
      return false;
    }
  }

  async delete(key: string): Promise<void> {
    try {
      await this.getPrefs().delete(key);
      await this.getPrefs().flush();
      this.notifySettingChanged(key);
    } catch (err) {
      logger.error('delete failed for %{public}s: %{public}s', key, JSON.stringify(err));
    }
  }

  async clear(): Promise<void> {
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
}
