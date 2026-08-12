import { fileIo as fs } from '@kit.CoreFileKit';
import { Logger } from '../utils/Logger';

const logger = new Logger('FileStore');

export class FileStore {
  private context: Context | null = null;
  private static instance: FileStore | null = null;

  private constructor() {}

  static getInstance(): FileStore {
    if (FileStore.instance === null) {
      FileStore.instance = new FileStore();
    }
    return FileStore.instance;
  }

  init(context: Context): void {
    this.context = context;
    logger.info('FileStore initialized');
  }

  private getContext(): Context {
    if (this.context === null) {
      throw new Error('FileStore not initialized');
    }
    return this.context;
  }

  async writeFile(relativePath: string, content: string): Promise<void> {
    try {
      const dir = this.getContext().filesDir;
      const fullPath = dir + '/' + relativePath;
      const dirPath = fullPath.substring(0, fullPath.lastIndexOf('/'));
      if (!fs.accessSync(dirPath)) {
        fs.mkdirSync(dirPath, true);
      }
      const file = fs.openSync(fullPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('writeFile failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  async readFile(relativePath: string): Promise<string> {
    try {
      const dir = this.getContext().filesDir;
      const fullPath = dir + '/' + relativePath;
      const file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(fullPath);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const arr = new Uint8Array(buf);
      let result = '';
      for (let i = 0; i < arr.length; i++) {
        result += String.fromCharCode(arr[i]);
      }
      return result;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('readFile failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  async deleteFile(relativePath: string): Promise<void> {
    try {
      const dir = this.getContext().filesDir;
      const fullPath = dir + '/' + relativePath;
      if (fs.accessSync(fullPath)) {
        fs.unlinkSync(fullPath);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('deleteFile failed: %{public}s', msg);
      throw new Error(msg);
    }
  }

  async fileExists(relativePath: string): Promise<boolean> {
    try {
      const dir = this.getContext().filesDir;
      const fullPath = dir + '/' + relativePath;
      return fs.accessSync(fullPath);
    } catch (err) {
      return false;
    }
  }

  getFilesDir(): string {
    return this.getContext().filesDir;
  }

  getCacheDir(): string {
    return this.getContext().cacheDir;
  }
}