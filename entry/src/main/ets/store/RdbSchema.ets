import { RdbConstants } from '../constants/RdbConstants';

export class RdbSchema {
  static getCreateRuleSourceTable(): string {
    return `CREATE TABLE IF NOT EXISTS ${RdbConstants.TABLE_RULE_SOURCE} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${RdbConstants.COL_API} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_TYPE} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_NAME} TEXT NOT NULL UNIQUE, ` +
      `${RdbConstants.COL_VERSION} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_BASE_URL} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_SEARCH_URL} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_SEARCH_LIST} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_SEARCH_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_SEARCH_RESULT} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_CHAPTER_ROADS} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_CHAPTER_RESULT} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_REFERER} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_USER_AGENT} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_ANTI_CRAWLER_CONFIG} TEXT NOT NULL DEFAULT '{}', ` +
      `${RdbConstants.COL_USE_WEBVIEW} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_USE_NATIVE_PLAYER} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_USE_POST} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_USE_LEGACY_PARSER} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_AD_BLOCKER} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_MULTI_SOURCES} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_ENABLED} INTEGER NOT NULL DEFAULT 1, ` +
      `${RdbConstants.COL_RAW_JSON} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_CREATED_AT} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_UPDATED_AT} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_SORT_ORDER} INTEGER NOT NULL DEFAULT 0` +
      `)`;
  }

  static getCreateFavoriteTable(): string {
    return `CREATE TABLE IF NOT EXISTS ${RdbConstants.TABLE_FAVORITE} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${RdbConstants.COL_ANIME_ID} TEXT NOT NULL UNIQUE, ` +
      `${RdbConstants.COL_ANIME_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_ANIME_COVER} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_ANIME_DESC} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1, ` +
      `${RdbConstants.COL_COLLECT_TYPE} INTEGER NOT NULL DEFAULT 1, ` +
      `${RdbConstants.COL_BANGUMI_ID} INTEGER NOT NULL DEFAULT -1, ` +
      `${RdbConstants.COL_BANGUMI_COVER} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_COVER_FALLBACK} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_CREATED_AT} INTEGER NOT NULL DEFAULT 0` +
      `)`;
  }

  static getCreateWatchHistoryTable(): string {
    return `CREATE TABLE IF NOT EXISTS ${RdbConstants.TABLE_WATCH_HISTORY} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${RdbConstants.COL_ANIME_ID} TEXT NOT NULL UNIQUE, ` +
      `${RdbConstants.COL_ANIME_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_ANIME_COVER} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_BANGUMI_ID} INTEGER NOT NULL DEFAULT -1, ` +
      `${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1, ` +
      `${RdbConstants.COL_SOURCE_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_EPISODE_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_EPISODE_URL} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_POSITION_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_DURATION_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_ROAD_INDEX} INTEGER NOT NULL DEFAULT -1, ` +
      `${RdbConstants.COL_EPISODE_INDEX} INTEGER NOT NULL DEFAULT -1, ` +
      `${RdbConstants.COL_UPDATED_AT} INTEGER NOT NULL DEFAULT 0` +
      `)`;
  }

  static getCreateSearchHistoryTable(): string {
    return `CREATE TABLE IF NOT EXISTS ${RdbConstants.TABLE_SEARCH_HISTORY} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${RdbConstants.COL_KEYWORD} TEXT NOT NULL UNIQUE, ` +
      `${RdbConstants.COL_TIMESTAMP} INTEGER NOT NULL DEFAULT 0` +
      `)`;
  }

  static getCreateCollectChangeTable(): string {
    return `CREATE TABLE IF NOT EXISTS ${RdbConstants.TABLE_COLLECT_CHANGE} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY, ` +
      `${RdbConstants.COL_BANGUMI_ID} INTEGER NOT NULL, ` +
      `${RdbConstants.COL_ACTION} INTEGER NOT NULL, ` +
      `${RdbConstants.COL_TYPE} INTEGER NOT NULL, ` +
      `${RdbConstants.COL_TIMESTAMP} INTEGER NOT NULL DEFAULT 0` +
      `)`;
  }

  static getCreateLocalVideoHistoryTable(): string {
    return `CREATE TABLE IF NOT EXISTS ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${RdbConstants.COL_FILE_KEY} TEXT NOT NULL UNIQUE, ` +
      `${RdbConstants.COL_FILE_URI} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_FILE_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_FILE_SIZE} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_COVER_URI} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_DURATION_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_POSITION_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_LAST_PLAYED_AT} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_DANMAKU_FILE_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_DANMAKU_URI} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_DANMAKU_OFFSET_MS} INTEGER NOT NULL DEFAULT 0, ` +
        `${RdbConstants.COL_DANMAKU_FORMAT} TEXT NOT NULL DEFAULT '', ` +
        `${RdbConstants.COL_DANMAKU_COUNT} INTEGER NOT NULL DEFAULT 0, ` +
        `${RdbConstants.COL_EXTERNAL_SUBTITLE_FILE_NAME} TEXT NOT NULL DEFAULT '', ` +
        `${RdbConstants.COL_EXTERNAL_SUBTITLE_URI} TEXT NOT NULL DEFAULT '', ` +
        `${RdbConstants.COL_CREATED_AT} INTEGER NOT NULL DEFAULT 0` +
      `)`;
  }

  static getCreateIndexes(): string[] {
    return [
      `CREATE INDEX IF NOT EXISTS idx_rule_source_name ON ${RdbConstants.TABLE_RULE_SOURCE}(${RdbConstants.COL_NAME})`,
      `CREATE INDEX IF NOT EXISTS idx_rule_source_enabled ON ${RdbConstants.TABLE_RULE_SOURCE}(${RdbConstants.COL_ENABLED})`,
      `CREATE INDEX IF NOT EXISTS idx_favorite_anime_id ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_ANIME_ID})`,
      `CREATE INDEX IF NOT EXISTS idx_favorite_collect_type ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_COLLECT_TYPE})`,
      `CREATE INDEX IF NOT EXISTS idx_favorite_bangumi_id ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_BANGUMI_ID})`,
      `CREATE INDEX IF NOT EXISTS idx_watch_history_anime_id ON ${RdbConstants.TABLE_WATCH_HISTORY}(${RdbConstants.COL_ANIME_ID})`,
      `CREATE INDEX IF NOT EXISTS idx_watch_history_bangumi_id ON ${RdbConstants.TABLE_WATCH_HISTORY}(${RdbConstants.COL_BANGUMI_ID})`,
      `CREATE INDEX IF NOT EXISTS idx_search_history_timestamp ON ${RdbConstants.TABLE_SEARCH_HISTORY}(${RdbConstants.COL_TIMESTAMP})`,
      `CREATE INDEX IF NOT EXISTS idx_collect_change_bangumi_id ON ${RdbConstants.TABLE_COLLECT_CHANGE}(${RdbConstants.COL_BANGUMI_ID})`,
      `CREATE INDEX IF NOT EXISTS idx_local_video_history_file_key ON ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}(${RdbConstants.COL_FILE_KEY})`,
      `CREATE INDEX IF NOT EXISTS idx_local_video_history_file_name ON ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}(${RdbConstants.COL_FILE_NAME})`
    ];
  }

  static getAllCreateSql(): string[] {
    const sqls: string[] = [
      RdbSchema.getCreateRuleSourceTable(),
      RdbSchema.getCreateFavoriteTable(),
      RdbSchema.getCreateWatchHistoryTable(),
      RdbSchema.getCreateSearchHistoryTable(),
      RdbSchema.getCreateCollectChangeTable(),
      RdbSchema.getCreateLocalVideoHistoryTable()
    ];
    const indexes = RdbSchema.getCreateIndexes();
    for (let i = 0; i < indexes.length; i++) {
      sqls.push(indexes[i]);
    }
    return sqls;
  }
}
