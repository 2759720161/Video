// Node 24+: exercise real Emby request construction/parsing with an in-memory HTTP transport.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === '@kit.NetworkKit') return { url: 'test:network', shortCircuit: true };
    if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      const url = new URL(specifier, context.parentURL);
      if (!url.pathname.endsWith('.ets')) url.pathname += '.ets';
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url.endsWith('/store/PreferencesStore.ets')) return { format: 'module', shortCircuit: true,
      source: "export class PreferencesStore { static getInstance() { throw new Error('Unexpected preference access'); } }" };
    if (url === 'test:network') return { format: 'module', shortCircuit: true, source: `
      export const replies = [], requests = [];
      export let destroyed = 0;
      export const http = {
        RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 },
        createHttp() { return {
          async request(url, options) {
            requests.push({ url: new URL(url), options });
            if (!replies.length) throw new Error('Unexpected HTTP request');
            return replies.shift();
          }, destroy() { destroyed++; }
        }; }
      };
    ` };
    if (url.endsWith('.ets')) return { format: 'module', shortCircuit: true,
      source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform' }) };
    return nextLoad(url, context);
  }
});

const transport = await import('@kit.NetworkKit');
const { EmbyClient } = await import('../entry/src/main/ets/providers/emby/EmbyClient.ets');
const { EmbyServerConfig } = await import('../entry/src/main/ets/providers/emby/EmbyModels.ets');
const config = new EmbyServerConfig();
Object.assign(config, { baseUrl: 'https://emby.invalid', userId: 'user A', accessToken: 'test-token' });
const client = new EmbyClient(config);
function reply(value, responseCode = 200) {
  transport.replies.push({ responseCode, result: JSON.stringify(value) });
}

test('search excludes only episodes and retains seasons, series and movies', async () => {
  reply({ Items: [
    { Id: 'episode', Name: 'Episode', Type: 'Episode' },
    { Id: 'season', Name: 'Season', Type: 'Season' },
    { Id: 'series', Name: 'Series', Type: 'Series' },
    { Id: 'movie', Name: 'Movie', Type: 'Movie' }
  ] });
  const items = await client.searchItems('test');
  assert.deepEqual(items.map(item => item.type), ['Season', 'Series', 'Movie']);
});

test('library page scopes server/user/parent and preserves paging and sorting', async () => {
  reply({ Items: [{ Id: 'movie', Name: 'Movie', Type: 'Movie' }], TotalRecordCount: 7303 });
  const page = await client.getItemsPage('library A', 40, 40, true, 'Movie', 'DateCreated', 'Descending');
  const request = transport.requests.at(-1);
  assert.equal(request.url.pathname, '/Users/user%20A/Items');
  for (const [key, value] of Object.entries({ ParentId: 'library A', StartIndex: '40', Limit: '40',
    Recursive: 'true', IncludeItemTypes: 'Movie', SortBy: 'DateCreated', SortOrder: 'Descending' })) {
    assert.equal(request.url.searchParams.get(key), value);
  }
  assert.equal(request.options.header['X-Emby-Token'], 'test-token');
  assert.equal(page.startIndex, 40);
  assert.equal(page.totalRecordCount, 7303);
  assert.equal(page.items[0].id, 'movie');
});

test('latest library endpoint accepts its array response and retains episode navigation context', async () => {
  reply([{ Id: 'episode', Name: 'Episode', Type: 'Episode', SeriesId: 'series', SeasonId: 'season',
    UserData: { PlaybackPositionTicks: 10000000 } }]);
  const items = await client.getLatestLibraryItems('tv library', 10);
  const url = transport.requests.at(-1).url;
  assert.equal(url.pathname, '/Users/user%20A/Items/Latest');
  assert.equal(url.searchParams.get('ParentId'), 'tv library');
  assert.equal(url.searchParams.get('GroupItems'), 'true');
  assert.equal(url.searchParams.get('Limit'), '10');
  assert.equal(items[0].seriesId, 'series');
  assert.equal(items[0].seasonId, 'season');
  assert.equal(items[0].resumePositionMs(), 1000);
});

test('all resume and next-up lists request pages beyond the home preview', async () => {
  reply({ Items: [{ Id: 'resume', Name: 'Resume', Type: 'Movie' }], TotalRecordCount: 90 });
  const resume = await client.getResumeItemsPage(40, 40);
  assert.equal(resume.totalRecordCount, 90);
  assert.equal(transport.requests.at(-1).url.searchParams.get('StartIndex'), '40');
  assert.equal(transport.requests.at(-1).url.searchParams.get('Limit'), '40');
  reply({ Items: [{ Id: 'next', Name: 'Next', Type: 'Episode' }], TotalRecordCount: 83 });
  const next = await client.getNextUpItemsPage(80, 40);
  const url = transport.requests.at(-1).url;
  assert.equal(url.pathname, '/Shows/NextUp');
  assert.equal(url.searchParams.get('UserId'), 'user A');
  assert.equal(url.searchParams.get('StartIndex'), '80');
  assert.equal(next.startIndex, 80);
  assert.equal(next.totalRecordCount, 83);
});

test('invalid responses and expired authentication surface errors and release HTTP handles', async () => {
  const before = transport.destroyed;
  reply([]);
  await assert.rejects(client.getItemsPage('library'), /响应格式无效/);
  reply({}, 401);
  await assert.rejects(client.getLatestLibraryItems('library'), /登录状态无效/);
  assert.equal(transport.destroyed - before, 2);
  assert.equal(transport.replies.length, 0);
});
