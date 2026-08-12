export const DANMAKU_SETTINGS_VERSION_KEY = 'danmakuSettingsVersion'
export const RULE_SOURCE_VERSION_KEY = 'ruleSourceVersion'

export class SettingsChangeSignal {
  private static danmakuVersion: number = 0
  private static ruleSourceVersion: number = 0

  static initDanmakuVersion(): void {
    SettingsChangeSignal.danmakuVersion = 0
    SettingsChangeSignal.setNumber(DANMAKU_SETTINGS_VERSION_KEY, SettingsChangeSignal.danmakuVersion)
    SettingsChangeSignal.ruleSourceVersion = 0
    SettingsChangeSignal.setNumber(RULE_SOURCE_VERSION_KEY, SettingsChangeSignal.ruleSourceVersion)
  }

  static notifyDanmakuChanged(): void {
    const now = Date.now()
    SettingsChangeSignal.danmakuVersion = Math.max(SettingsChangeSignal.danmakuVersion + 1, now)
    SettingsChangeSignal.setNumber(DANMAKU_SETTINGS_VERSION_KEY, SettingsChangeSignal.danmakuVersion)
  }

  static notifyRuleSourceChanged(): void {
    const now = Date.now()
    SettingsChangeSignal.ruleSourceVersion = Math.max(SettingsChangeSignal.ruleSourceVersion + 1, now)
    SettingsChangeSignal.setNumber(RULE_SOURCE_VERSION_KEY, SettingsChangeSignal.ruleSourceVersion)
  }

  static isDanmakuPreferenceKey(key: string): boolean {
    return key.indexOf('danmaku') === 0 || key.indexOf('dandan_') === 0
  }

  private static setNumber(key: string, value: number): void {
    if (!AppStorage.set<number>(key, value)) {
      AppStorage.setOrCreate<number>(key, value)
    }
  }

}
