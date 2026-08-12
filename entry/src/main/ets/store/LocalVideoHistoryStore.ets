import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { LocalVideoRecord } from '../models/LocalVideoRecord';
import { Logger } from '../utils/Logger';
import { LocalVideoHistoryChangeSignal } from './LocalVideoHistoryChangeSignal';

const logger = new Logger('LocalVideoHistoryStore');

export class LocalVideoHistoryStore {
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<LocalVideoRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.orderByDesc(RdbConstants.COL_LAST_PLAYED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async getByFileKey(fileKey: string): Promise<LocalVideoRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, fileKey);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    if (list.length > 0) {
      return list[0];
    }
    return null;
  }

  async getByFileIdentity(fileUri: string, fileName: string, fileSize: number): Promise<LocalVideoRecord | null> {
    return this.getByFileKey(`${fileUri}|${fileSize}|${fileName}`);
  }

  async upsert(record: LocalVideoRecord): Promise<number> {
    const fileKey = this.buildFileKey(record);
    record.fileKey = fileKey;
    const existing = await this.getByFileKey(fileKey);
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
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_ID, id);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async deleteByIds(ids: number[]): Promise<number> {
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
    if (fileKey.length === 0 || coverUri.length === 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, fileKey);
    const values: relationalStore.ValuesBucket = {
      cover_uri: coverUri
    };
    const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async updateExternalSubtitleBinding(fileUri: string, fileName: string, fileSize: number,
    subtitleFileName: string, subtitleUri: string): Promise<number> {
    const existing = await this.getByFileIdentity(fileUri, fileName, fileSize);
    if (existing === null) {
      const record = new LocalVideoRecord();
      record.fileUri = fileUri;
      record.fileName = fileName;
      record.fileSize = fileSize;
      record.externalSubtitleFileName = subtitleFileName;
      record.externalSubtitleUri = subtitleUri;
      return this.upsert(record);
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, existing.fileKey);
    const values: relationalStore.ValuesBucket = {
      external_subtitle_file_name: subtitleFileName,
      external_subtitle_uri: subtitleUri
    };
    const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async clearAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
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
          record.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          record.fileKey = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_KEY));
          record.fileUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_URI));
          record.fileName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_NAME));
          record.fileSize = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_FILE_SIZE));
          record.coverUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_COVER_URI));
          record.durationMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS));
          record.positionMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS));
          record.lastPlayedAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_LAST_PLAYED_AT));
          record.externalSubtitleFileName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EXTERNAL_SUBTITLE_FILE_NAME));
          record.externalSubtitleUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EXTERNAL_SUBTITLE_URI));
          record.createdAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_CREATED_AT));
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

  private buildFileKey(record: LocalVideoRecord): string {
    if (record.fileKey.length > 0) {
      return record.fileKey;
    }
    if (record.fileUri.length > 0) {
      return `${record.fileUri}|${record.fileSize}|${record.fileName}`;
    }
    return `${record.fileName}|${record.fileSize}|${record.durationMs}`;
  }
}
