import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { LocalVideoRecord } from '../models/LocalVideoRecord';
import { Logger } from '../utils/Logger';
import { LocalVideoHistoryChangeSignal } from './LocalVideoHistoryChangeSignal';

const logger = new Logger('LocalVideoHistoryStore');

export class LocalVideoHistoryStore {
  private static mutationTail: Promise<void> = Promise.resolve();
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<LocalVideoRecord[]> {
    // Public reads wait for queued writes; mutation internals use the direct
    // query below to avoid waiting on their own mutation entry.
    await LocalVideoHistoryStore.mutationTail;
    return this.getAllInternal();
  }

  private async getAllInternal(): Promise<LocalVideoRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.orderByDesc(RdbConstants.COL_LAST_PLAYED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async getByFileKey(fileKey: string): Promise<LocalVideoRecord | null> {
    const normalizedFileKey = LocalVideoHistoryStore.normalizeText(fileKey);
    if (normalizedFileKey.length === 0) {
      return null;
    }
    await LocalVideoHistoryStore.mutationTail;
    return this.getByFileKeyInternal(normalizedFileKey);
  }

  private async getByFileKeyInternal(normalizedFileKey: string): Promise<LocalVideoRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, normalizedFileKey);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    if (list.length > 0) {
      return list[0];
    }
    return null;
  }

  async getByFileIdentity(fileUri: string, fileName: string, fileSize: number): Promise<LocalVideoRecord | null> {
    return this.getByFileKey(`${LocalVideoHistoryStore.safeText(fileUri)}|${LocalVideoHistoryStore.safeNumber(fileSize)}|` +
      LocalVideoHistoryStore.safeText(fileName));
  }

  private async getByFileIdentityInternal(fileUri: string, fileName: string, fileSize: number): Promise<LocalVideoRecord | null> {
    return this.getByFileKeyInternal(LocalVideoHistoryStore.normalizeText(
      `${LocalVideoHistoryStore.safeText(fileUri)}|${LocalVideoHistoryStore.safeNumber(fileSize)}|` +
      LocalVideoHistoryStore.safeText(fileName)));
  }

  async upsert(record: LocalVideoRecord): Promise<number> {
    const snapshot = LocalVideoHistoryStore.copyRecord(record);
    return LocalVideoHistoryStore.enqueueMutation<number>(() => this.upsertInternal(snapshot));
  }

  private async upsertInternal(record: LocalVideoRecord): Promise<number> {
    record.fileUri = LocalVideoHistoryStore.safeText(record.fileUri)
    record.fileName = LocalVideoHistoryStore.safeText(record.fileName)
    record.fileSize = LocalVideoHistoryStore.safeNumber(record.fileSize)
    record.coverUri = LocalVideoHistoryStore.safeText(record.coverUri)
    record.externalSubtitleFileName = LocalVideoHistoryStore.safeText(record.externalSubtitleFileName)
    record.externalSubtitleUri = LocalVideoHistoryStore.safeText(record.externalSubtitleUri)
    const fileKey = this.buildFileKey(record);
    if (fileKey.length === 0) {
      return -1;
    }
    record.positionMs = Number.isFinite(record.positionMs) ? Math.max(0, Math.floor(record.positionMs)) : 0;
    record.durationMs = Number.isFinite(record.durationMs) ? Math.max(0, Math.floor(record.durationMs)) : 0;
    if (record.durationMs > 0) record.positionMs = Math.min(record.positionMs, record.durationMs);
    record.fileKey = fileKey;
    const existing = await this.getByFileKeyInternal(fileKey);
    if (existing !== null) {
      if (record.positionMs <= 0 && existing.positionMs > 0) {
        record.positionMs = existing.positionMs;
      }
      if (record.durationMs <= 0 && existing.durationMs > 0) {
        record.durationMs = existing.durationMs;
      }
      if (record.coverUri.length === 0 && existing.coverUri.length > 0) {
        record.coverUri = existing.coverUri;
      }
      // Routine progress saves do not know whether an empty subtitle field means
      // "not restored yet" or "user explicitly cleared it". Preserve the stored
      // binding here; explicit subtitle actions use updateExternalSubtitleBinding.
      if (record.externalSubtitleUri.length === 0 && existing.externalSubtitleUri.length > 0) {
        record.externalSubtitleUri = existing.externalSubtitleUri;
        record.externalSubtitleFileName = existing.externalSubtitleFileName;
      }
      if (record.durationMs > 0) record.positionMs = Math.min(record.positionMs, record.durationMs);
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
      predicates.equalTo(RdbConstants.COL_FILE_KEY, fileKey);
      const values: relationalStore.ValuesBucket = {
        file_key: fileKey,
        file_uri: record.fileUri,
        file_name: record.fileName,
        file_size: record.fileSize,
        cover_uri: record.coverUri,
        duration_ms: record.durationMs,
        position_ms: record.positionMs,
        external_subtitle_file_name: record.externalSubtitleFileName,
        external_subtitle_uri: record.externalSubtitleUri,
        last_played_at: Date.now()
      };
      const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
      LocalVideoHistoryChangeSignal.notifyChanged();
      return rows;
    } else {
      const values: relationalStore.ValuesBucket = {
        file_key: fileKey,
        file_uri: record.fileUri,
        file_name: record.fileName,
        file_size: record.fileSize,
        cover_uri: record.coverUri,
        duration_ms: record.durationMs,
        position_ms: record.positionMs,
        external_subtitle_file_name: record.externalSubtitleFileName,
        external_subtitle_uri: record.externalSubtitleUri,
        last_played_at: Date.now(),
        created_at: Date.now()
      };
      const id = await this.rdbManager.insert(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values);
      LocalVideoHistoryChangeSignal.notifyChanged();
      return id;
    }
  }

  async deleteById(id: number): Promise<number> {
    return LocalVideoHistoryStore.enqueueMutation<number>(() => this.deleteByIdInternal(id));
  }

  private async deleteByIdInternal(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_ID, id);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async deleteByIds(ids: number[]): Promise<number> {
    const snapshot = ids.slice();
    return LocalVideoHistoryStore.enqueueMutation<number>(() => this.deleteByIdsInternal(snapshot));
  }

  private async deleteByIdsInternal(ids: number[]): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.in(RdbConstants.COL_ID, ids);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async updateCoverUri(fileKey: string, coverUri: string): Promise<number> {
    return LocalVideoHistoryStore.enqueueMutation<number>(() => this.updateCoverUriInternal(fileKey, coverUri));
  }

  private async updateCoverUriInternal(fileKey: string, coverUri: string): Promise<number> {
    const normalizedFileKey = LocalVideoHistoryStore.normalizeText(fileKey);
    const normalizedCoverUri = LocalVideoHistoryStore.normalizeText(coverUri)
    if (normalizedFileKey.length === 0 || normalizedCoverUri.length === 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, normalizedFileKey);
    const values: relationalStore.ValuesBucket = {
      cover_uri: normalizedCoverUri
    };
    const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async updateExternalSubtitleBinding(fileUri: string, fileName: string, fileSize: number,
    subtitleFileName: string, subtitleUri: string): Promise<number> {
    return LocalVideoHistoryStore.enqueueMutation<number>(() => this.updateExternalSubtitleBindingInternal(
      fileUri, fileName, fileSize, subtitleFileName, subtitleUri));
  }

  private async updateExternalSubtitleBindingInternal(fileUri: string, fileName: string, fileSize: number,
    subtitleFileName: string, subtitleUri: string): Promise<number> {
    const normalizedFileUri = LocalVideoHistoryStore.safeText(fileUri)
    const normalizedFileName = LocalVideoHistoryStore.safeText(fileName)
    const normalizedFileSize = LocalVideoHistoryStore.safeNumber(fileSize)
    const normalizedSubtitleFileName = LocalVideoHistoryStore.safeText(subtitleFileName)
    const normalizedSubtitleUri = LocalVideoHistoryStore.safeText(subtitleUri)
    const existing = await this.getByFileIdentityInternal(normalizedFileUri, normalizedFileName, normalizedFileSize);
    if (existing === null) {
      const record = new LocalVideoRecord();
      record.fileUri = normalizedFileUri;
      record.fileName = normalizedFileName;
      record.fileSize = normalizedFileSize;
      record.externalSubtitleFileName = normalizedSubtitleFileName;
      record.externalSubtitleUri = normalizedSubtitleUri;
      return this.upsertInternal(record);
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, existing.fileKey);
    const values: relationalStore.ValuesBucket = {
      external_subtitle_file_name: normalizedSubtitleFileName,
      external_subtitle_uri: normalizedSubtitleUri
    };
    const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async clearAll(): Promise<number> {
    return LocalVideoHistoryStore.enqueueMutation<number>(() => this.clearAllInternal());
  }

  private async clearAllInternal(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  /** 串行化本地历史读改写，避免进度保存覆盖字幕或封面绑定。 */
  private static enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = LocalVideoHistoryStore.mutationTail.then(operation, operation);
    LocalVideoHistoryStore.mutationTail = result.then(() => {}, () => {});
    return result;
  }

  private static copyRecord(record: LocalVideoRecord): LocalVideoRecord {
    const copy = new LocalVideoRecord();
    copy.id = record.id;
    copy.sourceId = LocalVideoHistoryStore.safeText(record.sourceId);
    copy.fileKey = LocalVideoHistoryStore.safeText(record.fileKey);
    copy.fileUri = LocalVideoHistoryStore.safeText(record.fileUri);
    copy.fileName = LocalVideoHistoryStore.safeText(record.fileName);
    copy.fileSize = LocalVideoHistoryStore.safeNumber(record.fileSize);
    copy.coverUri = LocalVideoHistoryStore.safeText(record.coverUri);
    copy.durationMs = LocalVideoHistoryStore.safeNumber(record.durationMs);
    copy.positionMs = LocalVideoHistoryStore.safeNumber(record.positionMs);
    copy.lastPlayedAt = LocalVideoHistoryStore.safeNumber(record.lastPlayedAt);
    copy.externalSubtitleFileName = LocalVideoHistoryStore.safeText(record.externalSubtitleFileName);
    copy.externalSubtitleUri = LocalVideoHistoryStore.safeText(record.externalSubtitleUri);
    copy.danmakuFileName = LocalVideoHistoryStore.safeText(record.danmakuFileName);
    copy.danmakuUri = LocalVideoHistoryStore.safeText(record.danmakuUri);
    copy.danmakuOffsetMs = LocalVideoHistoryStore.safeNumber(record.danmakuOffsetMs);
    copy.danmakuFormat = LocalVideoHistoryStore.safeText(record.danmakuFormat);
    copy.danmakuCount = LocalVideoHistoryStore.safeNumber(record.danmakuCount);
    copy.createdAt = LocalVideoHistoryStore.safeNumber(record.createdAt);
    return copy;
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): LocalVideoRecord[] {
    const list: LocalVideoRecord[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new LocalVideoRecord();
          const id = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_ID));
          record.id = Number.isFinite(id) ? id : -1;
          record.fileKey = LocalVideoHistoryStore.safeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_FILE_KEY)));
          record.fileUri = LocalVideoHistoryStore.safeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_FILE_URI)));
          record.fileName = LocalVideoHistoryStore.safeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_FILE_NAME)));
          const fileSize = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_FILE_SIZE));
          record.fileSize = Number.isFinite(fileSize) && fileSize > 0 ? fileSize : 0;
          record.coverUri = LocalVideoHistoryStore.safeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_COVER_URI)));
          const durationMs = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS));
          const positionMs = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS));
          const lastPlayedAt = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_LAST_PLAYED_AT));
          record.durationMs = Number.isFinite(durationMs) && durationMs > 0 ? durationMs : 0;
          record.positionMs = Number.isFinite(positionMs) ? Math.max(0, positionMs) : 0;
          if (record.durationMs > 0) record.positionMs = Math.min(record.positionMs, record.durationMs);
          record.lastPlayedAt = Number.isFinite(lastPlayedAt) && lastPlayedAt > 0 ? lastPlayedAt : 0;
          record.externalSubtitleFileName = LocalVideoHistoryStore.safeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_EXTERNAL_SUBTITLE_FILE_NAME)));
          record.externalSubtitleUri = LocalVideoHistoryStore.safeText(
            this.readString(resultSet, resultSet.getColumnIndex(RdbConstants.COL_EXTERNAL_SUBTITLE_URI)));
          const createdAt = this.readLong(resultSet, resultSet.getColumnIndex(RdbConstants.COL_CREATED_AT));
          record.createdAt = Number.isFinite(createdAt) && createdAt > 0 ? createdAt : 0;
          list.push(record);
        } while (resultSet.goToNextRow());
      }
    } catch (err) {
      logger.error('parseResultSet error: %{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      resultSet.close();
    }
    return list;
  }

  private readString(resultSet: relationalStore.ResultSet, index: number): string {
    try {
      const value = resultSet.getString(index);
      return typeof value === 'string' ? value : '';
    } catch (_) {
      return '';
    }
  }

  private readLong(resultSet: relationalStore.ResultSet, index: number): number {
    try {
      const value = resultSet.getLong(index);
      return Number.isFinite(value) ? value : 0;
    } catch (_) {
      return 0;
    }
  }

  private buildFileKey(record: LocalVideoRecord): string {
    const storedKey = LocalVideoHistoryStore.normalizeText(record.fileKey);
    if (storedKey.length > 0) {
      return storedKey;
    }
    if (record.fileUri.length > 0) {
      return `${record.fileUri}|${LocalVideoHistoryStore.safeNumber(record.fileSize)}|${record.fileName}`;
    }
    return `${record.fileName}|${LocalVideoHistoryStore.safeNumber(record.fileSize)}|` +
      LocalVideoHistoryStore.safeNumber(record.durationMs);
  }

  private static safeText(value: string): string {
    return typeof value === 'string' ? value : '';
  }

  private static normalizeText(value: string): string {
    return LocalVideoHistoryStore.safeText(value).trim();
  }

  private static safeNumber(value: number): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
  }
}
