import { relationalStore } from '@kit.ArkData';
import { RdbConstants } from '../constants/RdbConstants';
import { RdbMigration } from './RdbMigration';
import { Logger } from '../utils/Logger';

const logger = new Logger('RdbManager');

export class RdbManager {
  private static instance: RdbManager | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;
  private context: Context | null = null;

  private constructor() {}

  static getInstance(): RdbManager {
    if (RdbManager.instance === null) {
      RdbManager.instance = new RdbManager();
    }
    return RdbManager.instance;
  }

  init(context: Context): Promise<relationalStore.RdbStore> {
    this.context = context;
    const config: relationalStore.StoreConfig = {
      name: RdbConstants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    return relationalStore.getRdbStore(context, config).then(async (store: relationalStore.RdbStore) => {
      this.rdbStore = store;
      const currentVersion = store.version;
      if (currentVersion < RdbConstants.DB_VERSION) {
        logger.info('DB upgrade needed: %{public}d -> %{public}d', currentVersion, RdbConstants.DB_VERSION);
        await RdbMigration.migrateToVersion(this, RdbConstants.DB_VERSION, currentVersion);
        store.version = RdbConstants.DB_VERSION;
      } else if (currentVersion === 0) {
        logger.info('DB first creation');
        await RdbMigration.migrateToVersion(this, RdbConstants.DB_VERSION, currentVersion);
        store.version = RdbConstants.DB_VERSION;
      }
      logger.info('RdbStore initialized at version %{public}d', RdbConstants.DB_VERSION);
      return store;
    }).catch((err: Error) => {
      logger.error('Failed to init RdbStore: %{public}s', err.message);
      throw new Error('Failed to init RdbStore: ' + err.message);
    });
  }

  getStore(): relationalStore.RdbStore {
    if (this.rdbStore === null) {
      throw new Error('RdbStore not initialized');
    }
    return this.rdbStore;
  }

  async executeSql(sql: string, args?: relationalStore.ValueType[]): Promise<void> {
    const store = this.getStore();
    try {
      if (args !== undefined && args.length > 0) {
        await store.executeSql(sql, args);
      } else {
        await store.executeSql(sql);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('executeSql failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    const store = this.getStore();
    try {
      const rowId = await store.insert(table, values);
      logger.debug('Inserted into %{public}s, rowId=%{public}d', table, rowId);
      return rowId;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Insert failed for %{public}s: %{public}s', table, msg);
      throw new Error(msg);
    }
  }

  async update(table: string, values: relationalStore.ValuesBucket, predicates: relationalStore.RdbPredicates): Promise<number> {
    const store = this.getStore();
    try {
      const count = await store.update(values, predicates);
      logger.debug('Updated %{public}s, count=%{public}d', table, count);
      return count;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Update failed for %{public}s: %{public}s', table, msg);
      throw new Error(msg);
    }
  }

  async delete(predicates: relationalStore.RdbPredicates): Promise<number> {
    const store = this.getStore();
    try {
      const count = await store.delete(predicates);
      logger.debug('Deleted, count=%{public}d', count);
      return count;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Delete failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  async query(predicates: relationalStore.RdbPredicates, columns?: string[]): Promise<relationalStore.ResultSet> {
    const store = this.getStore();
    try {
      if (columns !== undefined && columns.length > 0) {
        return await store.query(predicates, columns);
      } else {
        return await store.query(predicates);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Query failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  async querySql(sql: string, args?: relationalStore.ValueType[]): Promise<relationalStore.ResultSet> {
    const store = this.getStore();
    try {
      if (args !== undefined && args.length > 0) {
        return await store.querySql(sql, args);
      } else {
        return await store.querySql(sql);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('querySql failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  beginTransaction(): void {
    const store = this.getStore();
    store.beginTransaction();
  }

  commit(): void {
    const store = this.getStore();
    store.commit();
  }

  rollBack(): void {
    const store = this.getStore();
    store.rollBack();
  }
}
