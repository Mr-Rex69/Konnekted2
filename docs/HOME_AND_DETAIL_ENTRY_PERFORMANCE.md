# Home navigation and detail-page entry performance

## Device recording (1 November 2026, 08:03)

The supplied 17.88s recording starts with Lokal's Home, Library and profile
navigation and later shows the PixelPlayer comparison. Lokal's prior bottom-tab
animation used only a 20-pixel translation, independent of tab order, while
PixelPlayer chooses left/right travel from the relative tab positions. This
made Home switches look like one page abruptly being overlaid on another.

The user also reports pronounced entry-only frame drops on artist and album
pages, with smooth exits. A source inspection found synchronous library-wide
filtering, `lokalAlbums(library)` regrouping and sorting, plus full-resolution
art decoding in the first build of `LokalMusicDetailPage`.

## Fixes

- Main Home/Search/Library/You tab switches animate from the actual navigation
  direction (forward/backward), with a 330ms emphasized curve, 48%-width
  incoming translation and 22%-width outgoing parallax. Opacity is fixed at
  100%; the previous tab is retained only during the transition. RTL reverses
  the direction.
- Album/artist detail pages render their known local tracks and artwork first.
  Global library reconciliation and related-release grouping are deferred
  until the entering `ModalRoute` animation completes. The group list is
  cached per library identity and limited to the relevant artist rather
  than regrouping the entire library on each unrelated state update.
- `_entries` only builds the global track-match index when matching online
  tracks, and uses a set for owned-song duplicate elimination.
- Artwork initially decodes at a bounded 896px size and returns to the normal
  full-resolution path after entry. No permanent loss in cover quality.
- Layout and routing continue to respect animations-off, iOS/Android accessibility
  and Ultra Performance Mode.

## Required physical-device acceptance tests

1. Repeatedly switch Library → Home → Search → Home and You → Home,
   including rapidly switching before an animation ends. Both directions
   must remain consistent, without ghosted Home content or unpainted frames.
2. Open albums and artists from Library, Search, Home, Now Playing and
   online-only results. Measure frame pacing on entry **and on Back**.
3. Test both cold artwork caches and warmed artwork, with local files,
   high-resolution images and NAS/WebDAV/SMB covers.
4. Compare 500, 5,000 and 20,000-song libraries. Track build and raster
   timing separately in Flutter profile mode; the target is no recurring
   >16.7ms UI/raster frames on a 60Hz device during entry (subject to device).
5. Confirm Top Songs, other releases, Follow/Like/Play/Shuffle, online catalogue,
   and library reconciliation appear normally after entry.
6. Confirm all animated routes still honor Back, predictive-back where supported,
   reduced motion, and the user's animation preferences.

No APK profiling or on-device FPS measurement was available in this execution
environment. Test source and visual logic separately before merge.
