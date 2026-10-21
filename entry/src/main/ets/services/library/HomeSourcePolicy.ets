import { MediaSourceInstance } from '../../core/media/MediaSourceInstance'

/** Selection depends on instance identity and availability, never on network health. */
export class HomeSourcePolicy {
  /** The built-in local row is not an added service until its dedicated folder exists. */
  static hasAddedService(sources: MediaSourceInstance[], localFolderExists: boolean): boolean {
    return localFolderExists || sources.some((source: MediaSourceInstance) =>
      source.id !== 'local' && source.providerType !== 'local')
  }

  static canSelect(source: MediaSourceInstance): boolean {
    return source.enabled && (source.providerType === 'local' || source.providerType === 'emby' ||
      source.providerType === 'webdav' || source.providerType === 'catvod' || source.providerType === 'catnode')
  }

  static resolve(selectedId: string, sources: MediaSourceInstance[]): string {
    const selected = sources.find((source: MediaSourceInstance) => source.id === selectedId)
    if (selected !== undefined && HomeSourcePolicy.canSelect(selected)) return selected.id
    const local = sources.find((source: MediaSourceInstance) => source.id === 'local')
    return local !== undefined && HomeSourcePolicy.canSelect(local) ? 'local' : ''
  }
}
