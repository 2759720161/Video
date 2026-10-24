import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = file => readFileSync(new URL('../entry/src/main/' + file, import.meta.url), 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'transform' });
const Diagnostic = new Function(compile(read('ets/core/player/MpvDiagnostic.ets')) + ';return MpvDiagnostic;')();

test('native network, seek, demux and decoder messages become fixed diagnostic fields', () => {
  assert.equal(Diagnostic.stage('ffmpeg/http'), 'network');
  assert.equal(Diagnostic.stage('demux/lavf'), 'demux');
  assert.equal(Diagnostic.stage('vd'), 'decoder');
  assert.equal(Diagnostic.stage('vo/gpu-next'), 'video_output');
  assert.equal(Diagnostic.stage('cplayer'), 'player');
  assert.equal(Diagnostic.summary('http: HTTP/1.1 206 Partial Content'), 'http_status=206');
  assert.match(Diagnostic.summary('Range: bytes=1213388595-'), /range=1213388595-/);
  assert.match(Diagnostic.summary('TLS connection timed out'), /event=tls.*issue=timeout/);
  assert.match(Diagnostic.summary('HTTP error 403 Forbidden'), /http_status=403.*issue=authorization/);
  assert.equal(Diagnostic.summary('Using hardware decoding (ohcodec-copy).'), 'event=hardware_decode');
});

test('diagnostics never echo authentication, URLs, opaque tickets or arbitrary response text', () => {
  const secret = 'fixture-super-secret';
  const messages = [
    'GET /proxy/uuid?pst=' + secret + ' HTTP/1.1',
    'Cookie: sid=' + secret, 'Authorization: Bearer ' + secret,
    'Opening: https://media.invalid/a.mp4?auth_key=' + secret,
    'Failed to open https://media.invalid/a?token=' + secret,
    'HTTP/1.1 403 ' + secret, 'backend response: ' + secret,
    'Set-Cookie: ' + secret, 'Referer: https://account.invalid/' + secret
  ];
  for (const text of messages) {
    const result = Diagnostic.summary(text);
    assert.ok(!result.includes(secret)); assert.ok(!result.includes('http://'));
    assert.ok(!result.includes('https://')); assert.ok(!result.includes('pst='));
  }
});

function engineFixture() {
  const output = [];
  const Logger = class { info(...args) { output.push(args); } warn(...args) { output.push(args); } error(...args) { output.push(args); } };
  const napi = { nativeCreate() {}, nativeInitialize() {}, nativeCommand() {}, nativeCommandAsync() {},
    nativeLoadSubtitleMemory() {}, nativeSetProperty() {}, nativeSetSurfaceId() {} };
  const Engine = new Function('Logger', 'mpvNapi', 'PlayerState', 'MpvDiagnostic',
    compile(read('ets/core/player/MpvPlayerEngine.ets')) + ';return MpvPlayerEngine;')(Logger, napi, class {}, Diagnostic);
  const engine = new Engine(); output.length = 0;
  engine.isInitialized = true; engine.ctxId = 1;
  return { engine, output };
}

test('actual player log handler emits bounded sanitized messages and retains last native stage', () => {
  const { engine, output } = engineFixture();
  const event = { ctxId: 1, eventId: 2, logPrefix: 'ffmpeg', logLevel: 'debug',
    logText: 'HTTP/1.1 206 fixture-secret' };
  for (let i = 0; i < 1000; i++) engine.handleMpvEvent(event);
  assert.equal(output.length, 256); assert.equal(engine.diagnosticLogCount, 1000);
  assert.equal(engine.diagnosticLastStage, 'network');
  event.logLevel = 'error'; event.logPrefix = 'demux/lavf'; event.logText = 'Failed fixture-secret';
  engine.handleMpvEvent(event); assert.equal(output.length, 257);
  assert.equal(engine.diagnosticLastStage, 'demux');
  assert.ok(!JSON.stringify(output).includes('fixture-secret'));
  // Hidden header lines do not consume the useful diagnostic output budget.
  const other = engineFixture(); event.logLevel = 'debug'; event.logText = 'Cookie: fixture-secret';
  other.engine.handleMpvEvent(event); assert.equal(other.output.length, 0);
});

test('native log subscription respects selected debug families instead of dropping debug at info level', () => {
  const source = read('cpp/mpv_event_handler.cpp');
  assert.equal((source.match(/mpv_wrapper_request_log_messages\(ctxId, "terminal-default"\)/g) ?? []).length, 2);
  assert.equal(source.includes('mpv_wrapper_request_log_messages(ctxId, "info")'), false);
});
