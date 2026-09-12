// Node 24+: run the platform-independent Hypium cases against the actual .ets sources.
// This validates business logic only; the HarmonyOS build validates ArkTS compatibility.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const hypiumAdapter = `
  import assert from 'node:assert/strict';
  import { describe, it as test } from 'node:test';
  export { describe };
  export function it(name, filter, body) { test(name, body); }
  export function expect(actual) {
    return {
      assertEqual(expected) { assert.strictEqual(actual, expected); },
      assertTrue() { assert.strictEqual(actual, true); },
      assertFalse() { assert.strictEqual(actual, false); }
    };
  }
`;

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === '@ohos/hypium') {
      return { url: 'test:hypium-adapter', shortCircuit: true };
    }
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === 'test:hypium-adapter') {
      return { format: 'module', source: hypiumAdapter, shortCircuit: true };
    }
    if (url.endsWith('.ets')) {
      const source = stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' });
      return { format: 'module', source, shortCircuit: true };
    }
    return nextLoad(url, context);
  }
});

const { default: playbackModelsTest } = await import('../entry/src/test/PlaybackModels.test.ets');
playbackModelsTest();
const { default: embyDetailPresentationTest } = await import('../entry/src/test/EmbyDetailPresentation.test.ets');
embyDetailPresentationTest();
