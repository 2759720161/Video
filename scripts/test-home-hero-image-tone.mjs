import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/services/media/' + name + '.ets', import.meta.url), 'utf8');
const load = name => new Function(stripTypeScriptTypes(read(name).replace(/export class /g, 'class '), { mode: 'transform' }) + `;return ${name};`)();
const Tone = load('HomeHeroImageTone'), Colors = load('HomeHeroColors');
const rgb = color => [1, 3, 5].map(i => parseInt(color.slice(i, i + 2), 16));
const span = color => Math.max(...rgb(color)) - Math.min(...rgb(color));
const pixels = regions => new Uint8Array(regions.flatMap(([count, color]) => Array.from({ length: count }, () => color).flat()));

test('black-heavy artwork with local red and white regions produces a muted whole-image tone', () => {
  const sample = Tone.analyze(pixels([[80, [16, 16, 16, 255]], [10, [224, 48, 80, 255]], [10, [240, 240, 240, 255]]]));
  assert.equal(sample.blackShare, 0.8); assert.equal(sample.accentShare, 0.1);
  assert.ok(span(sample.tone) < 20);
  for (const base of [0xffffffff, 0xfff2f2f2, 0xff121212, 0xff000000]) assert.ok(span(Colors.surface(sample.tone, base)) < 12);
  assert.notEqual(Colors.surface(sample.tone, 0xffffffff), '#f2a8b6');
});

test('a large blue region outweighs a smaller brighter red region by actual coverage', () => {
  const sample = Tone.analyze(pixels([[60, [24, 56, 120, 255]], [30, [16, 16, 16, 255]], [10, [255, 0, 0, 255]]]));
  assert.equal(sample.blackShare, 0.3); assert.equal(sample.accentShare, 0.6);
  const [r, g, b] = rgb(sample.tone); assert.ok(b > g && g > r);
});

test('a tiny saturated logo cannot color an otherwise neutral poster', () => {
  const sample = Tone.analyze(pixels([[790, [200, 200, 200, 255]], [200, [20, 20, 20, 255]], [10, [255, 0, 0, 255]]]));
  assert.equal(sample.accentShare, 0.01); assert.ok(span(sample.tone) <= 5);
});

test('fully colored artwork retains its tone and neutral artwork stays neutral', () => {
  for (const color of [[224, 48, 80, 255], [24, 56, 88, 255], [255, 255, 0, 255],
    [0, 0, 0, 255], [255, 255, 255, 255], [128, 128, 128, 255]]) {
    const sample = Tone.analyze(pixels([[100, color]]));
    assert.deepEqual(rgb(sample.tone), color.slice(0, 3));
  }
});

test('transparent RGB is excluded and premultiplied pixels are unpremultiplied before weighting', () => {
  const straight = Tone.analyze(pixels([[10, [200, 100, 50, 128]], [90, [0, 255, 255, 0]]]));
  const premul = Tone.analyze(pixels([[10, [100, 50, 25, 128]], [90, [255, 0, 0, 0]]]), true);
  assert.deepEqual(rgb(straight.tone), [200, 100, 50]);
  assert.ok(rgb(premul.tone).every((v, i) => Math.abs(v - rgb(straight.tone)[i]) <= 1));
  assert.equal(straight.blackShare, 0); assert.equal(premul.blackShare, 0);
  assert.equal(Tone.analyze(pixels([[10, [255, 0, 0, 0]]])).tone, '');
  assert.equal(Tone.analyze(pixels([[10, [255, 0, 0, 0]]]), false, true).tone, '#ff0000');
});

test('semi-transparent regions contribute in proportion to visible coverage', () => {
  const sample = Tone.analyze(pixels([[100, [255, 0, 0, 1]], [100, [128, 128, 128, 255]]]));
  assert.ok(span(sample.tone) <= 2);
});

test('increasing near-black coverage reduces color strength continuously', () => {
  let previous = Infinity;
  for (let black = 0; black <= 100; black++) {
    const sample = Tone.analyze(pixels([[black, [16, 16, 16, 255]], [100 - black, [224, 48, 80, 255]]]));
    assert.ok(span(sample.tone) <= previous + 1); previous = span(sample.tone);
  }
});

test('invalid buffers are rejected and sample order does not bias color statistics', () => {
  for (const data of [new Uint8Array(), new Uint8Array(3), new Uint8Array(5)]) assert.equal(Tone.analyze(data).tone, '');
  const regions = [[70, [16, 16, 16, 255]], [15, [24, 40, 64, 255]], [10, [224, 48, 80, 255]], [5, [240, 240, 240, 255]]];
  assert.deepEqual(Tone.analyze(pixels(regions)), Tone.analyze(pixels([...regions].reverse())));
});
