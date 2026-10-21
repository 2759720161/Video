let artworkTransitionSequence: number = 0

/** A rendered card owns its identity until it is destroyed; media IDs are not unique UI instances. */
export function createArtworkTransitionId(): string {
  artworkTransitionSequence++
  return 'artwork_card_' + artworkTransitionSequence
}
