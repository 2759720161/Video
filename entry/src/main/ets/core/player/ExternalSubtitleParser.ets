import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

export class ExternalSubtitleCue {
  startMs: number = 0
  endMs: number = 0
  text: string = ''
}

/**
 * External subtitle fallback for native renderers that cannot reopen
 * HarmonyOS file-provider paths. It deliberately handles the text subtitle
 * formats selected by the app and leaves bitmap subtitles to the media file.
 */
export class ExternalSubtitleParser {
  static load(path: string): ExternalSubtitleCue[] {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    try {
      const size = fileIo.statSync(file.fd).size
      if (size <= 0 || size > 20 * 1024 * 1024) {
        return []
      }
      const buffer = new ArrayBuffer(size)
      fileIo.readSync(file.fd, buffer)
      const content = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer))
      return ExternalSubtitleParser.parse(content)
    } finally {
      fileIo.closeSync(file)
    }
  }

  static parse(content: string): ExternalSubtitleCue[] {
    const normalized = content.replace(/\r/g, '').replace(/^\uFEFF/, '')
    const lower = normalized.toLowerCase()
    const cues = lower.indexOf('[events]') >= 0 || lower.indexOf('dialogue:') >= 0 ?
      ExternalSubtitleParser.parseAss(normalized) : ExternalSubtitleParser.parseTimedText(normalized)
    cues.sort((first: ExternalSubtitleCue, second: ExternalSubtitleCue): number => first.startMs - second.startMs)
    return cues
  }

  static textAt(cues: ExternalSubtitleCue[], positionMs: number): string {
    const lines: string[] = []
    for (let i = 0; i < cues.length; i++) {
      const cue = cues[i]
      if (cue.startMs <= positionMs && positionMs < cue.endMs && cue.text.length > 0) {
        lines.push(cue.text)
      }
    }
    return lines.join('\n')
  }

  private static parseTimedText(content: string): ExternalSubtitleCue[] {
    const cues: ExternalSubtitleCue[] = []
    const blocks = content.split('\n\n')
    for (let i = 0; i < blocks.length; i++) {
      const lines = blocks[i].split('\n')
      let timeIndex = -1
      for (let j = 0; j < lines.length; j++) {
        if (lines[j].indexOf('-->') >= 0) {
          timeIndex = j
          break
        }
      }
      if (timeIndex < 0) {
        continue
      }
      const timestamps = lines[timeIndex].split('-->')
      if (timestamps.length < 2) {
        continue
      }
      const startMs = ExternalSubtitleParser.parseTimestamp(timestamps[0].trim())
      const endToken = timestamps[1].trim().split(' ')[0]
      const endMs = ExternalSubtitleParser.parseTimestamp(endToken)
      const textLines: string[] = []
      for (let j = timeIndex + 1; j < lines.length; j++) {
        const line = lines[j].trim()
        if (line.length > 0) {
          textLines.push(ExternalSubtitleParser.stripHtmlTags(line))
        }
      }
      ExternalSubtitleParser.appendCue(cues, startMs, endMs, textLines.join('\n'))
    }
    return cues
  }

  private static parseAss(content: string): ExternalSubtitleCue[] {
    const cues: ExternalSubtitleCue[] = []
    const lines = content.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (!line.toLowerCase().startsWith('dialogue:')) {
        continue
      }
      const fields = ExternalSubtitleParser.splitAssDialogue(line.substring(line.indexOf(':') + 1))
      if (fields.length < 3) {
        continue
      }
      const startMs = ExternalSubtitleParser.parseAssTimestamp(fields[1])
      const endMs = ExternalSubtitleParser.parseAssTimestamp(fields[2])
      const text = ExternalSubtitleParser.stripAssTags(fields[fields.length - 1])
      ExternalSubtitleParser.appendCue(cues, startMs, endMs, text)
    }
    return cues
  }

  /** ASS dialogue has nine commas before the text field, whose text may itself contain commas. */
  private static splitAssDialogue(value: string): string[] {
    const fields: string[] = []
    let start = 0
    for (let i = 0; i < value.length; i++) {
      if (value.charAt(i) === ',' && fields.length < 9) {
        fields.push(value.substring(start, i).trim())
        start = i + 1
      }
    }
    fields.push(value.substring(start).trim())
    return fields
  }

  private static appendCue(cues: ExternalSubtitleCue[], startMs: number, endMs: number, text: string): void {
    if (startMs < 0 || endMs <= startMs || text.length === 0) {
      return
    }
    const cue = new ExternalSubtitleCue()
    cue.startMs = startMs
    cue.endMs = endMs
    cue.text = text
    cues.push(cue)
  }

  private static parseTimestamp(value: string): number {
    const match = value.match(/^(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})$/)
    if (match === null) {
      return -1
    }
    const fraction = match[4].length === 1 ? Number(match[4]) * 100 :
      match[4].length === 2 ? Number(match[4]) * 10 : Number(match[4])
    return Number(match[1]) * 3600000 + Number(match[2]) * 60000 + Number(match[3]) * 1000 + fraction
  }

  private static parseAssTimestamp(value: string): number {
    const match = value.match(/^(\d{1,2}):(\d{2}):(\d{2})[.](\d{1,2})$/)
    if (match === null) {
      return -1
    }
    const fraction = match[4].length === 1 ? Number(match[4]) * 100 : Number(match[4]) * 10
    return Number(match[1]) * 3600000 + Number(match[2]) * 60000 + Number(match[3]) * 1000 + fraction
  }

  private static stripAssTags(value: string): string {
    return value.replace(/\{[^}]*\}/g, '').replace(/\\N|\\n/g, '\n').replace(/\\h/g, ' ').trim()
  }

  private static stripHtmlTags(value: string): string {
    return value.replace(/<[^>]*>/g, '').trim()
  }
}
