import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { PreferencesStore } from '../../store/PreferencesStore'

class StoredHeroTone {
  key: string = ''
  tone: string = ''
  expiresAt: number = 0
}

/** Only hashed artwork identities and RGB values are persisted, never authenticated URLs. */
export class HomeHeroPaletteStore {
  private static readonly KEY: string = 'home_hero_palette_v2'
  private static readonly LIMIT: number = 128
  private static readonly TTL: number = 24 * 60 * 60 * 1000
  private static entries: StoredHeroTone[] = []
  private static loading: Promise<void> | null = null
  private static timer: number = -1

  static async identity(artwork: string): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256')
    await digest.update({ data: new util.TextEncoder('utf-8').encodeInto(artwork) })
    const bytes = (await digest.digest()).data
    let key = ''
    for (let i = 0; i < bytes.length; i++) key += bytes[i].toString(16).padStart(2, '0')
    return key
  }

  static async get(key: string): Promise<string> {
    if (HomeHeroPaletteStore.loading === null) HomeHeroPaletteStore.loading = HomeHeroPaletteStore.load()
    await HomeHeroPaletteStore.loading
    return HomeHeroPaletteStore.entries.find((entry: StoredHeroTone) =>
      entry.key === key && entry.expiresAt > Date.now())?.tone ?? ''
  }

  static put(key: string, tone: string): void {
    if (!/^[0-9a-f]{64}$/.test(key) || !/^#[0-9a-f]{6}$/i.test(tone)) return
    HomeHeroPaletteStore.entries = HomeHeroPaletteStore.entries.filter((entry: StoredHeroTone) =>
      entry.key !== key && entry.expiresAt > Date.now())
    const entry = new StoredHeroTone()
    entry.key = key; entry.tone = tone; entry.expiresAt = Date.now() + HomeHeroPaletteStore.TTL
    HomeHeroPaletteStore.entries.push(entry)
    if (HomeHeroPaletteStore.entries.length > HomeHeroPaletteStore.LIMIT) HomeHeroPaletteStore.entries.shift()
    if (HomeHeroPaletteStore.timer >= 0) return
    HomeHeroPaletteStore.timer = setTimeout(() => {
      HomeHeroPaletteStore.timer = -1
      void PreferencesStore.getInstance().setString(HomeHeroPaletteStore.KEY,
        JSON.stringify(HomeHeroPaletteStore.entries)).catch(() => {})
    }, 1000)
  }

  private static async load(): Promise<void> {
    try {
      const raw = await PreferencesStore.getInstance().getString(HomeHeroPaletteStore.KEY, '[]')
      if (raw.length > 32 * 1024) return
      const entries = JSON.parse(raw) as StoredHeroTone[]
      if (!Array.isArray(entries)) return
      HomeHeroPaletteStore.entries = entries.filter((entry: StoredHeroTone) => entry !== null &&
        typeof entry.key === 'string' && /^[0-9a-f]{64}$/.test(entry.key) &&
        typeof entry.tone === 'string' && /^#[0-9a-f]{6}$/i.test(entry.tone) &&
        Number.isFinite(entry.expiresAt) && entry.expiresAt > Date.now() &&
        entry.expiresAt <= Date.now() + HomeHeroPaletteStore.TTL).slice(-HomeHeroPaletteStore.LIMIT)
    } catch (_) {}
  }
}
