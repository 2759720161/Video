export class LocalVideoRecord {
  id: number = -1
  fileKey: string = ''
  fileUri: string = ''
  fileName: string = ''
  fileSize: number = 0
  coverUri: string = ''
  durationMs: number = 0
  positionMs: number = 0
  lastPlayedAt: number = 0
  externalSubtitleFileName: string = ''
  externalSubtitleUri: string = ''
  // Compatibility-only fields for existing saved records. The independent player
  // no longer exposes or persists this feature.
  danmakuFileName: string = ''
  danmakuUri: string = ''
  danmakuOffsetMs: number = 0
  danmakuFormat: string = ''
  danmakuCount: number = 0
  createdAt: number = 0
}
