import { DanmakuItem } from '../../models/DanmakuItem'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuFileParser')

export class LocalDanmakuParseResult {
  items: DanmakuItem[] = []
  errorMessage: string = ''
  format: string = ''
}

export class DanmakuFileParser {
  static parse(fileName: string, content: string): LocalDanmakuParseResult {
    const result = new LocalDanmakuParseResult()
    if (content.length === 0) {
      result.errorMessage = '文件内容为空'
      return result
    }

    const ext = DanmakuFileParser.getFileExtension(fileName)
    if (ext === 'xml') {
      result.format = 'bilibili-xml'
      result.items = DanmakuFileParser.parseBilibiliXml(content)
    } else if (ext === 'json') {
      result.format = 'dandan-json'
      result.items = DanmakuFileParser.parseDandanJson(content)
    } else if (ext === 'ass') {
      result.format = 'ass'
      result.items = DanmakuFileParser.parseAssSubtitle(content)
    } else {
      const trimmed = content.trimStart()
      if (trimmed.startsWith('<?xml') || trimmed.startsWith('<')) {
        result.format = 'bilibili-xml'
        result.items = DanmakuFileParser.parseBilibiliXml(content)
      } else if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        result.format = 'dandan-json'
        result.items = DanmakuFileParser.parseDandanJson(content)
      } else if (trimmed.startsWith('[Script Info]') || trimmed.includes('Dialogue:')) {
        result.format = 'ass'
        result.items = DanmakuFileParser.parseAssSubtitle(content)
      } else {
        result.errorMessage = '不支持的弹幕格式'
        return result
      }
    }

    if (result.items.length === 0 && result.errorMessage.length === 0) {
      result.errorMessage = '未解析到有效弹幕'
    }

    logger.info('弹幕文件解析: file=%{public}s, format=%{public}s, count=%{public}d',
      fileName, result.format, result.items.length)
    return result
  }

  static parseBilibiliXml(content: string): DanmakuItem[] {
    const items: DanmakuItem[] = []
    if (content.length === 0) {
      return items
    }

    try {
      const dTagRegex = /<d\s+[^>]*p="([^"]+)"[^>]*>([\s\S]*?)<\/d>/g
      let match: RegExpExecArray | null = null
      while ((match = dTagRegex.exec(content)) !== null) {
        const pValue = match[1]
        const textRaw = match[2]
        const text = DanmakuFileParser.unescapeXml(textRaw)
        if (text.length === 0 || pValue.length === 0) {
          continue
        }

        const parts = pValue.split(',')
        if (parts.length < 4) {
          continue
        }

        const timeSec = parseFloat(parts[0])
        if (isNaN(timeSec)) {
          continue
        }

        const typeValue = parseInt(parts[1], 10)
        const fontSizeValue = parseFloat(parts[2])
        const colorValue = parseInt(parts[3], 10)
        const color = DanmakuFileParser.normalizeColorFromInt(colorValue)
        const fontSize = isNaN(fontSizeValue) ? 25 : fontSizeValue

        const danmakuType = DanmakuFileParser.mapBilibiliType(typeValue)
        items.push(new DanmakuItem(
          text,
          Math.round(timeSec * 1000),
          color,
          fontSize,
          danmakuType,
          'Local'
        ))
      }
    } catch (err) {
      logger.error('B站XML解析异常: %{public}s', err instanceof Error ? err.message : String(err))
    }

    items.sort((a: DanmakuItem, b: DanmakuItem) => a.timeMs - b.timeMs)
    return items
  }

  static parseDandanJson(content: string): DanmakuItem[] {
    const items: DanmakuItem[] = []
    if (content.length === 0) {
      return items
    }

    try {
      const json = JSON.parse(content) as Record<string, Object>
      const comments = json['comments'] as Object[]
      if (comments === null || comments === undefined) {
        return items
      }

      for (let i = 0; i < comments.length; i++) {
        const comment = comments[i] as Record<string, Object>
        const messageValue = String(comment['m'] ?? '')
        if (messageValue.length === 0) {
          continue
        }

        const pValue = String(comment['p'] ?? '')
        if (pValue.length === 0) {
          continue
        }

        const parts = pValue.split(',')
        if (parts.length < 3) {
          continue
        }

        const timeSec = parseFloat(parts[0])
        if (isNaN(timeSec)) {
          continue
        }

        const typeValue = parseInt(parts[1], 10)
        if (isNaN(typeValue)) {
          continue
        }

        const colorValue = parseInt(parts[2], 10)
        const color = DanmakuFileParser.normalizeColorFromInt(colorValue)
        const source = parts.length >= 4 ? parts[3].trim() : 'Local'
        const danmakuType = typeValue === 4 || typeValue === 5 ? typeValue : 0

        items.push(new DanmakuItem(
          messageValue,
          Math.round(timeSec * 1000),
          color,
          25,
          danmakuType,
          source.length > 0 ? source : 'Local'
        ))
      }
    } catch (err) {
      logger.error('弹弹JSON解析异常: %{public}s', err instanceof Error ? err.message : String(err))
    }

    items.sort((a: DanmakuItem, b: DanmakuItem) => a.timeMs - b.timeMs)
    return items
  }

  static parseAssSubtitle(content: string): DanmakuItem[] {
    const items: DanmakuItem[] = []
    if (content.length === 0) {
      return items
    }

    try {
      const lines = content.split('\n')
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim()
        if (!line.startsWith('Dialogue:')) {
          continue
        }

        const colonIndex = line.indexOf(':')
        if (colonIndex < 0) {
          continue
        }

        const fieldsStr = line.substring(colonIndex + 1).trim()
        const fields = fieldsStr.split(',')
        if (fields.length < 10) {
          continue
        }

        const startMs = DanmakuFileParser.parseAssTimestamp(fields[1].trim())
        if (startMs < 0) {
          continue
        }

        let textParts: string[] = []
        for (let j = 9; j < fields.length; j++) {
          textParts.push(fields[j])
        }
        let text = textParts.join(',').trim()
        text = DanmakuFileParser.stripAssTags(text)
        if (text.length === 0) {
          continue
        }

        items.push(new DanmakuItem(
          text,
          startMs,
          '#FFFFFF',
          25,
          0,
          'Local'
        ))
      }
    } catch (err) {
      logger.error('ASS解析异常: %{public}s', err instanceof Error ? err.message : String(err))
    }

    items.sort((a: DanmakuItem, b: DanmakuItem) => a.timeMs - b.timeMs)
    return items
  }

  private static getFileExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return ''
    }
    return fileName.substring(dotIndex + 1).toLowerCase()
  }

  private static mapBilibiliType(typeValue: number): number {
    if (typeValue === 4 || typeValue === 5) {
      return typeValue
    }
    return 0
  }

  private static normalizeColorFromInt(colorInt: number): string {
    if (isNaN(colorInt) || colorInt < 0 || colorInt > 0xFFFFFF) {
      return '#FFFFFF'
    }
    const hex = colorInt.toString(16).padStart(6, '0').toUpperCase()
    return '#' + hex
  }

  private static unescapeXml(text: string): string {
    return text
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&#39;/g, "'")
  }

  private static parseAssTimestamp(ts: string): number {
    if (ts.length === 0) {
      return -1
    }
    const parts = ts.split(':')
    if (parts.length !== 3) {
      return -1
    }
    const h = parseInt(parts[0], 10)
    const m = parseInt(parts[1], 10)
    const sParts = parts[2].split('.')
    const s = parseInt(sParts[0], 10)
    const cs = sParts.length > 1 ? parseInt(sParts[1], 10) : 0
    if (isNaN(h) || isNaN(m) || isNaN(s)) {
      return -1
    }
    return (h * 3600 + m * 60 + s) * 1000 + cs * 10
  }

  private static stripAssTags(text: string): string {
    return text.replace(/\{[^}]*}/g, '').replace(/\\N/g, ' ').replace(/\\n/g, ' ').trim()
  }
}
