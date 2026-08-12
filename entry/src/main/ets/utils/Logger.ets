import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../constants/AppConstants';

export enum LogLevel {
  DEBUG = 3,
  INFO = 4,
  WARN = 5,
  ERROR = 6
}

export class Logger {
  private module: string;
  private static globalLevel: LogLevel = LogLevel.DEBUG;

  constructor(module: string) {
    this.module = module;
  }

  static setGlobalLevel(level: LogLevel): void {
    Logger.globalLevel = level;
  }

  debug(msg: string, ...args: Object[]): void {
    if (Logger.globalLevel <= LogLevel.DEBUG) {
      hilog.debug(AppConstants.DOMAIN, this.module, msg, ...args);
    }
  }

  info(msg: string, ...args: Object[]): void {
    if (Logger.globalLevel <= LogLevel.INFO) {
      hilog.info(AppConstants.DOMAIN, this.module, msg, ...args);
    }
  }

  warn(msg: string, ...args: Object[]): void {
    if (Logger.globalLevel <= LogLevel.WARN) {
      hilog.warn(AppConstants.DOMAIN, this.module, msg, ...args);
    }
  }

  error(msg: string, ...args: Object[]): void {
    if (Logger.globalLevel <= LogLevel.ERROR) {
      hilog.error(AppConstants.DOMAIN, this.module, msg, ...args);
    }
  }

  static measure<T>(module: string, label: string, fn: () => T): T {
    const logger = new Logger(module);
    const start = Date.now();
    try {
      const result = fn();
      const elapsed = Date.now() - start;
      logger.info('%{public}s took %{public}d ms', label, elapsed);
      return result;
    } catch (err) {
      const elapsed = Date.now() - start;
      const errMsg = err instanceof Error ? err.message : String(err);
      logger.error('%{public}s failed after %{public}d ms: %{public}s', label, elapsed, errMsg);
      throw new Error(errMsg);
    }
  }

  static async measureAsync<T>(module: string, label: string, fn: () => Promise<T>): Promise<T> {
    const logger = new Logger(module);
    const start = Date.now();
    try {
      const result = await fn();
      const elapsed = Date.now() - start;
      logger.info('%{public}s took %{public}d ms', label, elapsed);
      return result;
    } catch (err) {
      const elapsed = Date.now() - start;
      const errMsg = err instanceof Error ? err.message : String(err);
      logger.error('%{public}s failed after %{public}d ms: %{public}s', label, elapsed, errMsg);
      throw new Error(errMsg);
    }
  }

  structLog(action: string, data: Record<string, Object>): void {
    if (Logger.globalLevel <= LogLevel.INFO) {
      const parts: string[] = [`[${this.module}]`, action];
      const keys = Object.keys(data);
      for (let i = 0; i < keys.length; i++) {
        parts.push(`${keys[i]}=${String(data[keys[i]])}`);
      }
      hilog.info(AppConstants.DOMAIN, this.module, parts.join(' | '));
    }
  }
}

export function extractErrorMsg(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  const errObj = err as Record<string, Object>;
  if (errObj !== null && errObj !== undefined) {
    if (errObj['message'] !== undefined) {
      return String(errObj['message']);
    }
    if (errObj['code'] !== undefined) {
      return 'code=' + String(errObj['code']);
    }
  }
  return String(err);
}