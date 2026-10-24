import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/providers/catvod/CatNodeConfigurationScript.ets', import.meta.url), 'utf8');
const Feedback = new Function(stripTypeScriptTypes(source.replace('export class', 'class'), { mode: 'transform' }) +
  '; return CatNodeConfigurationScript;')();
const script = Feedback.build();
const defer = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

function setup() {
  const button = { disabled: false, isConnected: true, textContent: '扫码后点我' };
  const state = { status: 200, result: { code: 0, status: 'waiting' }, gate: null, failure: null, abortOnly: false };
  const calls = { fetch: [], logs: [], messages: [], timers: new Map(), clicks: [] };
  let timerId = 0;
  const window = { async fetch(input, options) {
    calls.fetch.push({ input, options });
    if (state.abortOnly) await new Promise((resolve, reject) => options.signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
    if (state.gate) await state.gate.promise;
    if (state.failure) throw state.failure;
    return new Response(JSON.stringify(state.result), { status: state.status });
  }, setMessage(text, bad) { calls.messages.push({ text, bad }); } };
  const context = { window, location: new URL('http://127.0.0.1:43009/website'), URL, AbortController,
    console: { info: value => calls.logs.push(value) }, queueMicrotask,
    setTimeout(fn, ms) { const id = ++timerId; calls.timers.set(id, { fn, ms }); return id; },
    clearTimeout(id) { calls.timers.delete(id); },
    document: { getElementById: id => id === 'confirmLoginBtn' ? button : null,
      addEventListener(type, fn) { if (type === 'click') calls.clicks.push(fn); } } };
  runInNewContext(script, context);
  const poll = () => window.fetch('/website/api/login/poll', { method: 'POST', body: '{"taskId":"secret-task","provider":"quark"}' });
  const click = () => { for (const fn of calls.clicks) fn({ target: { closest: () => button } }); };
  return { state, calls, button, context, window, poll, click };
}

test('manual confirmation shows progress immediately and releases the button with a waiting response', async () => {
  const f = setup(); f.state.gate = defer(); f.click(); const pending = f.poll();
  await Promise.resolve();
  assert.equal(f.button.disabled, true); assert.equal(f.button.textContent, '正在确认…'); assert.equal(f.calls.messages.length, 0);
  f.state.gate.resolve(); const response = await pending;
  assert.deepEqual(await response.json(), { code: 0, status: 'waiting' });
  assert.equal(f.button.disabled, false); assert.equal(f.button.textContent, '尚未确认，点击重试');
  assert.equal(f.calls.timers.size, 0);
  assert.ok(f.calls.logs.some(line => line.includes('phase=response action=poll status=200:waiting')));
  assert.ok(f.calls.logs.every(line => !/secret-task|taskId|cookie|token|127\.0|quark/i.test(line)));
});

test('success and expired tasks have explicit terminal feedback', async () => {
  for (const status of ['success', 'expired']) {
    const f = setup(); f.state.result = { code: 0, status, terminal: true }; await f.poll();
    assert.equal(f.button.disabled, true);
    assert.equal(f.button.textContent, status === 'success' ? '登录成功' : '请重新扫码');
  }
});

test('HTTP, malformed and network failures release confirmation for retry without exposing request secrets', async () => {
  const f = setup(); f.state.status = 500; f.state.result = { code: 1, msg: 'private upstream value' };
  assert.equal((await f.poll()).status, 500);
  assert.equal(f.button.disabled, false); assert.equal(f.button.textContent, '确认失败，点击重试');
  f.state.status = 200; f.state.result = null; await f.poll();
  assert.equal(f.button.textContent, '确认失败，点击重试');
  f.state.failure = new Error('private URL and token');
  await assert.rejects(f.poll(), /private URL/);
  assert.equal(f.button.disabled, false); assert.equal(f.calls.timers.size, 0);
  assert.ok(f.calls.logs.every(line => !/private|secret-task|taskId/.test(line)));
});

test('a stalled confirmation is aborted after the complete upstream exchange budget and can be retried', async () => {
  const f = setup(); f.state.abortOnly = true;
  const pending = f.poll();
  const timer = [...f.calls.timers.values()][0]; assert.equal(timer.ms, 55000); timer.fn();
  await assert.rejects(pending, /登录确认超时/);
  assert.equal(f.button.disabled, false); assert.equal(f.button.textContent, '确认超时，点击重试');
  assert.equal(f.calls.messages.at(-1).bad, true); assert.equal(f.calls.timers.size, 0);
  f.state.abortOnly = false; await f.poll(); assert.equal(f.button.textContent, '尚未确认，点击重试');
});

test('clicks ignored by the source after a task is cleared produce a visible restart message', async () => {
  const f = setup(); f.click(); await Promise.resolve();
  assert.equal(f.calls.fetch.length, 0); assert.equal(f.button.textContent, '请重新扫码');
  assert.match(f.calls.messages[0].text, /登录任务已结束/);
  f.button.disabled = true; f.click(); await Promise.resolve(); assert.equal(f.calls.messages.length, 1);
});

test('the adapter installs once, preserves external/general requests and ignores detached QR controls', async () => {
  const f = setup(); const wrapped = f.window.fetch; runInNewContext(script, f.context);
  assert.equal(f.window.fetch, wrapped); assert.equal(f.calls.clicks.length, 1);
  const options = { method: 'POST', body: 'untouched' };
  await f.window.fetch('https://external.invalid/website/api/login/poll', options);
  await f.window.fetch('/website/api/db', options);
  assert.equal(f.calls.fetch[0].options, options); assert.equal(f.calls.fetch[1].options, options);
  assert.equal(f.calls.logs.length, 0);
  f.state.gate = defer(); const pending = f.poll(); f.button.isConnected = false;
  f.state.gate.resolve(); await pending; assert.equal(f.button.textContent, '正在确认…');
  const other = setup(); other.context.location = new URL('https://external.invalid/website');
  const original = other.window.fetch;
  runInNewContext(script, other.context); assert.equal(other.window.fetch, original);
});
