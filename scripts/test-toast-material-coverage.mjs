import { readdirSync, readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const url = new URL(entry.name + (entry.isDirectory() ? '/' : ''), directory);
    return entry.isDirectory() ? files(url) : entry.name.endsWith('.ets') ? [url] : [];
  });
}

test('every native toast uses the guarded material options builder', () => {
  let total = 0;
  for (const url of files(new URL('../entry/src/main/ets/', import.meta.url))) {
    const source = readFileSync(url, 'utf8');
    const calls = [...source.matchAll(/\.showToast\s*\(/g)];
    if (!calls.length) continue;
    assert.match(source, /import \{[^}]*buildDetailToastOptions[^}]*\} from/);
    for (const call of calls) {
      assert.match(source.slice(call.index), /^\.showToast\(buildDetailToastOptions\(/, url.pathname);
    }
    total += calls.length;
  }
  assert.ok(total >= 30);
});
