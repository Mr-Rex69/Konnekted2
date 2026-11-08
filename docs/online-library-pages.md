# Artist and album pages

Artist and album detail pages now use edge-to-edge artwork under the status bar, a gradient into the page background, large titles and prominent playback controls. Artist pages use a saved portrait or an online artist portrait; album covers are not presented as artist photos. Existing local artwork takes precedence. When no portrait is available, the header uses a theme-coloured fallback.

Library entry points start locally unless that page's online mode was previously enabled. Each artist/album has its own remembered online switch. Discovery recommendations and shortcuts from online songs can open a page even when there are no matching library files. No catalogue lookup starts merely by constructing a library page.

Online mode loads artist popular songs and releases, or an album's ordered full track list, through the existing Apple Music/iTunes metadata service. Configured playback-source searches provide a bounded fallback; an unverified album search is labelled as search results rather than a complete album. Portrait fallback uses the existing discovery artwork resolver. Successful page results are cached for 15 minutes, with explicit refresh, and empty/failed pages can be retried.

Catalogue metadata is not playable audio. Play, shuffle, queue and download actions use the existing discovery matching, configured playback sources and queue pre-resolver. A selected playback source is preserved and is not silently substituted. Library copies are preferred and marked; local songs missing from a catalogue result remain visible. Only an explicit download action copies missing songs into the library via the existing downloader. Partial progress is retained if a batch fails. Originals are not moved or deleted.

Artist pages include a recent/featured release card, popular songs, releases and available biography. Artist stars are local follow preferences. Album pages retain local song likes, playlist/queue actions, album identification, related local releases and artist navigation. The persistent shell dock remains available.

Metadata coverage and availability depend on the catalogue. This change does not add new provider-specific artist/album endpoints to add-ons; existing add-ons are used for recording search, playback and downloads. New presentation strings use the existing localization entry points; additional phrase translations still need language review.

Validation: source review and Dart formatting only. CI, tests, analysis, builds and device checks were skipped at the user's request. The layout, live catalogue responses, downloads and native sharing have not been verified on a physical device.
