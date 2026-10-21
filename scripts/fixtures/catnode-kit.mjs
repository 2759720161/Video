import * as fs from 'node:fs';
import { createHash } from 'node:crypto';
export const common = {};
export const hilog = { info() {}, warn() {}, error() {} };
export const promptAction = { showToast() {} };
export const buffer = { from: Buffer.from, byteLength: Buffer.byteLength };
export const util = { TextEncoder: class extends TextEncoder {
  encodeInto(value) { return this.encode(value); }
} };
export const url = { URL: class extends URL { static parseURL(value) { return new this(value); } } };
export const cryptoFramework = { createMd(name) {
  const digest = createHash(name.toLowerCase());
  return { async update(blob) { digest.update(blob.data); }, async digest() { return { data: digest.digest() }; } };
} };
export const fileIo = {
  OpenMode: { CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC,
    WRITE_ONLY: fs.constants.O_WRONLY, READ_ONLY: fs.constants.O_RDONLY },
  accessSync: fs.existsSync, mkdirSync: (path, recursive) => fs.mkdirSync(path, { recursive }),
  openSync: (path, flags) => ({ fd: fs.openSync(path, flags) }),
  closeSync: file => fs.closeSync(typeof file === 'number' ? file : file.fd),
  statSync: path => typeof path === 'number' ? fs.fstatSync(path) : fs.statSync(path),
  writeSync: (fd, data) => fs.writeSync(fd, typeof data === 'string' ? data : Buffer.from(data)),
  readSync: (fd, data) => fs.readSync(fd, Buffer.from(data)), readTextSync: path => fs.readFileSync(path, 'utf8'),
  renameSync: fs.renameSync, unlinkSync: fs.unlinkSync
};
export const http = {
  RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0, ARRAY_BUFFER: 1 },
  createHttp() { return { async request(address, options) {
    const response = await fetch(address, { method: options.method, headers: options.header,
      body: options.method === 'POST' ? options.extraData : undefined });
    const result = options.expectDataType === 1 ? await response.arrayBuffer() : await response.text();
    if ((typeof result === 'string' ? Buffer.byteLength(result) : result.byteLength) > options.maxLimit) throw new Error('too large');
    return { responseCode: response.status, result };
  }, destroy() {} }; }
};
