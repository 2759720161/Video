import { RdbManager } from './RdbManager';
import { RdbSchema } from './RdbSchema';
import { RdbConstants } from '../constants/RdbConstants';
import { Logger } from '../utils/Logger';

const logger = new Logger('RdbMigration');

interface MigrationStep {
  version: number;
  migrate: (rdbManager: RdbManager) => Promise<void>;
}

export class RdbMigration {
  private static migrations: MigrationStep[] = [
    {
      version: 1,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        const sqls = RdbSchema.getAllCreateSql();
        for (let i = 0; i < sqls.length; i++) {
          await rdbManager.executeSql(sqls[i]);
        }
        logger.info('Migration v1: tables created');
      }
    },
    {
      version: 2,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v2: anime_url column already exists in favorite, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1`
          );
        } catch (_err) {
          logger.info('Migration v2: source_id column already exists in favorite, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_WATCH_HISTORY} ADD COLUMN ${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v2: anime_url column already exists in watch_history, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_WATCH_HISTORY} ADD COLUMN ${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1`
          );
        } catch (_err) {
          logger.info('Migration v2: source_id column already exists in watch_history, skipping');
        }
        logger.info('Migration v2: added anime_url and source_id columns');
      }
    },
    {
      version: 3,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_COLLECT_TYPE} INTEGER NOT NULL DEFAULT 1`
          );
        } catch (_err) {
          logger.info('Migration v3: collect_type column already exists, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_BANGUMI_ID} INTEGER NOT NULL DEFAULT -1`
          );
        } catch (_err) {
          logger.info('Migration v3: bangumi_id column already exists, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_BANGUMI_COVER} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v3: bangumi_cover column already exists, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_COVER_FALLBACK} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v3: cover_fallback column already exists, skipping');
        }
        await rdbManager.executeSql(
          RdbSchema.getCreateCollectChangeTable()
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_collect_change_bangumi_id ON ${RdbConstants.TABLE_COLLECT_CHANGE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_collect_type ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_COLLECT_TYPE})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_bangumi_id ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        logger.info('Migration v3: added collect_type, bangumi_id, bangumi_cover, cover_fallback columns and collect_change table');
      }
    },
    {
      version: 4,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.ensureFavoriteCollectColumns(rdbManager);
        await rdbManager.executeSql(
          RdbSchema.getCreateCollectChangeTable()
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_collect_change_bangumi_id ON ${RdbConstants.TABLE_COLLECT_CHANGE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_collect_type ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_COLLECT_TYPE})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_bangumi_id ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        logger.info('Migration v4: repaired favorite collect schema');
      }
    },
    {
      version: 5,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_WATCH_HISTORY,
          RdbConstants.COL_ROAD_INDEX,
          'INTEGER NOT NULL DEFAULT -1');
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_WATCH_HISTORY,
          RdbConstants.COL_EPISODE_INDEX,
          'INTEGER NOT NULL DEFAULT -1');
        logger.info('Migration v5: added road_index and episode_index to watch_history');
      }
    },
    {
      version: 6,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_RULE_SOURCE,
          RdbConstants.COL_SORT_ORDER,
          'INTEGER NOT NULL DEFAULT 0');
        logger.info('Migration v6: added sort_order to rule_source');
      }
    },
    {
      version: 7,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await rdbManager.executeSql(
          RdbSchema.getCreateLocalVideoHistoryTable()
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_local_video_history_file_key ON ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}(${RdbConstants.COL_FILE_KEY})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_local_video_history_file_name ON ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}(${RdbConstants.COL_FILE_NAME})`
        );
        logger.info('Migration v7: created local_video_history table');
      }
    },
    {
      version: 8,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.rebuildLocalVideoHistoryWithFileKey(rdbManager);
        logger.info('Migration v8: rebuilt local_video_history with file_key uniqueness');
      }
    },
    {
      version: 9,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_LOCAL_VIDEO_HISTORY,
          RdbConstants.COL_COVER_URI,
          'TEXT NOT NULL DEFAULT \'\'');
        logger.info('Migration v9: added cover_uri to local_video_history');
      }
    },
    {
      version: 10,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_WATCH_HISTORY,
          RdbConstants.COL_BANGUMI_ID,
          'INTEGER NOT NULL DEFAULT -1');
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_watch_history_bangumi_id ON ${RdbConstants.TABLE_WATCH_HISTORY}(${RdbConstants.COL_BANGUMI_ID})`
        );
        logger.info('Migration v10: added bangumi_id to watch_history');
      }
    },
    {
      version: 11,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_WATCH_HISTORY,
          RdbConstants.COL_SOURCE_NAME,
          'TEXT NOT NULL DEFAULT \'\'');
        logger.info('Migration v11: added source_name to watch_history');
      }
    },
    {
      version: 12,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_LOCAL_VIDEO_HISTORY,
          RdbConstants.COL_EXTERNAL_SUBTITLE_FILE_NAME,
          'TEXT NOT NULL DEFAULT \'\'');
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_LOCAL_VIDEO_HISTORY,
          RdbConstants.COL_EXTERNAL_SUBTITLE_URI,
          'TEXT NOT NULL DEFAULT \'\'');
        logger.info('Migration v12: added persisted external subtitle binding');
      }
    }
  ];

  private static async rebuildLocalVideoHistoryWithFileKey(rdbManager: RdbManager): Promise<void> {
    const tempTable = `${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}_v8`;
    await rdbManager.executeSql(
      `CREATE TABLE IF NOT EXISTS ${tempTable} (` +
      `${RdbConstants.COL_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${RdbConstants.COL_FILE_KEY} TEXT NOT NULL UNIQUE, ` +
      `${RdbConstants.COL_FILE_URI} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_FILE_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_FILE_SIZE} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_DURATION_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_POSITION_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_LAST_PLAYED_AT} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_DANMAKU_FILE_NAME} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_DANMAKU_URI} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_DANMAKU_OFFSET_MS} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_DANMAKU_FORMAT} TEXT NOT NULL DEFAULT '', ` +
      `${RdbConstants.COL_DANMAKU_COUNT} INTEGER NOT NULL DEFAULT 0, ` +
      `${RdbConstants.COL_CREATED_AT} INTEGER NOT NULL DEFAULT 0` +
      `)`
    );
    await rdbManager.executeSql(
      `INSERT OR IGNORE INTO ${tempTable} (` +
      `${RdbConstants.COL_ID}, ${RdbConstants.COL_FILE_KEY}, ${RdbConstants.COL_FILE_URI}, ` +
      `${RdbConstants.COL_FILE_NAME}, ${RdbConstants.COL_FILE_SIZE}, ${RdbConstants.COL_DURATION_MS}, ` +
      `${RdbConstants.COL_POSITION_MS}, ${RdbConstants.COL_LAST_PLAYED_AT}, ${RdbConstants.COL_DANMAKU_FILE_NAME}, ` +
      `${RdbConstants.COL_DANMAKU_URI}, ${RdbConstants.COL_DANMAKU_OFFSET_MS}, ${RdbConstants.COL_DANMAKU_FORMAT}, ` +
      `${RdbConstants.COL_DANMAKU_COUNT}, ${RdbConstants.COL_CREATED_AT}) ` +
      `SELECT ${RdbConstants.COL_ID}, ` +
      `CASE WHEN ${RdbConstants.COL_FILE_URI} <> '' ` +
      `THEN ${RdbConstants.COL_FILE_URI} || '|' || CAST(${RdbConstants.COL_FILE_SIZE} AS TEXT) || '|' || ${RdbConstants.COL_FILE_NAME} ` +
      `ELSE ${RdbConstants.COL_FILE_NAME} || '|' || CAST(${RdbConstants.COL_FILE_SIZE} AS TEXT) || '|' || CAST(${RdbConstants.COL_DURATION_MS} AS TEXT) END, ` +
      `${RdbConstants.COL_FILE_URI}, ${RdbConstants.COL_FILE_NAME}, ${RdbConstants.COL_FILE_SIZE}, ` +
      `${RdbConstants.COL_DURATION_MS}, ${RdbConstants.COL_POSITION_MS}, ${RdbConstants.COL_LAST_PLAYED_AT}, ` +
      `${RdbConstants.COL_DANMAKU_FILE_NAME}, ${RdbConstants.COL_DANMAKU_URI}, ${RdbConstants.COL_DANMAKU_OFFSET_MS}, ` +
      `${RdbConstants.COL_DANMAKU_FORMAT}, ${RdbConstants.COL_DANMAKU_COUNT}, ${RdbConstants.COL_CREATED_AT} ` +
      `FROM ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}`
    );
    await rdbManager.executeSql(`DROP TABLE ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}`);
    await rdbManager.executeSql(`ALTER TABLE ${tempTable} RENAME TO ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}`);
    await rdbManager.executeSql(
      `CREATE INDEX IF NOT EXISTS idx_local_video_history_file_key ON ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}(${RdbConstants.COL_FILE_KEY})`
    );
    await rdbManager.executeSql(
      `CREATE INDEX IF NOT EXISTS idx_local_video_history_file_name ON ${RdbConstants.TABLE_LOCAL_VIDEO_HISTORY}(${RdbConstants.COL_FILE_NAME})`
    );
  }

  private static async ensureFavoriteCollectColumns(rdbManager: RdbManager): Promise<void> {
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_ANIME_URL, 'TEXT NOT NULL DEFAULT \'\'');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_SOURCE_ID, 'INTEGER NOT NULL DEFAULT -1');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_COLLECT_TYPE, 'INTEGER NOT NULL DEFAULT 1');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_BANGUMI_ID, 'INTEGER NOT NULL DEFAULT -1');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_BANGUMI_COVER, 'TEXT NOT NULL DEFAULT \'\'');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_COVER_FALLBACK, 'TEXT NOT NULL DEFAULT \'\'');
  }

  private static async addColumnIfMissing(rdbManager: RdbManager, table: string, column: string,
    definition: string): Promise<void> {
    try {
      await rdbManager.executeSql(
        `ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`
      );
      logger.info('Added column %{public}s.%{public}s', table, column);
    } catch (_err) {
      logger.info('Column %{public}s.%{public}s already exists, skipping', table, column);
    }
  }

  static async migrateToVersion(rdbManager: RdbManager, targetVersion: number, currentVersion: number = 0): Promise<void> {
    logger.info('Starting migration from version %{public}d to version %{public}d', currentVersion, targetVersion);

    for (let i = 0; i < RdbMigration.migrations.length; i++) {
      const migration = RdbMigration.migrations[i];
      if (migration.version <= currentVersion) {
        continue;
      }
      if (migration.version > targetVersion) {
        break;
      }

      try {
        rdbManager.beginTransaction();
        await migration.migrate(rdbManager);
        rdbManager.commit();
        logger.info('Migration v%{public}d completed', migration.version);
      } catch (err) {
        rdbManager.rollBack();
        const msg = err instanceof Error ? err.message : String(err);
        logger.error('Migration v%{public}d failed, rolled back: %{public}s',
          migration.version, msg);
        throw new Error(msg);
      }
    }

    logger.info('Migration to version %{public}d completed', targetVersion);
  }

  static getCurrentVersion(): number {
    return RdbConstants.DB_VERSION;
  }
}
