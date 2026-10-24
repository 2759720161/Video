import type { EmbyItem } from '../../providers/emby/EmbyModels'

export class MediaSearchItem {
  id: string = ''
  title: string = ''
  subtitle: string = ''
  overview: string = ''
  artworkUrl: string = ''
  sourceName: string = ''
  year: number = 0
  embyItem: EmbyItem | null = null
}

export class MediaSearchPage {
  items: MediaSearchItem[] = []
  page: number = 1
  pageCount: number = 1
}

export class MediaSearchPresentation {
  static normalize(value: string): string { return value.trim().replace(/\s+/g, ' ').slice(0, 255) }

  static history(text: string): string[] {
    try {
      const parsed = JSON.parse(text) as Object
      if (!Array.isArray(parsed)) return []
      const values = parsed as Object[]
      const result: string[] = []
      for (let i = 0; i < values.length; i++) {
        if (typeof values[i] !== 'string') continue
        const word = MediaSearchPresentation.normalize(values[i] as string)
        if (word.length > 0 && !result.includes(word)) result.push(word)
        if (result.length === 20) break
      }
      return result
    } catch (_) { return [] }
  }

  static remember(history: string[], value: string): string[] {
    const word = MediaSearchPresentation.normalize(value)
    return word.length > 0 ? [word, ...history.filter((entry: string) => entry !== word)].slice(0, 20) : history.slice()
  }

  static merge(previous: MediaSearchItem[], incoming: MediaSearchItem[]): MediaSearchItem[] {
    const result = previous.slice()
    const seen = new Set(previous.map((item: MediaSearchItem) => item.id))
    for (let i = 0; i < incoming.length; i++) {
      const item = incoming[i]
      if (item.id.length === 0 || item.title.trim().length === 0 || seen.has(item.id)) continue
      result.push(item); seen.add(item.id)
    }
    return result
  }

  static sorted(items: MediaSearchItem[], order: string): MediaSearchItem[] {
    const result = items.slice()
    if (order === 'title') result.sort((a: MediaSearchItem, b: MediaSearchItem) => a.title.localeCompare(b.title))
    else if (order === 'year') result.sort((a: MediaSearchItem, b: MediaSearchItem) => b.year - a.year)
    return result
  }

  static width(value: number): number { return Number.isFinite(value) && value >= 240 ? Math.min(1200, value) : 360 }
  static columns(width: number): number { return Math.max(2, Math.min(6, Math.floor((MediaSearchPresentation.width(width) - 28) / 108))) }
  static cardWidth(width: number): number {
    const columns = MediaSearchPresentation.columns(width)
    return Math.floor((MediaSearchPresentation.width(width) - 40 - 12 * (columns - 1)) / columns * 100) / 100
  }
}
