// Route-level regressions: duplicate media appearances and nested detail pages must not cross-match.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url.endsWith('.ets')) return { format: 'module', shortCircuit: true,
      source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }) };
    return nextLoad(url, context);
  }
});
const { createArtworkTransitionId } = await import('../entry/src/main/ets/utils/ArtworkTransition.ets');
const { buildEmbyDetailRouteParams } = await import('../entry/src/main/ets/providers/emby/EmbyDetailRoute.ets');
const { EmbyItem } = await import('../entry/src/main/ets/providers/emby/EmbyModels.ets');

function media(id, type = 'Movie') {
  const item = new EmbyItem();
  item.id = id;
  item.type = type;
  return item;
}
const matches = (left, right) => left.filter(id => id && right.includes(id));

test('shared artwork clips its own rounded corners in both loading and loaded details', () => {
  for (const file of ['components/media/MediaPosterCard.ets', 'components/media/ImmersiveDetailStage.ets',
    'pages/emby/EmbyDetailPage.ets']) {
    const source = readFileSync(new URL('../entry/src/main/ets/' + file, import.meta.url), 'utf8');
    assert.match(source, /\.borderRadius\(AppRadius\.MEDIA_POSTER\)\s*\.clip\(true\)\s*\.sharedTransition\(/, file);
  }
});

test('duplicate home appearances and detail recommendations match only the clicked card', () => {
  const item = media('same-film');
  const home = [createArtworkTransitionId(), createArtworkTransitionId(), createArtworkTransitionId()];
  const params = buildEmbyDetailRouteParams('server', item, home[1]);
  const detail = [params.artworkTransitionId, createArtworkTransitionId(), createArtworkTransitionId()];
  assert.deepEqual(matches(home, detail), [home[1]]);
  assert.deepEqual(matches(detail, home), [home[1]]);
});

test('nested detail navigation retains independent forward and return pairs', () => {
  const homeCard = createArtworkTransitionId();
  const first = buildEmbyDetailRouteParams('server', media('A'), homeCard);
  const recommendation = createArtworkTransitionId();
  const collectionDuplicate = createArtworkTransitionId();
  const second = buildEmbyDetailRouteParams('server', media('B'), recommendation);
  const firstPage = [first.artworkTransitionId, recommendation, collectionDuplicate];
  const secondPage = [second.artworkTransitionId, createArtworkTransitionId()];
  assert.deepEqual(matches(firstPage, secondPage), [recommendation]);
  assert.deepEqual(matches(secondPage, firstPage), [recommendation]);
  assert.deepEqual(matches(firstPage, [homeCard]), [homeCard]);
  assert.deepEqual(matches(secondPage, [homeCard]), []);
});

test('episode and season redirect preserve the clicked artwork and episode selection', () => {
  const selectedCard = createArtworkTransitionId();
  const episode = media('episode-7', 'Episode');
  episode.seriesId = 'series';
  episode.parentId = 'season-2';
  episode.indexNumber = 7;
  const params = buildEmbyDetailRouteParams('server', episode, selectedCard);
  assert.deepEqual(params, { sourceId: 'server', itemId: 'series', artworkTransitionId: selectedCard,
    initialSeasonId: 'season-2', initialEpisodeId: 'episode-7', initialEpisodeIndex: 7 });
  episode.seasonId = 'explicit-season';
  assert.equal(buildEmbyDetailRouteParams('server', episode, selectedCard).initialSeasonId, 'explicit-season');
  const season = media('season-2', 'Season');
  season.seriesId = 'series';
  assert.deepEqual(buildEmbyDetailRouteParams('server', season, selectedCard), {
    sourceId: 'server', itemId: 'series', artworkTransitionId: selectedCard, initialSeasonId: 'season-2'
  });
});

test('non-poster entry never inherits a previous artwork transition', () => {
  const item = media('film');
  buildEmbyDetailRouteParams('server', item, createArtworkTransitionId());
  assert.deepEqual(buildEmbyDetailRouteParams('server', item), { sourceId: 'server', itemId: 'film' });
  assert.deepEqual(buildEmbyDetailRouteParams('server', item, ''), { sourceId: 'server', itemId: 'film' });
});

test('recreated cards do not capture a stale return destination', () => {
  const removedCard = createArtworkTransitionId();
  const params = buildEmbyDetailRouteParams('server', media('film'), removedCard);
  const replacement = createArtworkTransitionId();
  assert.deepEqual(matches([params.artworkTransitionId], [replacement]), []);
});
