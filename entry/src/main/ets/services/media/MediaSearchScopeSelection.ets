import { CatNodeSite } from '../../providers/catvod/CatNodeRuntime'

export class MediaSearchScopeSelection {
  static normalize(keys: string[], scopes: CatNodeSite[]): string[] {
    const selected = new Set<string>(keys)
    const seen = new Set<string>()
    return scopes.filter((site: CatNodeSite) => {
      if (site.searchable === false || !selected.has(site.key) || seen.has(site.key)) return false
      seen.add(site.key); return true
    }).map((site: CatNodeSite) => site.key)
  }

  static decode(text: string, scopes: CatNodeSite[]): string[] {
    if (text.trim().length === 0) return MediaSearchScopeSelection.normalize(scopes.map((site: CatNodeSite) => site.key), scopes)
    try {
      const value = JSON.parse(text) as Object
      if (!Array.isArray(value)) return []
      const keys = (value as Object[]).filter((key: Object) => typeof key === 'string') as string[]
      return MediaSearchScopeSelection.normalize(keys, scopes)
    } catch (_) { return [] }
  }

  static equal(left: string[], right: string[]): boolean {
    return left.length === right.length && left.every((key: string, index: number) => key === right[index])
  }
}
