import { PreferencesStore } from '../../store/PreferencesStore'
import { SourceCredential } from './SourceCredential'
import { huks } from '@kit.UniversalKeystoreKit'
import { buffer, util } from '@kit.ArkTS'

const CREDENTIAL_KEY_PREFIX: string = 'secureCredentialV2:'
const HUKS_KEY_ALIAS: string = 'video-source-credential-key-v2'
const HUKS_ENVELOPE_PREFIX: string = 'huks1:'

/**
 * 凭据存储边界。
 *
 * 业务层只能通过本接口读取敏感字段，来源 configJson 永远不应包含这些字段。
 * 密文落在应用私有 Preferences 中，实际加解密密钥由系统 HUKS 管理，
 * Preferences 本身不再保存可直接读取的凭据明文。
 */
export class SecureCredentialStore {
  private static instance: SecureCredentialStore | null = null
  private mutationTail: Promise<void> = Promise.resolve()

  private constructor() {}

  static getInstance(): SecureCredentialStore {
    if (SecureCredentialStore.instance === null) {
      SecureCredentialStore.instance = new SecureCredentialStore()
    }
    return SecureCredentialStore.instance
  }

  async get(sourceId: string): Promise<SourceCredential | null> {
    const normalizedId = SecureCredentialStore.normalizeText(sourceId)
    if (normalizedId.length === 0) return null
    const raw = await PreferencesStore.getInstance().getString(this.key(normalizedId), '')
    if (raw.startsWith(HUKS_ENVELOPE_PREFIX)) {
      try {
        const encrypted = SecureCredentialStore.fromBase64(raw.substring(HUKS_ENVELOPE_PREFIX.length))
        const plain = await this.crypt(encrypted, false)
        return SecureCredentialStore.decode(SecureCredentialStore.bytesToString(plain), normalizedId)
      } catch (_) {
        return null
      }
    }
    // V1/V2 早期实现兼容读取；成功读取后立即回写密文，避免旧明文长期留存。
    const legacy = SecureCredentialStore.decode(raw, normalizedId)
    if (legacy !== null) {
      this.set(legacy).catch((_err: Error) => {})
    }
    return legacy
  }

  async set(credential: SourceCredential): Promise<void> {
    const snapshot = credential.copy()
    const sourceId = SecureCredentialStore.normalizeText(snapshot.sourceId)
    const providerType = SecureCredentialStore.normalizeText(snapshot.providerType).toLowerCase()
    if (sourceId.length === 0 || providerType.length === 0) {
      throw new Error('Invalid source credential')
    }
    snapshot.sourceId = sourceId
    snapshot.providerType = providerType
    const values: Record<string, string> = {}
    const keys = Object.keys(snapshot.values)
    for (let i = 0; i < keys.length; i++) {
      const key = SecureCredentialStore.normalizeText(keys[i])
      const value = snapshot.values[keys[i]]
      if (key.length > 0 && typeof value === 'string') values[key] = value
    }
    snapshot.values = values
    return this.enqueue(async () => {
      const encrypted = await this.crypt(SecureCredentialStore.stringToBytes(JSON.stringify(snapshot)), true)
      await PreferencesStore.getInstance().setStringStrict(this.key(sourceId),
        HUKS_ENVELOPE_PREFIX + SecureCredentialStore.toBase64(encrypted))
    })
  }

  async delete(sourceId: string): Promise<void> {
    const normalizedId = SecureCredentialStore.normalizeText(sourceId)
    if (normalizedId.length === 0) return
    return this.enqueue(async () => {
      await PreferencesStore.getInstance().delete(this.key(normalizedId))
    })
  }

  private key(sourceId: string): string {
    return CREDENTIAL_KEY_PREFIX + sourceId
  }

  private async enqueue(operation: () => Promise<void>): Promise<void> {
    const result = this.mutationTail.then(operation, operation)
    this.mutationTail = result.then(() => {}, () => {})
    return result
  }

  private async ensureKey(): Promise<void> {
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_ECB }
    ]
    try {
      await huks.generateKeyItem(HUKS_KEY_ALIAS, { properties: properties, inData: new Uint8Array(0) })
    } catch (_) {
      // Existing key is expected on all subsequent launches. Other failures
      // are surfaced by initSession so callers never silently store plaintext.
    }
  }

  private async crypt(data: Uint8Array, encrypt: boolean): Promise<Uint8Array> {
    await this.ensureKey()
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: encrypt ?
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT : huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_ECB }
    ]
    const options: huks.HuksOptions = { properties: properties, inData: new Uint8Array(0) }
    const session = await huks.initSession(HUKS_KEY_ALIAS, options)
    try {
      const updated = await huks.updateSession(session.handle, { properties: properties, inData: data })
      const finished = await huks.finishSession(session.handle, { properties: properties, inData: new Uint8Array(0) })
      return SecureCredentialStore.concat(updated.outData ?? new Uint8Array(0), finished.outData ?? new Uint8Array(0))
    } catch (err) {
      await huks.abortSession(session.handle, options).catch((_abortErr: Error) => {})
      throw new Error(err instanceof Error ? err.message : String(err))
    }
  }

  private static stringToBytes(value: string): Uint8Array {
    return new Uint8Array(buffer.from(value, 'utf-8').buffer)
  }

  private static bytesToString(value: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(value)
  }

  private static concat(left: Uint8Array, right: Uint8Array): Uint8Array {
    const result = new Uint8Array(left.length + right.length)
    result.set(left, 0)
    result.set(right, left.length)
    return result
  }

  private static toBase64(bytes: Uint8Array): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let result = ''
    for (let i = 0; i < bytes.length; i += 3) {
      const first = bytes[i]
      const second = i + 1 < bytes.length ? bytes[i + 1] : -1
      const third = i + 2 < bytes.length ? bytes[i + 2] : -1
      result += alphabet.charAt(first >> 2)
      result += alphabet.charAt(((first & 3) << 4) | (second < 0 ? 0 : second >> 4))
      result += second < 0 ? '=' : alphabet.charAt(((second & 15) << 2) | (third < 0 ? 0 : third >> 6))
      result += third < 0 ? '=' : alphabet.charAt(third & 63)
    }
    return result
  }

  private static fromBase64(value: string): Uint8Array {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const bytes: number[] = []
    let bufferValue = 0
    let bits = 0
    for (let i = 0; i < value.length; i++) {
      const index = alphabet.indexOf(value.charAt(i))
      if (index < 0) continue
      bufferValue = (bufferValue << 6) | index
      bits += 6
      if (bits >= 8) {
        bits -= 8
        bytes.push((bufferValue >> bits) & 255)
      }
    }
    return new Uint8Array(bytes)
  }

  private static decode(raw: string, sourceId: string): SourceCredential | null {
    if (typeof raw !== 'string' || raw.length === 0) return null
    try {
      const parsed = JSON.parse(raw) as Object
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null
      const value = parsed as Record<string, Object>
      const credential = new SourceCredential()
      credential.sourceId = SecureCredentialStore.normalizeText(sourceId)
      credential.providerType = SecureCredentialStore.readString(value, 'providerType').trim().toLowerCase()
      const rawValues = value['values']
      if (rawValues === null || typeof rawValues !== 'object' || Array.isArray(rawValues)) return null
      const entries = rawValues as Record<string, Object>
      const keys = Object.keys(entries)
      for (let i = 0; i < keys.length; i++) {
        const key = SecureCredentialStore.normalizeText(keys[i])
        const entry = entries[keys[i]]
        if (key.length > 0 && typeof entry === 'string') credential.values[key] = entry as string
      }
      return credential.providerType.length > 0 ? credential : null
    } catch (_) {
      return null
    }
  }

  private static readString(value: Record<string, Object>, key: string): string {
    return typeof value[key] === 'string' ? value[key] as string : ''
  }

  private static normalizeText(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
