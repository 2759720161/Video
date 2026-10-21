// Execute the real parsers, route builder, queue builder and MPV selection against native mocks.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';

globalThis.__trackTest = { mode: 'auto', replies: [], requests: [], mpvCalls: [] };
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('@kit.') || specifier === 'libmpv_napi.so') {
      return { url: 'mock:' + specifier, shortCircuit: true };
    }
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    let source;
    if (url === 'mock:@kit.NetworkKit') source = `export const http = {
      RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 },
      createHttp() { return { destroy() {}, async request(url, options) {
        globalThis.__trackTest.requests.push(url);
        if (!globalThis.__trackTest.replies.length) throw new Error('Unexpected request');
        return { responseCode: 200, result: JSON.stringify(globalThis.__trackTest.replies.shift()) };
      } }; }
    };`;
    else if (url === 'mock:@kit.CoreFileKit') source = 'export const fileIo = {};';
    else if (url === 'mock:@kit.AbilityKit') source = 'export const common = {};';
    else if (url === 'mock:libmpv_napi.so') source = `export default {
      nativeCreate() {}, nativeInitialize() {}, nativeCommand() {}, nativeCommandAsync() {},
      nativeLoadSubtitleMemory() {}, nativeSetSurfaceId() {},
      nativeSetProperty(ctx, key, value) { globalThis.__trackTest.mpvCalls.push([key, value]); return 0; }
    };`;
    else if (url.endsWith('/utils/Logger.ets')) source = 'export class Logger { info() {} warn() {} error() {} }';
    else if (url.endsWith('/store/PreferencesStore.ets')) source = `export class PreferencesStore {
      static getInstance() { return { async getString() { return globalThis.__trackTest.mode; } }; }
    }`;
    else if (url.endsWith('/providers/base/ProviderRegistry.ets')) source = 'export class ProviderRegistry {}';
    else if (url.endsWith('/services/PlaybackSessionManager.ets')) source = 'export class PlaybackSessionManager {}';
    if (source !== undefined) return { format: 'module', shortCircuit: true, source };
    if (url.endsWith('.ets')) return { format: 'module', shortCircuit: true,
      source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }) };
    return nextLoad(url, context);
  }
});

const { EmbyPlaybackInfo } = await import('../entry/src/main/ets/providers/emby/EmbyPlaybackInfo.ets');
const { EmbyClient } = await import('../entry/src/main/ets/providers/emby/EmbyClient.ets');
const { EmbyServerConfig, EmbyItem } = await import('../entry/src/main/ets/providers/emby/EmbyModels.ets');
const { PlaybackTrackSelection } = await import('../entry/src/main/ets/core/playback/PlaybackTrackSelection.ets');
const { MediaItem } = await import('../entry/src/main/ets/core/media/MediaItem.ets');
const { ProviderPlaybackLauncher } = await import('../entry/src/main/ets/services/ProviderPlaybackLauncher.ets');
const { MpvPlayerEngine } = await import('../entry/src/main/ets/core/player/MpvPlayerEngine.ets');
const { PlayerTrack, PlayerTrackType } = await import('../entry/src/main/ets/core/player/IPlayerEngine.ets');
const state = globalThis.__trackTest;

function source(id = 'version A') {
  return { Id: id, Container: 'mkv', SupportsDirectStream: true,
    DefaultAudioStreamIndex: 0, DefaultSubtitleStreamIndex: -1,
    MediaStreams: [
      { Index: 7, Type: 'Subtitle', Language: 'chi', Codec: 'ass' },
      { Index: 0, Type: 'Audio', Language: 'eng', Codec: 'vorbis', Channels: 2 },
      { Index: 2, Type: 'Video', Codec: 'h264' },
      { Index: 4, Type: 'Audio', Language: 'zho', Codec: 'aac', Channels: 2 },
      { Index: 5, Type: 'Subtitle', Language: 'eng', Codec: 'subrip', IsExternal: true },
      { Index: 9, Type: 'Subtitle', Language: 'eng', Codec: 'ass' }
    ] };
}
function selection(audio = 4, subtitle = 9, variantId = 'version A') {
  return Object.assign(new PlaybackTrackSelection(), { variantId, audioIndex: audio, subtitleIndex: subtitle });
}
async function route(pick, sources = [source()], mode = 'auto', variantId = pick?.variantId ?? '') {
  state.mode = mode;
  state.replies.push({ MediaSources: sources, PlaySessionId: 'test-session' });
  const config = Object.assign(new EmbyServerConfig(), { baseUrl: 'https://emby.invalid',
    userId: 'user', accessToken: 'test-token' });
  const client = new EmbyClient(config);
  const item = Object.assign(new EmbyItem(), { id: 'movie', container: 'mkv' });
  await client.getPlaybackVariants(item);
  const before = state.requests.length;
  assert.equal((await client.getPlaybackSources(item)).length, sources.length);
  assert.equal(state.requests.length, before, 'Track metadata should reuse version metadata');
  return client.getPlaybackRoute(item, variantId, pick);
}

test('parse sparse unordered tracks, retain zero indices, ignore malformed records and localize labels', () => {
  const raw = source();
  raw.MediaStreams.push(null, {}, { Type: 'Audio', Index: -1 }, { Type: 'Audio', Index: 1.5 });
  const parsed = EmbyPlaybackInfo.parse({ MediaSources: [raw] }).mediaSources[0];
  assert.deepEqual(parsed.tracks.map(t => t.index), [0, 4, 5, 7, 9]);
  assert.equal(parsed.defaultAudioIndex, 0);
  assert.equal(parsed.defaultSubtitleIndex, -1);
  assert.equal(parsed.tracks[0].label(), '英语');
  assert.equal(parsed.tracks[0].detail(), 'VORBIS · 2ch');
  assert.equal(parsed.tracks[1].label(), '中文');
});

test('direct playback maps provider indices to per-type embedded ordinals, excluding external subtitles', async () => {
  const result = await route(selection());
  assert.equal(result.audioTrackOrdinal, 1);
  assert.equal(result.subtitleTrackOrdinal, 1);
  assert.equal(result.subtitleUrl, '');
});

test('off is explicit while absent selection leaves engine defaults intact', async () => {
  assert.equal((await route(selection(0, -1))).subtitleTrackOrdinal, -1);
  const result = await route(null);
  assert.equal(result.subtitleTrackOrdinal, -2);
  assert.equal(result.audioTrackOrdinal, -1);
});

test('external subtitle selection creates an authenticated resource without confusing embedded ordinals', async () => {
  const result = await route(selection(4, 5));
  const url = new URL(result.subtitleUrl);
  assert.equal(url.pathname, '/Videos/movie/version%20A/Subtitles/5/Stream.srt');
  assert.equal(url.searchParams.get('api_key'), 'test-token');
  assert.equal(result.subtitleTrackOrdinal, -1);
});

test('external ASS remains ASS for libass rendering', async () => {
  const raw = source();
  raw.MediaStreams.find(t => t.Index === 7).IsExternal = true;
  const result = await route(selection(4, 7), [raw]);
  assert.ok(result.subtitleUrl.includes('/7/Stream.ass?'));
  assert.equal(result.subtitleName, '中文.ass');
});

test('transcoding replaces existing audio/subtitle query parameters rather than duplicating them', async () => {
  const raw = source();
  raw.TranscodingUrl = '/Videos/movie/main.m3u8?AudioStreamIndex=0&SubtitleStreamIndex=7';
  const result = await route(selection(4, -1), [raw], 'transcode');
  const url = new URL(result.url);
  assert.deepEqual(url.searchParams.getAll('AudioStreamIndex'), ['4']);
  assert.deepEqual(url.searchParams.getAll('SubtitleStreamIndex'), ['-1']);
  assert.equal(result.audioTrackOrdinal, 0);
});

test('missing or switched versions never reuse another version\'s stream indices', async () => {
  const result = await route(selection(), [source('version B')]);
  assert.equal(result.audioTrackOrdinal, -1);
  assert.equal(result.subtitleTrackOrdinal, -2);
  const switched = await route(selection(), [source(), source('version B')], 'auto', 'version B');
  assert.equal(switched.audioTrackOrdinal, -1);
});

test('static fallback retains embedded ordinals even when the preference requests transcoding', async () => {
  const result = await route(selection(), [source()], 'transcode');
  assert.equal(result.audioTrackOrdinal, 1);
  assert.equal(result.subtitleTrackOrdinal, 1);
  assert.equal(result.subtitleUrl, '');
});

test('bitmap subtitles use server burn-in when transcoding instead of invalid text extraction', async () => {
  const raw = source();
  raw.MediaStreams.find(t => t.Index === 7).Codec = 'pgssub';
  raw.TranscodingUrl = '/Videos/movie/main.m3u8?SubtitleStreamIndex=-1&SubtitleMethod=External';
  const result = await route(selection(4, 7), [raw], 'transcode');
  const url = new URL(result.url);
  assert.equal(url.searchParams.get('SubtitleStreamIndex'), '7');
  assert.equal(url.searchParams.get('SubtitleMethod'), 'Encode');
  assert.equal(result.subtitleUrl, '');
});

test('queue uses clicked media selection and leaves subsequent episodes independent', () => {
  const current = Object.assign(new MediaItem(), { sourceId: 'server', id: 'episode', playable: true,
    variantId: 'version A', trackSelection: selection() });
  const stale = Object.assign(new MediaItem(), { sourceId: 'server', id: 'episode', playable: true });
  const next = Object.assign(new MediaItem(), { sourceId: 'server', id: 'next', playable: true });
  const queue = ProviderPlaybackLauncher.createQueue('server', current, [stale, next], false);
  assert.equal(queue[0].trackSelection.subtitleIndex, 9);
  assert.equal(queue[0].variantId, 'version A');
  assert.equal(queue[1].trackSelection, null);
});

test('MPV duplicate audio/subtitle IDs select the requested track type', async () => {
  const engine = new MpvPlayerEngine();
  engine.ctxId = 1;
  engine.latestTracks = [Object.assign(new PlayerTrack(), { index: 1, type: PlayerTrackType.audio }),
    Object.assign(new PlayerTrack(), { index: 1, type: PlayerTrackType.subtitle })];
  state.mpvCalls.length = 0;
  await engine.selectTrack(1, PlayerTrackType.subtitle);
  await engine.selectTrack(1, PlayerTrackType.audio);
  await engine.deselectTrack(1);
  assert.deepEqual(state.mpvCalls, [['sid', '1'], ['aid', '1'], ['sid', 'no']]);
});
