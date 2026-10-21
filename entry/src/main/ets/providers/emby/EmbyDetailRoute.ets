import { EmbyItem } from './EmbyModels'

/** Carry the clicked artwork needed to keep the detail page's shared transition alive while loading. */
export function buildEmbyDetailRouteParams(sourceId: string, item: EmbyItem,
  artworkTransitionId: string = '', transitionArtworkUrl: string = ''): Record<string, Object> {
  const params: Record<string, Object> = { 'sourceId': sourceId, 'itemId': item.id }
  if (artworkTransitionId.length > 0) params['artworkTransitionId'] = artworkTransitionId
  if (transitionArtworkUrl.length > 0) params['transitionArtworkUrl'] = transitionArtworkUrl
  if (item.type === 'Season' && item.seriesId.length > 0) {
    params['itemId'] = item.seriesId
    params['initialSeasonId'] = item.id
  } else if (item.type === 'Episode' && item.seriesId.length > 0) {
    params['itemId'] = item.seriesId
    params['initialSeasonId'] = item.seasonId.length > 0 ? item.seasonId : item.parentId
    params['initialEpisodeId'] = item.id
    params['initialEpisodeIndex'] = item.indexNumber
  }
  return params
}
