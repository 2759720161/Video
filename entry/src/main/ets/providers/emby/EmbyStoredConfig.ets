/** Emby 来源的非敏感持久化字段。accessToken 只允许进入 SecureCredentialStore。 */
export class EmbyStoredConfig {
  baseUrl: string = ''
  serverId: string = ''
  serverName: string = ''
  serverVersion: string = ''
  userId: string = ''
  userName: string = ''
  deviceId: string = ''
}
