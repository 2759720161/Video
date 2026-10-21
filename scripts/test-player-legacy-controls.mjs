// Run with Node 24+. Compare the restored layout with Git and exercise its progress handler.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const current = readFileSync(new URL('../entry/src/main/ets/pages/player/PlayerPage.ets', import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const historical = execFileSync('git', ['show', '2229866:entry/src/main/ets/pages/player/LocalPlayerPage.ets'],
  { cwd: root, encoding: 'utf8' }).replaceAll('\r\n', '\n');

function method(source, name) {
  const start = source.indexOf(`  private ${name}(`);
  assert.notEqual(start, -1, `Missing ${name}`);
  const end = source.indexOf('\n  }', start);
  assert.notEqual(end, -1, `Missing closing brace for ${name}`);
  return source.slice(start, end + 4);
}

for (const name of ['VideoBottomBar', 'LandscapeProgressRow', 'PortraitControlRow', 'VideoInfoRow',
  'ProgressUtilityRow', 'SubtitleToolButton', 'AudioTrackToolButton', 'VideoInfoText',
  'LandscapeControlRow', 'PrimaryPlaybackControls', 'SpeedToolButton', 'CurrentSpeedSymbol', 'SeekControlButton']) {
  test(`${name} retains the 2229866 layout and parameters`, () => {
    assert.equal(method(current, name), method(historical, name));
  });
}

test('V2 controls are not used by the playback page', () => {
  for (const name of ['PlayerTopBar', 'PlayerProgressBar', 'PlayerPrimaryControls', 'PlayerToolBar', 'PlayerToolbarV2']) {
    assert.equal(current.includes(name), false);
  }
  const button = method(current, 'TopSymbolButton');
  assert.ok(button.includes('.width(44)'));
  assert.ok(button.includes('.height(44)'));
  assert.ok(button.includes(".backgroundColor('#00000000')"));
  assert.ok(button.includes('.accessibilityText(accessibilityLabel)'));
});

test('legacy top bar retains its direct aspect and PiP controls plus access to current settings', () => {
  const top = method(current, 'VideoTopBar');
  for (const fragment of ['.height(this.topSafeHeight + 68)', 'sys.symbol.chevron_left',
    '.fontSize(28)', 'this.PiPToolButton()', 'sys.symbol.rectangle_4_group_1',
    'this.leaveFromTopBar()', 'this.openTopMoreMenu()']) assert.ok(top.includes(fragment));
  assert.equal(method(current, 'PiPToolButton').includes('PlaybackQueueOverlay'), false);
});

const mode = { Begin: 0, Moving: 1, End: 2, Click: 3 };
const progress = method(current, 'onProgressChanged');
const progressHandler = new Function('value', 'mode', 'SliderChangeMode',
  progress.slice(progress.indexOf('{') + 1, progress.lastIndexOf('}')));

function player(playing = true, visible = true) {
  const events = [];
  return {
    events, isPlaying: playing, isDraggingProgress: false, wasPlayingBeforeDrag: false,
    positionMs: 0, hasEngine: true,
    shouldShowBottomControlLayer: () => visible,
    playerEngine: { pause: () => events.push('pause'), play: () => events.push('play') },
    pauseAutoHideTimer: () => events.push('stopTimer'),
    seekTo: value => events.push(['seek', value]),
    showControlsWithAutoHide: () => events.push('showControls')
  };
}

test('slider delegates to the current progress handler and preserves duration guards', () => {
  const slider = method(current, 'ProgressSlider');
  assert.ok(slider.includes('this.onProgressChanged(value, mode)'));
  assert.ok(slider.includes('max: this.durationMs > 0 ? this.durationMs : 1'));
  assert.ok(slider.includes('this.shouldShowBottomControlLayer()'));
});

test('dragging a playing video pauses, seeks and resumes', () => {
  const state = player();
  progressHandler.call(state, 0, mode.Begin, mode);
  assert.equal(state.isDraggingProgress, true);
  progressHandler.call(state, 12000, mode.Moving, mode);
  assert.equal(state.positionMs, 12000);
  progressHandler.call(state, 12000, mode.End, mode);
  assert.equal(state.isDraggingProgress, false);
  assert.deepEqual(state.events, ['pause', 'stopTimer', ['seek', 12000], 'play', 'showControls']);
});

test('dragging a paused video does not start playback', () => {
  const state = player(false);
  progressHandler.call(state, 0, mode.Begin, mode);
  progressHandler.call(state, 7000, mode.Click, mode);
  assert.deepEqual(state.events, ['stopTimer', ['seek', 7000], 'showControls']);
});

test('hidden controls ignore progress input', () => {
  const state = player(true, false);
  for (const value of Object.values(mode)) progressHandler.call(state, 9000, value, mode);
  assert.deepEqual(state.events, []);
  assert.equal(state.positionMs, 0);
  assert.equal(state.isDraggingProgress, false);
});
