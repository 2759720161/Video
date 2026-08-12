import { PreferencesStore } from '../../store/PreferencesStore'

export const DANMAKU_PREFS_KEY_BORDER = 'danmakuBorder'
export const DANMAKU_PREFS_KEY_BORDER_SIZE = 'danmakuBorderSize'
export const DANMAKU_PREFS_KEY_COLOR = 'danmakuColor'
export const DANMAKU_PREFS_KEY_FONT_SIZE = 'danmakuFontSize'
export const DANMAKU_PREFS_KEY_FONT_WEIGHT = 'danmakuFontWeight'
export const DANMAKU_PREFS_KEY_OPACITY = 'danmakuOpacity'
export const DANMAKU_PREFS_KEY_SCROLL_DURATION = 'danmakuScrollDuration'
export const DANMAKU_PREFS_KEY_LINE_HEIGHT = 'danmakuLineHeight'
export const DANMAKU_PREFS_KEY_DISPLAY_AREA = 'danmakuDisplayArea'
export const DANMAKU_PREFS_KEY_HIDE_SCROLL = 'danmakuHideScroll'
export const DANMAKU_PREFS_KEY_HIDE_TOP = 'danmakuHideTop'
export const DANMAKU_PREFS_KEY_HIDE_BOTTOM = 'danmakuHideBottom'
export const DANMAKU_PREFS_KEY_HIDE_COLOR = 'danmakuHideColor'
export const DANMAKU_PREFS_KEY_BILIBILI_SOURCE = 'danmakuBiliBiliSource'
export const DANMAKU_PREFS_KEY_GAMER_SOURCE = 'danmakuGamerSource'
export const DANMAKU_PREFS_KEY_DANDAN_SOURCE = 'danmakuDanDanSource'
export const DANMAKU_PREFS_KEY_FOLLOW_SPEED = 'danmakuFollowSpeed'
export const DANMAKU_PREFS_KEY_DEDUPLICATION = 'danmakuDeduplication'
export const DANMAKU_PREFS_KEY_MAX_LENGTH = 'danmakuMaxLength'
export const DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED = 'danmakuBlockKeywordsEnabled'
export const DANMAKU_PREFS_KEY_BLOCK_KEYWORDS = 'danmakuBlockKeywords'
export const DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED = 'danmakuBlockRegexEnabled'
export const DANMAKU_PREFS_KEY_BLOCK_REGEX = 'danmakuBlockRegex'
export const DANMAKU_PREFS_KEY_TIME_OFFSET = 'danmakuTimeOffset'
export const DANMAKU_PREFS_KEY_MASSIVE_MODE = 'danmakuMassiveMode'


const DEFAULT_BORDER = true
const DEFAULT_BORDER_SIZE = 1.5
const DEFAULT_COLOR = true
const DEFAULT_FONT_SIZE = 25
const DEFAULT_FONT_WEIGHT = 4
const DEFAULT_OPACITY = 1.0
const DEFAULT_SCROLL_DURATION = 8
const DEFAULT_LINE_HEIGHT = 1.2
const DEFAULT_DISPLAY_AREA = 1.0
const DEFAULT_HIDE_SCROLL = false
const DEFAULT_HIDE_TOP = false
const DEFAULT_HIDE_BOTTOM = false
const DEFAULT_HIDE_COLOR = false
const DEFAULT_BILIBILI_SOURCE = true
const DEFAULT_GAMER_SOURCE = true
const DEFAULT_DANDAN_SOURCE = true
const DEFAULT_FOLLOW_SPEED = true
const DEFAULT_DEDUPLICATION = false
const DEFAULT_MAX_LENGTH = 100
const DEFAULT_BLOCK_KEYWORDS_ENABLED = true
const DEFAULT_BLOCK_KEYWORDS = ''
const DEFAULT_BLOCK_REGEX_ENABLED = true
const DEFAULT_BLOCK_REGEX = ''
const DEFAULT_TIME_OFFSET = 0.0
const DEFAULT_MASSIVE_MODE = false

const MIN_TIME_OFFSET = -60.0
const MAX_TIME_OFFSET = 60.0
const TIME_OFFSET_STEP = 0.25
const MAX_BLOCK_TEXT_LENGTH = 4000

export class DanmakuStyleSettings {
  border: boolean = DEFAULT_BORDER
  borderSize: number = DEFAULT_BORDER_SIZE
  useSourceColor: boolean = DEFAULT_COLOR
  fontSize: number = DEFAULT_FONT_SIZE
  fontWeight: number = DEFAULT_FONT_WEIGHT
  opacity: number = DEFAULT_OPACITY
  scrollDurationSec: number = DEFAULT_SCROLL_DURATION
  lineHeight: number = DEFAULT_LINE_HEIGHT
  displayArea: number = DEFAULT_DISPLAY_AREA
  hideScroll: boolean = DEFAULT_HIDE_SCROLL
  hideTop: boolean = DEFAULT_HIDE_TOP
  hideBottom: boolean = DEFAULT_HIDE_BOTTOM
  hideColor: boolean = DEFAULT_HIDE_COLOR
  biliBiliSource: boolean = DEFAULT_BILIBILI_SOURCE
  gamerSource: boolean = DEFAULT_GAMER_SOURCE
  danDanSource: boolean = DEFAULT_DANDAN_SOURCE
  followSpeed: boolean = DEFAULT_FOLLOW_SPEED
  deduplication: boolean = DEFAULT_DEDUPLICATION
  maxLength: number = DEFAULT_MAX_LENGTH
  blockKeywordsEnabled: boolean = DEFAULT_BLOCK_KEYWORDS_ENABLED
  blockKeywordsText: string = DEFAULT_BLOCK_KEYWORDS
  blockRegexEnabled: boolean = DEFAULT_BLOCK_REGEX_ENABLED
  blockRegexText: string = DEFAULT_BLOCK_REGEX
  danmakuTimeOffset: number = DEFAULT_TIME_OFFSET
  massiveMode: boolean = DEFAULT_MASSIVE_MODE


  static async load(): Promise<DanmakuStyleSettings> {
    const prefs = PreferencesStore.getInstance()
    const settings = new DanmakuStyleSettings()
    settings.border = await prefs.getBoolean(DANMAKU_PREFS_KEY_BORDER, DEFAULT_BORDER)
    settings.borderSize = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_BORDER_SIZE, DEFAULT_BORDER_SIZE), 0.1, 3.0)
    settings.useSourceColor = await prefs.getBoolean(DANMAKU_PREFS_KEY_COLOR, DEFAULT_COLOR)
    settings.fontSize = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_FONT_SIZE, DEFAULT_FONT_SIZE), 10, 48)
    settings.fontWeight = Math.floor(DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_FONT_WEIGHT, DEFAULT_FONT_WEIGHT), 1, 9))
    settings.opacity = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_OPACITY, DEFAULT_OPACITY), 0.1, 1.0)
    settings.scrollDurationSec = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_SCROLL_DURATION, DEFAULT_SCROLL_DURATION), 4, 12)
    settings.lineHeight = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_LINE_HEIGHT, DEFAULT_LINE_HEIGHT), 1.0, 2.5)
    settings.displayArea = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_DISPLAY_AREA, DEFAULT_DISPLAY_AREA), 0.25, 1.0)
    settings.hideScroll = await prefs.getBoolean(DANMAKU_PREFS_KEY_HIDE_SCROLL, DEFAULT_HIDE_SCROLL)
    settings.hideTop = await prefs.getBoolean(DANMAKU_PREFS_KEY_HIDE_TOP, DEFAULT_HIDE_TOP)
    settings.hideBottom = await prefs.getBoolean(DANMAKU_PREFS_KEY_HIDE_BOTTOM, DEFAULT_HIDE_BOTTOM)
    settings.hideColor = await prefs.getBoolean(DANMAKU_PREFS_KEY_HIDE_COLOR, DEFAULT_HIDE_COLOR)
    settings.biliBiliSource = await prefs.getBoolean(DANMAKU_PREFS_KEY_BILIBILI_SOURCE, DEFAULT_BILIBILI_SOURCE)
    settings.gamerSource = await prefs.getBoolean(DANMAKU_PREFS_KEY_GAMER_SOURCE, DEFAULT_GAMER_SOURCE)
    settings.danDanSource = await prefs.getBoolean(DANMAKU_PREFS_KEY_DANDAN_SOURCE, DEFAULT_DANDAN_SOURCE)
    settings.followSpeed = await prefs.getBoolean(DANMAKU_PREFS_KEY_FOLLOW_SPEED, DEFAULT_FOLLOW_SPEED)
    settings.deduplication = await prefs.getBoolean(DANMAKU_PREFS_KEY_DEDUPLICATION, DEFAULT_DEDUPLICATION)
    settings.maxLength = Math.floor(DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_MAX_LENGTH, DEFAULT_MAX_LENGTH), 20, 200))
    settings.blockKeywordsEnabled = await prefs.getBoolean(
      DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED, DEFAULT_BLOCK_KEYWORDS_ENABLED)
    settings.blockKeywordsText = DanmakuStyleSettings.clampText(
      await prefs.getString(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS, DEFAULT_BLOCK_KEYWORDS))
    settings.blockRegexEnabled = await prefs.getBoolean(
      DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED, DEFAULT_BLOCK_REGEX_ENABLED)
    settings.blockRegexText = DanmakuStyleSettings.clampText(
      await prefs.getString(DANMAKU_PREFS_KEY_BLOCK_REGEX, DEFAULT_BLOCK_REGEX))
    settings.danmakuTimeOffset = DanmakuStyleSettings.clampNumber(
      await prefs.getNumber(DANMAKU_PREFS_KEY_TIME_OFFSET, DEFAULT_TIME_OFFSET), MIN_TIME_OFFSET, MAX_TIME_OFFSET)
    settings.massiveMode = await prefs.getBoolean(DANMAKU_PREFS_KEY_MASSIVE_MODE, DEFAULT_MASSIVE_MODE)

    return settings
  }

  static async reset(): Promise<void> {
    const prefs = PreferencesStore.getInstance()
    await prefs.delete(DANMAKU_PREFS_KEY_BORDER)
    await prefs.delete(DANMAKU_PREFS_KEY_BORDER_SIZE)
    await prefs.delete(DANMAKU_PREFS_KEY_COLOR)
    await prefs.delete(DANMAKU_PREFS_KEY_FONT_SIZE)
    await prefs.delete(DANMAKU_PREFS_KEY_FONT_WEIGHT)
    await prefs.delete(DANMAKU_PREFS_KEY_OPACITY)
    await prefs.delete(DANMAKU_PREFS_KEY_SCROLL_DURATION)
    await prefs.delete(DANMAKU_PREFS_KEY_LINE_HEIGHT)
    await prefs.delete(DANMAKU_PREFS_KEY_DISPLAY_AREA)
    await prefs.delete(DANMAKU_PREFS_KEY_HIDE_SCROLL)
    await prefs.delete(DANMAKU_PREFS_KEY_HIDE_TOP)
    await prefs.delete(DANMAKU_PREFS_KEY_HIDE_BOTTOM)
    await prefs.delete(DANMAKU_PREFS_KEY_HIDE_COLOR)
    await prefs.delete(DANMAKU_PREFS_KEY_BILIBILI_SOURCE)
    await prefs.delete(DANMAKU_PREFS_KEY_GAMER_SOURCE)
    await prefs.delete(DANMAKU_PREFS_KEY_DANDAN_SOURCE)
    await prefs.delete(DANMAKU_PREFS_KEY_FOLLOW_SPEED)
    await prefs.delete(DANMAKU_PREFS_KEY_DEDUPLICATION)
    await prefs.delete(DANMAKU_PREFS_KEY_MAX_LENGTH)
    await prefs.delete(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED)
    await prefs.delete(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS)
    await prefs.delete(DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED)
    await prefs.delete(DANMAKU_PREFS_KEY_BLOCK_REGEX)
    await prefs.delete(DANMAKU_PREFS_KEY_TIME_OFFSET)
    await prefs.delete(DANMAKU_PREFS_KEY_MASSIVE_MODE)

  }

  static getDefault(): DanmakuStyleSettings {
    return new DanmakuStyleSettings()
  }

  private static clampNumber(value: number, min: number, max: number): number {
    if (value < min) {
      return min
    }
    if (value > max) {
      return max
    }
    return value
  }

  static clampText(value: string): string {
    if (value.length > MAX_BLOCK_TEXT_LENGTH) {
      return value.substring(0, MAX_BLOCK_TEXT_LENGTH)
    }
    return value
  }
}
