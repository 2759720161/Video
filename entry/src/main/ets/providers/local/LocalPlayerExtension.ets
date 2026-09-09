import { common } from '@kit.AbilityKit'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalPlaybackLauncher } from '../../services/LocalPlaybackLauncher'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'

/** 页面可选的本地播放扩展返回值，不把 LocalVideoRecord 暴露给播放器页面。 */
export class LocalSubtitleBinding {
  fileName: string = ''
  uri: string = ''
}

export class LocalHistoryUpdate {
  videoUri: string = ''
  videoFileName: string = ''
  videoFileSize: number = 0
  durationMs: number = 0
  positionMs: number = 0
  rememberPosition: boolean = true
  danmakuFileName: string = ''
  danmakuUri: string = ''
  danmakuOffsetMs: number = 0
  danmakuFormat: string = ''
  danmakuCount: number = 0
  externalSubtitleFileName: string = ''
  externalSubtitleUri: string = ''
}

/** 封装本地授权、历史扩展字段和本地文件跳转，页面只依赖这些稳定操作。 */
export class LocalPlayerExtension {
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private thumbnailStore: LocalVideoThumbnailStore = LocalVideoThumbnailStore.getInstance()

  async authorize(context: common.UIAbilityContext, uri: string): Promise<boolean> {
    return await LocalFilePicker.ensureReadableUri(uri) ||
      await LocalFilePicker.authorizeExistingUri(context, uri)
  }

  async persistExternalSubtitle(videoUri: string, fileName: string, fileSize: number,
    subtitleFileName: string, subtitleUri: string): Promise<void> {
    await this.historyStore.updateExternalSubtitleBinding(videoUri, fileName, fileSize,
      subtitleFileName, subtitleUri)
  }

  async restoreExternalSubtitle(videoUri: string, fileName: string,
    fileSize: number): Promise<LocalSubtitleBinding | null> {
    const record = await this.historyStore.getByFileIdentity(videoUri, fileName, fileSize)
    if (record === null || record.externalSubtitleUri.length === 0) return null
    const binding = new LocalSubtitleBinding()
    binding.fileName = record.externalSubtitleFileName
    binding.uri = record.externalSubtitleUri
    return binding
  }

  async saveHistory(update: LocalHistoryUpdate, captureExitFrame: boolean = false): Promise<void> {
    const record = new LocalVideoRecord()
    record.fileUri = update.videoUri
    record.fileName = update.videoFileName
    record.fileSize = update.videoFileSize
    record.durationMs = update.durationMs
    record.positionMs = update.rememberPosition ? update.positionMs : 0
    record.lastPlayedAt = Date.now()
    record.danmakuFileName = update.danmakuFileName
    record.danmakuUri = update.danmakuUri
    record.danmakuOffsetMs = update.danmakuOffsetMs
    record.danmakuFormat = update.danmakuFormat
    record.danmakuCount = update.danmakuCount
    record.externalSubtitleFileName = update.externalSubtitleFileName
    record.externalSubtitleUri = update.externalSubtitleUri
    record.createdAt = Date.now()
    await this.historyStore.upsert(record)
    if (!captureExitFrame) return
    const coverPositionMs = update.durationMs > 0
      ? Math.min(update.positionMs, Math.max(0, update.durationMs - 1)) : update.positionMs
    let coverUri = await this.thumbnailStore.ensureThumbnail(update.videoUri, update.videoFileName,
      update.videoFileSize, coverPositionMs)
    if (coverUri.length === 0) {
      coverUri = await this.thumbnailStore.ensureRandomThumbnail(update.videoUri, update.videoFileName,
        update.videoFileSize)
    }
    if (coverUri.length > 0) await this.historyStore.updateCoverUri(record.fileKey, coverUri)
  }

  async openAnotherLocalVideo(uiContext: UIContext): Promise<string | null> {
    const context = uiContext.getHostContext() as common.UIAbilityContext
    const result = await LocalFilePicker.pickVideoFile(context)
    if (result === null) return null
    const record = new LocalVideoRecord()
    record.fileUri = result.uri
    record.fileName = result.fileName
    record.fileSize = result.fileSize
    await LocalPlaybackLauncher.open(uiContext, record, [record], true, true)
    return result.fileName
  }

  async deleteHistory(localRecordId: number): Promise<void> {
    if (!Number.isFinite(localRecordId) || localRecordId <= 0) return
    const records = await this.historyStore.getAll()
    for (let i = 0; i < records.length; i++) {
      if (records[i].id !== localRecordId) continue
      await LocalFilePicker.revokeUriPermission(records[i].fileUri)
      await this.historyStore.deleteById(localRecordId)
      return
    }
  }
}
