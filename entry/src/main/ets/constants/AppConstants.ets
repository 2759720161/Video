import { APP_VERSION as GENERATED_APP_VERSION } from './AppVersion'

export class AppConstants {
  static readonly APP_NAME: string = '影匣'
  static readonly APP_VERSION: string = GENERATED_APP_VERSION
  static readonly DOMAIN: number = 0x0000
  static readonly LOG_TAG: string = 'LocalPlayer'

  static readonly DEFAULT_TIMEOUT_MS: number = 10000
  static readonly SNIFFER_TIMEOUT_MS: number = 15000
  static readonly SNIFFER_MAX_RETRY: number = 2
  static readonly DEFAULT_SPEED: number = 1.0
  static readonly DEFAULT_VOLUME: number = 1.0
  static readonly MAX_CONCURRENT_REQUESTS: number = 10
  static readonly MAX_RETRY_COUNT: number = 3
  static readonly RETRY_BASE_DELAY_MS: number = 1000
  static readonly SUPPORTED_API_LEVEL: number = 8

  static readonly SEARCH_KEYWORD_PLACEHOLDER: string = '@keyword'
  static readonly M3U8_HEADER: string = '#EXTM3U'

  static readonly VIDEO_EXTENSIONS: string[] = ['.m3u8', '.mp4', '.flv', '.ts']
  static readonly AD_DOMAINS: string[] = [
    'ad.example.com',
    'ads.example.com',
    'tracking.example.com'
  ]
}
