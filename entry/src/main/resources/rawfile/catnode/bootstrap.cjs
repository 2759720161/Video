'use strict';
const reportFailure = error => globalThis.videoNativeNotify(JSON.stringify({
  type: 'error', message: error instanceof Error ? (error.stack || error.message) : String(error)
}));
process.on('uncaughtExceptionMonitor', reportFailure);
process.on('unhandledRejection', reportFailure);
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { createHost } = require('./host.cjs');
const root = process.argv[2];
const notify = value => globalThis.videoNativeNotify(JSON.stringify(value));
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'bundle.json'), 'utf8'));
if (!/^[0-9a-f]{32}$/.test(manifest.md5) || !/^[0-9a-f]{64}$/.test(manifest.sha256) ||
    manifest.file !== `index.${manifest.md5}.cjs`) {
  throw new Error('Cat 订阅缓存无效，请重新保存订阅');
}
const bundle = path.join(__dirname, manifest.file);
const bytes = fs.readFileSync(bundle);
if (crypto.createHash('sha256').update(bytes).digest('hex') !== manifest.sha256 ||
    crypto.createHash('md5').update(bytes).digest('hex') !== manifest.md5) {
  throw new Error('Cat 订阅校验失败，请重新保存订阅');
}
const host = createHost(root, notify);
host.start(bundle).catch(error => {
  notify({ type: 'error', message: error.message });
  process.exitCode = 1;
});
