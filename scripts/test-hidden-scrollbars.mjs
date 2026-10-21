import { readdirSync, readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

function sources(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = new URL(entry.name + (entry.isDirectory() ? '/' : ''), directory);
    return entry.isDirectory() ? sources(path) : entry.name.endsWith('.ets') ? [path] : [];
  });
}

test('all scroll and grid containers explicitly hide scrollbars', () => {
  let containers = 0;
  let hiddenBars = 0;
  for (const path of sources(new URL('../entry/src/main/ets/', import.meta.url))) {
    const source = readFileSync(path, 'utf8');
    const count = [...source.matchAll(/\b(?:Scroll|Grid|List|WaterFlow|ArcList)\s*\([^\n]*\)\s*\{/g)].length;
    const off = [...source.matchAll(/\.scrollBar\(BarState\.Off\)/g)].length;
    assert.doesNotMatch(source, /\.scrollBar\(BarState\.(?:Auto|On)\)/, path.pathname);
    assert.doesNotMatch(source, /\b(?:ScrollBar|ArcScrollBar)\s*\(/, path.pathname);
    assert.equal(off, count, path.pathname);
    containers += count;
    hiddenBars += off;
  }
  assert.ok(containers > 0);
  assert.equal(hiddenBars, containers);
});
