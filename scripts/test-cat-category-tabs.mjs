import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/pages/catvod/CatVodCategoryTab.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  build()'));
const reset = source.slice(source.indexOf('class CatVodCategoryTabReset'));
const Tab = new Function('FrameCallback', stripTypeScriptTypes(`class Tab { ${methods} }\n${reset}`,
  { mode: 'transform' }) + ';return Tab;')(class {});
const setup = (selected = false, enabled = true) => {
  let selections = 0; const frames = [];
  const tab = Object.assign(new Tab(), { selected, selectionEnabled: enabled, toggled: false,
    resetPending: false, resetTicket: 0, alive: false, onSelect: () => selections++,
    getUIContext: () => ({ postFrameCallback: callback => frames.push(callback) }) });
  tab.aboutToAppear();
  const touch = value => { tab.toggled = value; tab.selectionChanged(value); };
  const render = () => { for (const frame of frames.splice(0)) frame.onFrame(); };
  return { tab, touch, render, frames, selections: () => selections };
};

test('active tab cannot be deselected by repeated taps or feedback from its native Toggle', () => {
  const { tab, touch, render, selections } = setup(true);
  for (let attempt = 0; attempt < 10; attempt++) {
    touch(false); assert.equal(tab.toggled, false, 'allow native state to render before restoring');
    render(); assert.equal(tab.toggled, true);
    touch(true); render(); assert.equal(tab.toggled, true);
  }
  assert.equal(selections(), 0);
});

test('an unaccepted selection restores parent state and a later accepted update selects exactly one tab', () => {
  const previous = setup(true), next = setup(false);
  next.touch(true);
  next.render();
  assert.equal(next.selections(), 1);
  assert.equal(next.tab.toggled, false, 'a stale or rejected action must not create a second selection');
  previous.tab.selected = false; previous.tab.syncSelection();
  next.tab.selected = true; next.tab.syncSelection();
  assert.equal(previous.tab.toggled, false); assert.equal(next.tab.toggled, true);
  previous.touch(false); next.touch(true); previous.render(); next.render();
  assert.equal(next.selections(), 1); assert.equal(previous.selections(), 0);
});

test('loading and disabled state block stale native selection events without losing the active tab', () => {
  for (const selected of [false, true]) {
    const { tab, touch, render, selections } = setup(selected, false);
    for (const value of [true, false, true]) { touch(value); render(); assert.equal(tab.toggled, selected); }
    assert.equal(selections(), 0);
  }
});

test('a synchronous parent switch is retained when the callback returns', () => {
  const { tab, touch, render } = setup(false);
  let calls = 0;
  tab.onSelect = () => { calls++; tab.selected = true; tab.syncSelection(); };
  touch(true); render(); assert.equal(calls, 1); assert.equal(tab.toggled, true);
  touch(false); render(); assert.equal(calls, 1); assert.equal(tab.toggled, true);
});

test('duplicate native callbacks cannot dispatch twice before the parent selection arrives', () => {
  const { touch, render, frames, selections } = setup(false);
  touch(true); touch(true); touch(false); touch(true);
  assert.equal(selections(), 1); assert.equal(frames.length, 1);
  render(); touch(true); assert.equal(selections(), 2);
});

test('late frame callbacks cannot overwrite a reappeared tab or dispatch after leaving', () => {
  const { tab, touch, frames, selections } = setup(false);
  touch(true); const old = frames.shift();
  tab.aboutToDisappear(); tab.aboutToAppear(); touch(true);
  assert.equal(tab.resetPending, true);
  old.onFrame(); assert.equal(tab.resetPending, true);
  tab.aboutToDisappear(); tab.selected = true; tab.toggled = false;
  frames.shift().onFrame(); assert.equal(tab.toggled, false);
  touch(true); assert.equal(selections(), 2);
});
