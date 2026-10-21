// Exercise the page's actual async paging methods without the ArkUI rendering runtime.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/pages/emby/EmbyDetailPage.ets', import.meta.url), 'utf8');
const methods = ['loadEpisodes', 'loadMoreEpisodes'].map(name => {
  const start = source.indexOf(`  private async ${name}(`);
  assert.ok(start >= 0, `Missing method: ${name}`);
  const end = source.indexOf('\n  }', start);
  assert.ok(end > start, `Missing method end: ${name}`);
  return source.slice(start, end + 4);
}).join('\n');
const Page = new Function(`${stripTypeScriptTypes(`class Page { ${methods} }`, { mode: 'transform' })}; return Page;`)();

function pageResult(start, count = 20, total = 60) {
  return {
    items: Array.from({ length: count }, (_, i) => ({ id: String(start + i), type: 'Episode' })),
    totalRecordCount: total
  };
}

function fixture(fetchPage) {
  const calls = [];
  const page = new Page();
  Object.assign(page, {
    provider: { getSeasonEpisodesPageRaw: async (series, season, start, limit) => {
      calls.push({ season, start, limit });
      return fetchPage(season, start);
    } },
    item: { id: 'series', type: 'Series' }, selectedSeasonId: 'season-a',
    seasonLoadGeneration: 0, episodeNextStart: 0, episodeRangeStart: 0,
    episodeItems: [], currentSeasonEpisodeCount: 60, EPISODE_PAGE_SIZE: 20,
    episodesLoading: false, loadingMore: false, episodesError: '',
    playbackTarget: {}, sortByIndex: () => {}
  });
  return { page, calls };
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

test('repeated end events share one append request and preserve existing episodes', async () => {
  const pending = deferred();
  const { page, calls } = fixture((_, start) => start === 0 ? pageResult(0) : pending.promise);
  await page.loadEpisodes(0);
  const append = page.loadMoreEpisodes();
  await page.loadMoreEpisodes();
  assert.equal(calls.length, 2);
  assert.equal(page.episodeItems.length, 20);
  pending.resolve(pageResult(20));
  await append;
  assert.equal(page.episodeItems.length, 40);
  assert.equal(page.episodeItems[0].id, '0');
  assert.equal(page.loadingMore, false);
});

test('a selected range continues at the next server offset and stops at the total', async () => {
  const { page, calls } = fixture((_, start) => pageResult(start, start === 40 ? 5 : 20, 45));
  await page.loadEpisodes(20);
  await page.loadMoreEpisodes();
  await page.loadMoreEpisodes();
  assert.deepEqual(calls.map(call => call.start), [20, 40]);
  assert.equal(page.episodeRangeStart, 20);
  assert.equal(page.episodeItems.length, 25);
});

test('switching seasons discards an in-flight append from the previous season', async () => {
  const pending = deferred();
  const { page } = fixture((season, start) => {
    if (season === 'season-a' && start === 20) return pending.promise;
    return pageResult(season === 'season-b' ? 100 : 0);
  });
  await page.loadEpisodes(0);
  const oldAppend = page.loadMoreEpisodes();
  page.selectedSeasonId = 'season-b';
  await page.loadEpisodes(0);
  pending.resolve(pageResult(20));
  await oldAppend;
  assert.equal(page.episodeItems.length, 20);
  assert.equal(page.episodeItems[0].id, '100');
  assert.equal(page.episodeNextStart, 20);
});

test('a failed append retains its cursor and can retry the same page', async () => {
  let fail = true;
  const { page, calls } = fixture((_, start) => {
    if (start === 20 && fail) throw new Error('offline');
    return pageResult(start);
  });
  await page.loadEpisodes(0);
  await page.loadMoreEpisodes();
  assert.ok(page.episodesError.length > 0);
  assert.equal(page.episodeItems.length, 20);
  assert.equal(page.episodeNextStart, 20);
  fail = false;
  await page.loadMoreEpisodes();
  assert.deepEqual(calls.map(call => call.start), [0, 20, 20]);
  assert.equal(page.episodesError, '');
  assert.equal(page.episodeItems.length, 40);
});

test('duplicate results do not cause the same server page to be requested repeatedly', async () => {
  const { page, calls } = fixture((_, start) => pageResult(start === 20 ? 0 : start));
  await page.loadEpisodes(0);
  await page.loadMoreEpisodes();
  assert.equal(page.episodeItems.length, 20);
  await page.loadMoreEpisodes();
  assert.deepEqual(calls.map(call => call.start), [0, 20, 40]);
});

test('an empty tail stops further requests even when the reported total is stale', async () => {
  const { page, calls } = fixture((_, start) => pageResult(start, start === 0 ? 20 : 0));
  await page.loadEpisodes(0);
  await page.loadMoreEpisodes();
  await page.loadMoreEpisodes();
  assert.deepEqual(calls.map(call => call.start), [0, 20]);
});
