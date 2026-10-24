import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*\r?\n/gm, '').replace(/export class /g, 'class '), { mode: 'transform' });
const Layout = new Function(compile(read('components/media/carousel/HomeCarouselLayout.ets')) + ';return HomeCarouselLayout;')();
const Motion = new Function(compile(read('components/media/carousel/HomeCarouselMotion.ets')) + ';return HomeCarouselMotion;')();
const Projection = new Function('HomeCarouselLayout', 'HomeCarouselMotion',
  compile(read('components/media/carousel/HomeCarouselProjection.ets')) + ';return HomeCarouselProjection;')(Layout, Motion);
const Item = new Function(compile(read('components/media/carousel/HomeCarouselItem.ets')) + ';return HomeCarouselItem;')();
const shared = read('components/media/carousel/HomeMediaCarousel.ets');
const methods = shared.slice(shared.indexOf('  private syncItems('), shared.indexOf('  build()'));
const frameClasses = shared.includes('class HomeCarouselTapFrame') ? shared.slice(shared.indexOf('class HomeCarouselTapFrame')) : '';
const touchBody = shared.split('.onTouch((event: TouchEvent) => {')[1].split('\n          })')[0];
const makeCarousel = new Function('HomeCarouselMotion', 'HomeCarouselItem', 'HomeCarouselLayout', 'setTimeout', 'clearTimeout', 'FrameCallback',
  compile(frameClasses) +
  compile(`class Carousel { ${methods} }`) + ';return Carousel;');
const touchHandler = new Function('HomeCarouselMotion', 'TouchType', compile(`function functionTouch(event: { type: number }): void { ${touchBody} }`) + ';return functionTouch;');
const TouchType = { Down: 0, Up: 1, Cancel: 2 };
const fixture = (count = 3, deferFrames = false) => {
  const opened = [], selected = [], moved = [], commands = [], timings = [], frames = [];
  let nativeDuration = Motion.AUTO_DURATION_MS, nativeCurve = 'auto';
  let now = 0, nextId = 0;
  const pending = new Map();
  const clock = {
    pending,
    set(callback, delay) { const id = ++nextId; pending.set(id, { callback, at: now + delay }); return id; },
    clear(id) { pending.delete(id); },
    advance(ms) {
      now += ms;
      for (const [id, task] of [...pending]) {
        if (task.at <= now) { pending.delete(id); task.callback(); }
      }
    }
  };
  const Carousel = makeCarousel(Motion, Item, Layout, clock.set, clock.clear, class FrameCallback {});
  const commit = () => {
    nativeDuration = page.switchDuration();
    nativeCurve = page.interactionPaused && page.manualDuration === Motion.DRAG_DURATION_MS ? 'drag' : 'auto';
  };
  const flushFrame = () => { commit(); for (const task of frames.splice(0)) task.onIdle(1000000); };
  const timing = () => timings.push({ duration: nativeDuration, curve: nativeCurve });
  const items = Array.from({ length: count }, (_, i) => Object.assign(new Item(), { id: 'source:film:' + i,
    title: '作品' + i, artworkUrl: 'https://images.test/' + i }));
  const page = Object.assign(new Carousel(), { items, version: 1, currentIndex: 0, displayIndex: 0,
    visualCenter: 0, itemLength: 0, viewportWidth: 360, contentKey: '', animating: false, touching: false,
    isActive: true, foreground: true, visible: true,
    alive: true, interactionTimer: -1, interactionTicket: 0, interactionPaused: false,
    manualDuration: Motion.TAP_DURATION_MS, renderedItems: [], metadataKey: '', diagnosticKind: 'cat',
    moveTicket: 0, pendingSlot: -1,
    syncTrace: { sample: (_context, _kind, _position, apply) => apply(), flush() {} },
    getUIContext: () => ({ postFrameCallback: task => { frames.push(task); if (!deferFrames) flushFrame(); } }),
    controller: {
      changeIndex: (...args) => { timing(); commands.push(['changeIndex', ...args]); moved.push(args); },
      showNext: () => { timing(); commands.push(['showNext']); moved.push([(page.displayIndex + 1) % Motion.slotCount(count), true]); },
      showPrevious: () => { const slots = Motion.slotCount(count); commands.push(['showPrevious']);
        timing(); moved.push([(page.displayIndex - 1 + slots) % slots, true]); }
    }, onOpen: id => opened.push(id),
    onIndexChanged: index => selected.push(index) });
  page.onProgress = () => {};
  page.syncItems();
  const touch = type => touchHandler(Motion, TouchType).call(page, { type });
  return { page, items, opened, selected, moved, commands, clock, timings, frames, flushFrame, touch };
};
const near = (actual, expected, epsilon = 1e-8) => assert.ok(Math.abs(actual - expected) < epsilon, `${actual} != ${expected}`);
const sample = (page, index, position, length = 200) => page.scrollPosition(index,
  position * (length + Layout.GAP) / length, length);
const wrap = (value, count) => ((value % count) + count) % count;
// ArkUI resolves changeIndex within the current cycle; directional commands step the native cursor.
const nativeLanding = (command, cursor, slots) => command[0] === 'showNext' ? cursor + 1 :
  command[0] === 'showPrevious' ? cursor - 1 : Math.floor(cursor / slots) * slots + command[1];

test('portrait turntable fits phones and tablets with bounded poster and stage dimensions', () => {
  for (const width of [240, 320, 360, 390, 600, 840, 1200, 1320]) {
    const margin = Layout.margin(width), card = Layout.cardWidth(width);
    assert.ok(margin >= 8); assert.ok(card >= 144 && card <= 260);
    assert.ok(card < width); assert.ok(Math.abs(card + 2 * (margin + Layout.GAP) - Layout.stageWidth(width)) < 0.0001);
    assert.equal(Layout.imageHeight(width), Math.round(card * 3 / 2));
    assert.equal(Layout.cardHeight(width), Layout.imageHeight(width));
    assert.equal(Layout.stageHeight(width), Layout.cardHeight(width) + 32);
    assert.ok(Layout.stageWidth(width) <= 720);
  }
  assert.equal(Layout.width(NaN), 360); assert.equal(Layout.width(0), 360);
});

test('rounded image bounds fit the artwork itself for portrait, square and landscape sources', () => {
  for (const viewport of [240, 360, 390, 840, 1320]) {
    for (const ratio of [0.02, 0.5, 2 / 3, 0.75, 1, 16 / 9, 3, 100]) {
      const width = Layout.artworkWidth(viewport, ratio), height = Layout.artworkHeight(viewport, ratio);
      assert.ok(width > 0 && width <= Layout.cardWidth(viewport) + 1e-8);
      assert.ok(height > 0 && height <= Layout.imageHeight(viewport) + 1e-8);
      assert.ok(Math.abs(width / height - ratio) < 1e-8);
      assert.ok(Math.abs(width - Layout.cardWidth(viewport)) < 1e-8 ||
        Math.abs(height - Layout.imageHeight(viewport)) < 1e-8);
      assert.ok(Layout.artworkRadius(viewport, ratio) <= Math.min(width, height) / 2);
    }
  }
  for (const [width, height] of [[0, 100], [100, 0], [-1, 100], [NaN, 100], [Infinity, 100]]) {
    assert.equal(Layout.artworkRatio(width, height), 2 / 3);
  }
});

test('poster sizing waits for valid image data and ignores completions or errors from an older URL', () => {
  const source = read('components/media/carousel/HomeCarouselCard.ets');
  const methods = source.slice(source.indexOf('  private resetArtwork('), source.indexOf('  @Builder'));
  const Card = new Function('HomeCarouselLayout', compile(`class Card { ${methods} }`) + ';return Card;')(Layout);
  const errors = [];
  const card = Object.assign(new Card(), { artworkUrl: 'current', failed: false, decoded: false,
    sourceRatio: 2 / 3, onArtworkError: url => errors.push(url) });
  card.artworkLoaded('current', 1920, 1080, 0);
  assert.equal(card.sourceRatio, 16 / 9); assert.equal(card.decoded, false);
  card.artworkLoaded('current', 1920, 1080, 1); assert.equal(card.decoded, true);
  card.artworkUrl = 'new'; card.resetArtwork();
  card.artworkLoaded('current', 300, 400, 1); card.artworkFailed('current');
  assert.equal(card.sourceRatio, 2 / 3); assert.equal(card.decoded, false); assert.equal(card.failed, false);
  assert.deepEqual(errors, []);
  card.artworkLoaded('new', NaN, 500, 1); assert.equal(card.decoded, false);
  card.artworkFailed('new'); card.artworkLoaded('new', 300, 400, 1);
  assert.equal(card.failed, true); assert.equal(card.decoded, false); assert.deepEqual(errors, ['new']);
});

test('both providers use one native turntable with full posters and unrotated captions', () => {
  const card = read('components/media/carousel/HomeCarouselCard.ets');
  assert.ok(read('pages/catvod/CatVodHeroBanner.ets').includes('HomeMediaCarousel({'));
  assert.ok(read('pages/emby/EmbyHomeContent.ets').includes('HomeMediaCarousel({'));
  assert.ok(shared.includes('.prevMargin(')); assert.ok(shared.includes('.nextMargin('));
  assert.ok(shared.includes('.interval(5000)')); assert.ok(shared.includes('.duration(this.switchDuration())'));
  assert.ok(shared.includes('.curve(this.interactionPaused && this.manualDuration === HomeCarouselMotion.DRAG_DURATION_MS ? this.manualCurve : this.autoCurve)'));
  assert.ok(card.includes('.objectFit(ImageFit.Contain)'));
  assert.equal(card.includes('Text(this.title)'), false);
  assert.ok(shared.indexOf('Text(item.title)') > shared.indexOf('.onContentDidScroll('));
  assert.ok(shared.includes('posePosition: this.slidePosition(index)'));
  assert.ok(card.includes('.transform3D(this.faceTransform())'));
  assert.ok(card.includes('this.getUIContext().vp2px(1)'));
  assert.ok(shared.includes('shadeOpacity: HomeCarouselMotion.shadeOpacity(this.slidePosition(index))'));
  assert.ok(shared.includes('faceOpacity: HomeCarouselMotion.opacity(this.slidePosition(index))'));
  assert.equal(shared.includes('.brightness('), false);
  assert.equal(card.includes('.brightness('), false);
  assert.equal(shared.includes('.rotate('), false);
  assert.equal(shared.includes('.opacity(HomeCarouselMotion.opacity('), false);
  assert.equal(shared.includes('perspective: 1000'), false);
  assert.equal(card.includes('.radialGradient('), false); assert.equal(card.includes('.linearGradient('), false);
});

const projectPoint = (matrix, x, y) => {
  const w = matrix[3] * x + matrix[7] * y + matrix[15];
  assert.ok(w > 0);
  return { x: (matrix[0] * x + matrix[4] * y + matrix[12]) / w,
    y: (matrix[1] * x + matrix[5] * y + matrix[13]) / w };
};

test('actual 3D matrices give side posters opposite sloping edges instead of flat rectangles at rest', () => {
  for (const viewport of [240, 360, 600, 840]) {
    for (const ratio of [0.5, 2 / 3, 1, 16 / 9]) {
      const width = Layout.artworkWidth(viewport, ratio), height = Layout.artworkHeight(viewport, ratio);
      for (const side of [-1, 1]) {
        const values = Projection.matrixValues(side, viewport, 1);
        const topLeft = projectPoint(values, -width / 2, -height / 2);
        const topRight = projectPoint(values, width / 2, -height / 2);
        const bottomLeft = projectPoint(values, -width / 2, height / 2);
        const bottomRight = projectPoint(values, width / 2, height / 2);
        assert.ok(Math.abs(topLeft.y - topRight.y) > height * 0.035);
        assert.ok((topLeft.y - topRight.y) * side > 0, 'near edge must be taller, mirrored on opposite sides');
        assert.ok((bottomLeft.y - bottomRight.y) * side < 0);
        assert.ok(Math.abs(values[3]) > 0, 'a genuine projective coefficient must reach transform3D');
      }
    }
  }
});

test('actual 3D matrix corners stay consistent across pixel densities and preserve the unwarped center', () => {
  for (const viewport of [240, 360, 840]) {
    const width = Layout.cardWidth(viewport), height = Layout.cardHeight(viewport);
    const identityFace = Projection.matrixValues(0, viewport, 1);
    for (const [x, y] of [[-width / 2, -height / 2], [width / 2, height / 2], [0, 0]]) {
      const center = projectPoint(identityFace, x, y); near(center.x, x); near(center.y, y);
      for (const p of [-1.5, -1, -0.5, 0, 0.5, 1, 1.5]) {
        const expected = projectPoint(Projection.matrixValues(p, viewport, 1), x, y);
        for (const density of [1.5, 2, 3, 4]) {
          const scaled = projectPoint(Projection.matrixValues(p, viewport, density), x * density, y * density);
          near(scaled.x / density, expected.x); near(scaled.y / density, expected.y);
        }
      }
    }
  }
});

test('center and side poses are continuous, mirrored, bounded and safe for invalid input', () => {
  assert.equal(Math.abs(Motion.angle(0)), 0); assert.equal(Motion.scale(0), 1); assert.equal(Motion.opacity(0), 1);
  for (const value of [0.01, 0.2, 0.5, 0.99, 1, 2, 100]) {
    assert.equal(Motion.angle(-value), -Motion.angle(value));
    assert.equal(Motion.offsetX(-value, 200, Layout.GAP), -Motion.offsetX(value, 200, Layout.GAP));
    assert.equal(Motion.scale(-value), Motion.scale(value));
    assert.ok(Motion.scale(value) >= 0.8 - 1e-10 && Motion.scale(value) <= 1);
    assert.ok(Math.abs(Motion.angle(value)) <= 46);
    assert.ok(Motion.opacity(value) >= 0 && Motion.opacity(value) <= 1);
    assert.ok(Motion.shadeOpacity(value) >= 0 && Motion.shadeOpacity(value) <= 0.36 + 1e-10);
    assert.ok(Motion.offsetY(value) >= 0 && Motion.offsetY(value) <= 14);
    assert.ok(Motion.offsetZ(value) >= -64 && Motion.offsetZ(value) <= 0);
  }
  assert.equal(Motion.scale(NaN), 1); assert.equal(Motion.position(Infinity), 0);
  assert.ok(Math.abs(Motion.angle(0.5001) - Motion.angle(0.5)) < 0.01);
});

test('pose easing settles smoothly at the center and side positions, without a hard slope change', () => {
  for (const boundary of [0, 1, -1]) {
    for (const property of ['angle', 'scale', 'opacity', 'shadeOpacity', 'offsetY', 'offsetZ']) {
      const left = Motion[property](boundary - 0.0001), right = Motion[property](boundary + 0.0001);
      assert.ok(Math.abs(left - right) < 0.00001, property + ' at ' + boundary);
    }
  }
  for (let p = 0; p <= 1; p += 0.05) {
    assert.ok(Math.abs(Motion.focusWeight(-p) + Motion.focusWeight(1 - p) - 1) < 1e-10);
  }
});

test('pose acceleration joins continuously at the center, side and outer limits', () => {
  const h = 0.00001;
  const properties = ['angle', 'scale', 'opacity', 'shadeOpacity', 'offsetY', 'offsetZ', 'captionOffset'];
  const functions = properties.map(property => [property, x => Motion[property](x)]);
  functions.push(['offsetX', x => Motion.offsetX(x, 260, Layout.GAP)]);
  for (const boundary of [-2, -1, 0, 1, 2]) {
    for (const [property, f] of functions) {
      const leftVelocity = (f(boundary) - f(boundary - h)) / h;
      const rightVelocity = (f(boundary + h) - f(boundary)) / h;
      const leftAcceleration = (f(boundary) - 2 * f(boundary - h) + f(boundary - 2 * h)) / (h * h);
      const rightAcceleration = (f(boundary + 2 * h) - 2 * f(boundary + h) + f(boundary)) / (h * h);
      assert.ok(Math.abs(leftVelocity - rightVelocity) < 0.001, `${property} velocity at ${boundary}`);
      assert.ok(Math.abs(leftAcceleration) < 0.08, `${property} left acceleration at ${boundary}: ${leftAcceleration}`);
      assert.ok(Math.abs(rightAcceleration) < 0.08, `${property} right acceleration at ${boundary}: ${rightAcceleration}`);
    }
  }
});

test('composed native travel, depth and height remain monotonic without a second spread or reversal', () => {
  let previousY = 0, previousDepth = 0, previousScale = 1, previousOpacity = 1, previousX = 0;
  for (let step = 0; step <= 2000; step++) {
    const position = step / 1000;
    const y = Motion.offsetY(position), depth = -Motion.offsetZ(position);
    const scale = Motion.scale(position), opacity = Motion.opacity(position);
    const x = position * (260 + Layout.GAP) + Motion.offsetX(position, 260, Layout.GAP);
    assert.ok(y >= previousY - 1e-10 && depth >= previousDepth - 1e-10);
    assert.ok(scale <= previousScale + 1e-10 && opacity <= previousOpacity + 1e-10);
    assert.ok(x >= previousX - 1e-10);
    near(Motion.offsetY(-position), y); near(Motion.offsetZ(-position), -depth);
    previousY = y; previousDepth = depth; previousScale = scale; previousOpacity = opacity; previousX = x;
  }
  for (const width of [144, 187.2, 260]) {
    near(width + Layout.GAP + Motion.offsetX(1, width, Layout.GAP), width * 0.62);
  }
});

// Conservative bounds for a scaled Y-rotated plane, evaluated in vp. This checks the geometry;
// it does not simulate native rasterization, hit dispatch or the device's compositor.
const faceBounds = (viewport, position) => {
  const width = Layout.cardWidth(viewport), perspective = Layout.perspectiveVp(viewport);
  const angle = Motion.angle(position) * Math.PI / 180, scale = Motion.scale(position);
  const nearestZ = Motion.offsetZ(position) + width * scale / 2 * Math.abs(Math.sin(angle));
  const factor = perspective / (perspective - nearestZ);
  return { center: position * (width + Layout.GAP) + Motion.offsetX(position, width, Layout.GAP),
    halfWidth: width * scale * Math.cos(angle) / 2 * factor,
    halfHeight: Layout.cardHeight(viewport) * scale / 2 * factor + Motion.offsetY(position) };
};

test('resting composition overlaps neighboring opaque posters while keeping their outer faces visible', () => {
  for (const viewport of [240, 320, 360, 390, 600, 840, 1200, 1320]) {
    const width = Layout.cardWidth(viewport), center = faceBounds(viewport, 0), side = faceBounds(viewport, 1);
    const overlap = center.halfWidth + side.halfWidth - side.center;
    assert.ok(overlap >= width * 0.18 && overlap <= width * 0.26, `overlap at ${viewport}: ${overlap}`);
    const stageHalf = Layout.stageWidth(viewport) / 2;
    const exposed = Math.min(stageHalf, side.center + side.halfWidth) - center.halfWidth;
    assert.ok(exposed >= 32, `exposed side at ${viewport}: ${exposed}`);
    assert.ok(Motion.depth(0) > Motion.depth(1));
    assert.equal(Motion.opacity(1), 1); assert.equal(Motion.opacity(2), 0);
    assert.ok(Motion.shadeOpacity(1) > Motion.shadeOpacity(0));
  }
});

test('crossing faces have clearance at paint-order handoff and all poses fit the reserved stage height', () => {
  for (const viewport of [240, 360, 600, 840, 1320]) {
    for (const progress of [0.4995, 0.5, 0.5005]) {
      const outgoing = faceBounds(viewport, -progress), incoming = faceBounds(viewport, 1 - progress);
      const gap = incoming.center - outgoing.center - incoming.halfWidth - outgoing.halfWidth;
      assert.ok(gap > Layout.cardWidth(viewport) * 0.03, `handoff gap at ${viewport}: ${gap}`);
    }
    for (let step = 0; step <= 400; step++) {
      const pose = faceBounds(viewport, step / 200);
      assert.ok(pose.halfHeight <= Layout.stageHeight(viewport) / 2, `vertical bounds at ${viewport}`);
    }
  }
  assert.ok(shared.includes('.zIndex(HomeCarouselMotion.depth(this.slidePosition(index)))'));
  assert.ok(shared.includes('.cachedCount(1, true).clip(false)'));
  assert.ok(shared.includes('.hitTestBehavior(Math.abs(this.slidePosition(index)) <= 1.01 ? HitTestMode.Default : HitTestMode.None)'));
});

test('native timing curves stay monotonic without overshoot, and manual start avoids the previous kick', () => {
  const curves = [...shared.matchAll(/private (autoCurve|manualCurve) = curves\.cubicBezierCurve\(([^)]+)\)/g)];
  assert.equal(curves.length, 2);
  const coordinate = (t, a, b) => 3 * (1 - t) ** 2 * t * a + 3 * (1 - t) * t * t * b + t ** 3;
  for (const [, name, args] of curves) {
    const [x1, y1, x2, y2] = args.split(',').map(Number);
    let previousX = 0, previousY = 0;
    for (let step = 0; step <= 1000; step++) {
      const x = coordinate(step / 1000, x1, x2), y = coordinate(step / 1000, y1, y2);
      assert.ok(x >= previousX && y >= previousY && y <= 1);
      previousX = x; previousY = y;
    }
    if (name === 'autoCurve') { assert.equal(y1, 0); assert.equal(y2, 1); }
    else { assert.ok(y1 / x1 >= 2 && y1 / x1 < 3.5); assert.equal(y2, 1); }
  }
});

test('title handoff suppresses overlapping text while subtitle arrival trails the title', () => {
  for (let p = 0; p <= 1; p += 0.01) {
    assert.ok(Motion.captionWeight(-p) + Motion.captionWeight(1 - p) <= 1 + 1e-10);
    assert.ok(Motion.subtitleWeight(p) <= Motion.captionWeight(p));
    assert.ok(Motion.captionWeight(p) <= Motion.focusWeight(p) + 1e-10);
  }
  assert.ok(Motion.captionWeight(0.5) < 0.025);
  assert.equal(Motion.subtitleWeight(0.5), 0);
  assert.equal(Motion.captionWeight(0), 1); assert.equal(Motion.subtitleWeight(0), 1);
  assert.ok(Motion.offsetY(0.5) > 0); assert.equal(Motion.offsetZ(1), -40);
});

test('poster and indicator taps match autoplay timing while drag settling keeps its shorter duration', () => {
  const { page, clock } = fixture();
  assert.equal(page.switchDuration(), 720);
  page.manualDuration = Motion.DRAG_DURATION_MS; page.touching = true; page.pauseInteraction();
  assert.equal(page.switchDuration(), 420);
  page.touching = false; page.finishSlide(page.displayIndex);
  clock.advance(Motion.INTERACTION_PAUSE_MS); assert.equal(page.switchDuration(), 720);
  page.openSlot(page.displayIndex + 1); assert.equal(page.switchDuration(), Motion.AUTO_DURATION_MS);
  page.manualDuration = Motion.DRAG_DURATION_MS;
  page.selectItem(1); assert.equal(page.switchDuration(), Motion.AUTO_DURATION_MS);
});

test('touch then tap commits autoplay parameters before the native controller starts moving', () => {
  for (const method of ['openSlot', 'selectItem']) {
    const { page, touch, flushFrame, commands, timings } = fixture(6, true);
    touch(TouchType.Down); flushFrame();
    assert.equal(page.switchDuration(), 420);
    touch(TouchType.Up);
    page[method](1);
    assert.equal(commands.length, 0, 'native command must wait for the parameter commit');
    flushFrame();
    assert.equal(commands.length, 1);
    assert.deepEqual(timings, [{ duration: 720, curve: 'auto' }]);
  }
});

test('queued taps cannot start after a new touch, lifecycle change, source replacement or native animation', () => {
  const changes = [
    f => f.touch(TouchType.Down),
    f => f.page.aboutToDisappear(),
    f => { f.page.foreground = false; f.page.activityChanged(); },
    f => { f.page.isActive = false; f.page.activityChanged(); },
    f => f.page.setCarouselVisibility(false),
    f => { f.page.version++; f.page.syncItems(); },
    f => { f.page.currentIndex = 2; f.page.syncSelection(); },
    f => f.page.beginSlide()
  ];
  for (const change of changes) {
    const f = fixture(6, true);
    f.page.selectItem(1);
    assert.equal(f.frames.length, 1);
    change(f); f.flushFrame();
    assert.deepEqual(f.commands, []);
    assert.equal(f.page.pendingSlot, -1);
  }
});

test('queued taps block duplicates and autoplay until the committed transition finishes', () => {
  const { page, frames, commands, clock, flushFrame, timings } = fixture(6, true);
  page.selectItem(1); page.openSlot(2); page.selectItem(3);
  assert.equal(frames.length, 1); assert.deepEqual(commands, []);
  clock.advance(Motion.INTERACTION_PAUSE_MS * 2);
  assert.equal(page.canAutoPlay(), false);
  flushFrame(); assert.deepEqual(commands, [['showNext']]);
  assert.deepEqual(timings, [{ duration: 720, curve: 'auto' }]);
  page.beginSlide(); clock.advance(Motion.AUTO_DURATION_MS);
  page.finishSlide(1); clock.advance(Motion.INTERACTION_PAUSE_MS - 1);
  assert.equal(page.canAutoPlay(), false);
  clock.advance(1); assert.equal(page.canAutoPlay(), true);
});

test('failed frame registration drops a tap safely and subsequent taps still work', () => {
  const f = fixture(6, true), context = f.page.getUIContext;
  f.page.getUIContext = () => ({ postFrameCallback() { throw new Error('UI unavailable'); } });
  f.page.selectItem(1); assert.equal(f.page.pendingSlot, -1); assert.deepEqual(f.commands, []);
  f.page.getUIContext = context;
  f.page.selectItem(1); f.flushFrame();
  assert.deepEqual(f.commands, [['showNext']]);
});

test('refreshed metadata reaches repeated render slots without resetting an ongoing drag', () => {
  const { page } = fixture();
  sample(page, page.displayIndex, -0.25);
  page.items = page.items.map(item => Object.assign(new Item(), item, { title: item.title + ' 更新' }));
  page.syncItems();
  assert.equal(page.slidePosition(page.displayIndex), -0.25);
  assert.ok(page.slots().every(item => item.title.endsWith(' 更新')));
  assert.equal(page.slots().length, Motion.slotCount(page.items.length));
});

test('equivalent provider arrays reuse render slots during color frames and metadata changes preserve position', () => {
  const { page } = fixture();
  sample(page, page.displayIndex, -0.35);
  const original = page.slots();
  for (let i = 0; i < 120; i++) {
    page.items = page.items.map(item => Object.assign(new Item(), item));
    page.syncItems();
    assert.equal(page.slots(), original);
    near(page.slidePosition(page.displayIndex), -0.35);
  }
  page.items[1].subtitle = '新更新'; page.syncItems();
  assert.notEqual(page.slots(), original);
  assert.equal(page.slots()[1].subtitle, '新更新');
  near(page.slidePosition(page.displayIndex), -0.35);
});

test('captions crossfade through a drag and recover when a gesture is cancelled', () => {
  const { page, selected } = fixture(3), center = page.displayIndex;
  assert.equal(page.captionWeight(0), 1); assert.equal(page.captionWeight(1), 0);
  sample(page, center, -0.4); sample(page, center + 1, 0.6);
  assert.ok(page.captionWeight(0) > page.captionWeight(1));
  sample(page, center, -0.7); sample(page, center + 1, 0.3);
  assert.ok(page.captionWeight(1) > page.captionWeight(0));
  assert.deepEqual(selected, []);
  sample(page, center, 0); page.finishSlide(center);
  assert.equal(page.captionWeight(0), 1); assert.equal(page.captionWeight(1), 0);
  sample(page, center, -0.7); sample(page, center + 1, 0.3);
  sample(page, center + 1, 0); page.finishSlide(center + 1); page.changeSlide(center + 1);
  assert.equal(page.captionWeight(0), 0); assert.equal(page.captionWeight(1), 1); assert.deepEqual(selected, [1]);
});

test('indicator selection chooses the nearest loop slot without opening media or bypassing inactive state', () => {
  for (const count of [2, 3, 4, 5, 6]) {
    const slots = Motion.slotCount(count);
    for (let selected = 0; selected < slots; selected++) {
      for (let target = 0; target < count; target++) {
        const nearest = Motion.nearestSlot(target, selected, count);
        assert.equal(nearest % count, target);
        const distance = Math.abs(Motion.relative(nearest, selected, slots));
        for (let other = target; other < slots; other += count) {
          assert.ok(distance <= Math.abs(Motion.relative(other, selected, slots)));
        }
      }
    }
  }
  const { page, moved, opened } = fixture(3);
  page.selectItem(1); assert.deepEqual(moved, [[4, true]]); assert.deepEqual(opened, []);
  page.selectItem(0); assert.equal(moved.length, 1);
  for (const field of ['isActive', 'foreground', 'visible', 'alive']) {
    page[field] = false; page.selectItem(2); assert.equal(moved.length, 1); page[field] = true;
  }
  page.animating = true; page.selectItem(2); assert.equal(moved.length, 1);
  page.animating = false; page.selectItem(-1); page.selectItem(3); assert.equal(moved.length, 1);
});

test('adjacent poster and indicator taps travel one native page at every boundary', () => {
  for (const count of [2, 3, 4, 5, 6, 10]) {
    const slots = Motion.slotCount(count);
    for (const method of ['openSlot', 'selectItem']) {
      for (let start = 0; start < slots; start++) {
        for (const direction of [-1, 1]) {
          const { page, commands, opened } = fixture(count);
          page.displayIndex = start; page.visualCenter = start;
          const target = wrap(start + direction, slots);
          const destination = method === 'selectItem' ? Motion.nearestSlot(target % count, start, count) : target;
          page[method](method === 'selectItem' ? target % count : target);
          assert.equal(commands.length, 1);
          for (const cycle of [-2, 0, 3]) {
            const cursor = cycle * slots + start;
            const landing = nativeLanding(commands[0], cursor, slots);
            assert.equal(landing - cursor, Motion.relative(destination, start, slots),
              `${method}: ${count} items, ${start} -> ${destination}, cycle ${cycle}`);
          }
          assert.deepEqual(opened, []);
        }
      }
    }
  }
});

test('loop seam and middle transitions have identical poses, caption weights and continuous color progress', () => {
  const trajectory = (start, direction, method) => {
    const { page, commands } = fixture(6), slots = 6, frames = [];
    const progress = []; page.onProgress = position => progress.push(position);
    page.displayIndex = start; page.visualCenter = start;
    page[method](wrap(start + direction, slots)); page.beginSlide();
    const delta = nativeLanding(commands.at(-1), start, slots) - start;
    for (let frame = 0; frame <= 40; frame++) {
      const center = start + delta * frame / 40;
      const nearest = Math.round(center), slot = wrap(nearest, slots);
      sample(page, slot, nearest - center);
      if (frame > 0) near(progress.at(-1), wrap(center, 6));
      const values = [];
      for (let offset = -2; offset <= 2; offset++) {
        const index = wrap(start + offset, slots), position = page.slidePosition(index);
        values.push(position, Motion.scale(position), Motion.angle(position), Motion.offsetX(position, 200, Layout.GAP),
          Motion.offsetY(position), Motion.offsetZ(position), Motion.opacity(position), Motion.shadeOpacity(position),
          Motion.depth(position), page.captionWeight(index),
          page.indicatorWeight(index));
      }
      frames.push(values);
    }
    const final = wrap(start + delta, slots), before = page.visualCenter;
    page.changeSlide(final);
    page.finishSlide(final, Layout.margin(page.viewportWidth) + Layout.GAP);
    near(Motion.relative(page.visualCenter, before, slots), 0);
    near(page.captionWeight(final), 1); near(page.indicatorWeight(final), 1);
    return frames;
  };
  for (const method of ['openSlot', 'selectItem']) {
    for (const direction of [-1, 1]) {
      const middle = trajectory(2, direction, method);
      const seam = trajectory(direction === 1 ? 5 : 0, direction, method);
      seam.forEach((values, frame) => values.forEach((value, property) => near(value, middle[frame][property])));
    }
  }
});

test('repeated forward and reverse turns keep native steps and provider identities across multiple cycles', () => {
  for (const count of [2, 3, 4, 5, 6, 10]) {
    for (const direction of [-1, 1]) {
      const { page, commands, selected, opened } = fixture(count), slots = Motion.slotCount(count);
      let cursor = page.displayIndex;
      for (let turn = 0; turn < slots * 3; turn++) {
        const target = wrap(cursor + direction, slots);
        page.openSlot(target);
        const next = nativeLanding(commands.at(-1), cursor, slots);
        assert.equal(next - cursor, direction);
        sample(page, target, 0); page.changeSlide(target);
        page.finishSlide(target, Layout.margin(page.viewportWidth) + Layout.GAP);
        assert.equal(selected.at(-1), wrap(next, count));
        assert.equal(page.activeItem().id, 'source:film:' + wrap(next, count));
        cursor = next;
      }
      assert.deepEqual(opened, []);
      assert.equal(commands.length, slots * 3);
    }
  }
});

test('nonadjacent indicators retain direct selection and an unsettled center recenters without opening', () => {
  const { page, commands, opened } = fixture(6);
  page.selectItem(3); assert.deepEqual(commands, [['changeIndex', 3, true]]);
  sample(page, 0, -0.2); page.openSlot(0);
  assert.deepEqual(commands.at(-1), ['changeIndex', 0, true]); assert.deepEqual(opened, []);
  sample(page, 0, 0); page.openSlot(0); assert.deepEqual(opened, ['source:film:0']);
});

test('manual selection pauses autoplay until the poster settles and the reading delay has elapsed', () => {
  const { page, clock } = fixture();
  page.touching = true; page.pauseInteraction();
  assert.equal(page.canAutoPlay(), false); assert.equal(clock.pending.size, 0);
  page.touching = false; page.pauseInteraction();
  assert.equal(clock.pending.size, 1);
  const interrupted = [...clock.pending.values()][0].callback;
  page.beginSlide(); assert.equal(clock.pending.size, 0);
  interrupted(); assert.equal(page.canAutoPlay(), false);
  page.finishSlide(4); assert.equal(clock.pending.size, 1);
  clock.advance(Motion.INTERACTION_PAUSE_MS - 1); assert.equal(page.canAutoPlay(), false);
  clock.advance(1); assert.equal(page.canAutoPlay(), true);
});

test('repeated interactions extend reading time and old timers cannot resume autoplay early', () => {
  const { page, clock } = fixture();
  page.selectItem(1); const oldTimer = [...clock.pending.values()][0].callback;
  clock.advance(2000); page.selectItem(2);
  oldTimer(); assert.equal(page.canAutoPlay(), false);
  clock.advance(2999); assert.equal(page.canAutoPlay(), false);
  clock.advance(1); assert.equal(page.canAutoPlay(), true);
});

test('leaving, backgrounding, hiding or replacing the source cancels interaction timers', () => {
  for (const change of [p => p.aboutToDisappear(), p => { p.foreground = false; p.activityChanged(); },
    p => { p.isActive = false; p.activityChanged(); }, p => p.setCarouselVisibility(false),
    p => { p.version++; p.syncItems(); }]) {
    const { page, clock } = fixture();
    page.pauseInteraction(); const oldTimer = [...clock.pending.values()][0].callback;
    change(page); assert.equal(clock.pending.size, 0);
    const token = page.interactionTicket;
    page.interactionPaused = true; oldTimer();
    assert.equal(page.interactionPaused, true); assert.equal(page.interactionTicket, token);
  }
});

test('small catalogs get distinct loop slots while selection and indicators keep real item identities', () => {
  assert.equal(Motion.slotCount(0), 0); assert.equal(Motion.slotCount(1), 1);
  for (const count of [2, 3, 4, 5, 6, 10]) {
    const { page, items, selected } = fixture(count);
    const slots = page.slots();
    assert.ok(slots.length >= 6); assert.equal(slots.length % count, 0);
    assert.equal(new Set(slots).size, count);
    for (let i = 0; i < slots.length; i++) {
      page.changeSlide(i);
      assert.equal(page.activeItem(), items[i % count]); assert.equal(selected.at(-1), i % count);
    }
    assert.equal(Motion.relative(0, slots.length - 1, slots.length), 1);
    assert.equal(Motion.relative(slots.length - 1, 0, slots.length), -1);
  }
});

test('scroll samples drive every card and index/finish callbacks do not reset continuous motion', () => {
  const { page } = fixture();
  sample(page, page.displayIndex, -0.4); near(page.slidePosition(page.displayIndex), -0.4);
  near(page.slidePosition(2), -1.4); near(page.slidePosition(4), 0.6); near(page.slidePosition(5), 1.6);
  page.syncItems(); near(page.slidePosition(page.displayIndex), -0.4);
  page.syncSelection(); near(page.slidePosition(page.displayIndex), -0.4);
  page.animating = true; page.finishSlide(4);
  assert.equal(page.animating, false); near(page.visualCenter, 3.4);
  page.changeSlide(4); near(page.visualCenter, 3.4);
  for (const [index, value] of [[-1, 0.2], [99, 0.3], [1.1, 0.4], [1, NaN]]) page.scrollPosition(index, value, 200);
  near(page.visualCenter, 3.4);
});

test('native samples normalize item spacing consistently across widths and loop boundaries', () => {
  for (const length of [144, 187.2, 260]) {
    for (const selected of [0, 3, 5]) {
      for (const progress of [-0.9, -0.3, 0, 0.2, 0.6, 1]) {
        const center = selected + progress;
        for (let index = 0; index < 6; index++) {
          const relative = Motion.relative(index, center, 6);
          const native = relative * (length + Layout.GAP) / length;
          const measured = Motion.centerFromSample(index, native, length, Layout.GAP, 6);
          near(Motion.relative(measured, center, 6), 0);
        }
      }
    }
  }
  for (const args of [[0, 1, 0, 12, 6], [0, 1, 200, -1, 6], [0, Infinity, 200, 12, 6],
    [0.5, 1, 200, 12, 6], [0, 1, 200, 12, 1]]) assert.equal(Number.isNaN(Motion.centerFromSample(...args)), true);
});

test('late side-card callbacks cannot change its pose, and settling has no second spread phase', () => {
  const { page } = fixture(3), center = page.displayIndex;
  for (const progress of [0.1, 0.25, 0.45, 0.65, 0.85, 1]) {
    sample(page, center, -progress);
    sample(page, center + 1, 1 - progress);
    near(page.visualCenter, center + progress);
    const before = Array.from({ length: 6 }, (_, index) => page.slidePosition(index));
    // A previously offscreen right-hand page starts reporting only after the swipe has begun.
    sample(page, center + 2, 2 - progress);
    sample(page, center + 2, 2); // A stale far-page sample must not rewind the current frame.
    before.forEach((position, index) => near(page.slidePosition(index), position));
  }
  const pose = index => {
    const p = page.slidePosition(index);
    return [Motion.offsetX(p, 200, Layout.GAP), Motion.offsetY(p), Motion.offsetZ(p), Motion.angle(p), Motion.scale(p)];
  };
  const sidePoses = [pose(center), pose(center + 2)];
  page.changeSlide(center + 1);
  page.finishSlide(center + 1, Layout.margin(page.viewportWidth) + Layout.GAP);
  [pose(center), pose(center + 2)].forEach((values, index) => values.forEach((v, i) => near(v, sidePoses[index][i])));
  page.currentIndex = 1; page.syncSelection(); near(page.visualCenter, center + 1);
});

test('animation interruption preserves its actual offset, while a normal finish uses the native final offset', () => {
  const { page } = fixture(), center = page.displayIndex, length = 200;
  const origin = Layout.margin(page.viewportWidth) + Layout.GAP;
  sample(page, center, -0.4, length);
  page.finishSlide(center, origin - 0.4 * (length + Layout.GAP));
  near(page.visualCenter, center + 0.4);
  page.changeSlide(center); near(page.visualCenter, center + 0.4);
  sample(page, center, -0.98, length);
  page.finishSlide(center + 1, origin);
  near(page.slidePosition(center + 1), 0); near(page.slidePosition(center), -1);
});

test('palette progress is emitted during movement and maps repeated render slots to real catalog positions', () => {
  const { page } = fixture(2); const progress = []; page.onProgress = position => progress.push(position);
  sample(page, 2, -0.25); near(progress.at(-1), 0.25);
  sample(page, 3, -0.5); near(progress.at(-1), 1.5);
  const count = progress.length; page.changeSlide(3); assert.equal(progress.length, count);
  sample(page, 4, 0); near(progress.at(-1), 0);
});

test('home and provider backgrounds do not add a second timed animation after per-frame palette updates', () => {
  for (const path of ['pages/home/HomePage.ets', 'pages/catvod/CatVodContent.ets', 'pages/emby/EmbyHomeContent.ets']) {
    assert.equal(read(path).includes('.animation({ duration: 500, curve: Curve.EaseInOut })'), false, path);
  }
});

test('side taps center a poster; only the settled center opens the original provider ID', () => {
  const { page, items, opened, moved } = fixture(2);
  const center = page.displayIndex;
  page.openSlot(center + 1); assert.deepEqual(moved, [[center + 1, true]]); assert.deepEqual(opened, []);
  sample(page, center + 1, 0); page.changeSlide(center + 1);
  page.openSlot(center + 1); assert.deepEqual(opened, [items[1].id]);
  page.animating = true; page.openSlot(center + 1); assert.equal(opened.length, 1);
  page.animating = false; page.openSlot(-1); page.openSlot(99); assert.equal(moved.length, 1); assert.equal(opened.length, 1);
});

test('source resets and external selections drop stale poses, including empty and one-item catalogs', () => {
  const { page } = fixture();
  sample(page, 3, -0.5); page.version++; page.syncItems();
  assert.equal(page.visualCenter, page.displayIndex); assert.equal(page.slidePosition(page.displayIndex), 0);
  page.currentIndex = 2; page.syncSelection(); assert.equal(page.activeItem().id, 'source:film:2');
  page.items = [page.items[1]]; page.syncItems();
  assert.equal(page.displayIndex, 0); assert.equal(page.slots().length, 1); assert.equal(page.canAutoPlay(), false);
  page.items = []; page.syncItems(); assert.deepEqual(page.slots(), []); assert.equal(page.activeItem().id, '');
});

test('Cat wrapper resolves the original item on click and ignores an obsolete card ID', () => {
  const source = read('pages/catvod/CatVodHeroBanner.ets');
  const method = source.slice(source.indexOf('  private openItem('), source.indexOf('  build()'));
  const Page = new Function(compile(`class Page { ${method} }`) + ';return Page;')();
  const original = { id: 'catnode:site-a:opaque-id' }; const opened = [];
  const page = Object.assign(new Page(), { items: [original], onOpen: video => opened.push(video) });
  page.openItem(original.id); page.openItem('obsolete'); assert.deepEqual(opened, [original]);
});

test('refreshing the Cat carousel resets position and invalidates an earlier color request', () => {
  const source = read('pages/catvod/CatVodHeroBanner.ets');
  const method = source.slice(source.indexOf('  private resetPosition('), source.indexOf('  private onActivityChanged('));
  const Page = new Function(compile(`class Page { ${method} }`) + ';return Page;')();
  const page = Object.assign(new Page(), { currentIndex: 4, failedArtwork: new Set(['bad']), paletteRequest: 0,
    alive: true, updatePalette() { this.paletteRequest++; }, warmColors: async () => {} });
  page.resetPosition(); assert.equal(page.currentIndex, 0); assert.equal(page.failedArtwork.size, 0);
  assert.equal(page.paletteRequest, 1); page.aboutToDisappear(); assert.equal(page.alive, false);
  assert.equal(page.paletteRequest, 2);
});
