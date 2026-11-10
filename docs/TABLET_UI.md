# Tablet workspace

Android tablets, foldables and iPads use a shared Flutter workspace inspired by Lokal desktop. It keeps the existing playback, library and provider bindings.

## Navigation and space

- A window at least 600 logical pixels wide and 480 pixels high uses tablet chrome. Smaller windows retain the phone dock.
- Navigation and the player sidebar retract independently. The workspace toolbar always offers both reopen controls; playback remains available in the footer when both panels are closed.
- Wide windows dock the player on the right; windows below 1000 pixels open it over a dismissible scrim. Back dismisses that overlay before navigating away. The initial player panel opens automatically only when playback is available in a wide window.
- The navigation sidebar is one scrolling list of peer destinations, including You and Settings. It has no Library section divider or pinned bottom actions. Search lives in the workspace header immediately left of the right-sidebar toggle, and retains its keyboard/refocus behavior. The sidebar uses labels when space permits and an icon rail otherwise. The player panel can be resized from 300 to 420 logical pixels, including through accessibility increase/decrease actions.
- The central navigator and player-panel state remain mounted across collapse, rotation, overlay/docked changes and split view. Panel choices last for the current session. The keyboard does not change navigation mode.
- Content receives its actual pane dimensions and system insets, including when playback is absent. Home artwork, grids, mixes and shelves adapt independently; tablet text uses bounded sizing rather than viewport zoom.

## Floating glass playback footer

The tablet player floats over the content in a centered capsule, using exactly the phone dock's shared refraction lens, blur, translucent tint, rim and performance-mode fallback. It is always confined to the space between visible sidebars, including a right overlay. Opening, closing or resizing a sidebar adjusts the capsule bounds immediately. Its expanded size is at most 1200 × 80 logical pixels. Meaningful downward browsing scroll folds it to at most 760 × 56; upward scroll or its expand icon restores it. The 250ms transition is reversible, honors reduced motion and fades secondary controls within the same glass surface.

Artwork, identity, play/pause, next, sidebar access and playback options stay within reach when folded. Expanded wide layouts add previous, shuffle/repeat, Like, lyrics, queue and volume shortcuts. Narrow layouts and the folded pill expose secondary actions through the playback menu; the seek timeline with timestamps returns on expansion. Panes narrower than 600 logical pixels select the compact player automatically; very narrow space beside an overlay reduces it to essential icon controls instead of crossing either sidebar. Volume/mute and output selection live in a compact on-demand sheet. Fullscreen, local sleep timer, speed, pitch and EQ remain in playback options.

The central page retains its full viewport behind the glass. Its bottom clearance and system safe areas keep final rows reachable without feeding that clearance back into the dock's own SafeArea. Both sidebars keep their own full height and system insets. Collapsing the pill changes clearance rather than resizing the navigator.

Local playback uses `PlayerVolumeControl`, preserving system, casting and exclusive-output volume behavior. Remote playback dispatches through the existing desktop controller. Live radio uses its station transport and volume, displays live state and never exposes a fabricated seek position. Local sleep timer, speed, pitch and EQ remain accessible through the playback menu.

## Player sidebar

| Desktop behavior | Tablet implementation |
| --- | --- |
| Details, Lyrics, Queue | Persistent top-level views, with real editable music queues and station selection for radio |
| Large artwork and moving covers | Existing shared `MotionArtView` with still-art fallback and native output suppression intact |
| Below-cover Info/Lyrics switch | Independent Details/Lyrics card selector; a separate toggle combines the two cards |
| Like and artwork double tap | Existing song or station favorites; guarded writes and a single like animation |
| Fullscreen, fullscreen lyrics, music video | Full-player and lyric routes; official video action appears when an opted-in lookup finds a match |
| Moving-art toggle | Existing per-song moving-cover preference, shared with the rest of the player |
| Linked identity/context | Album and individual artist links; album, artist, playlist and folder playback context links |
| Metadata | Album/album artist, year, editable local genre, track number, format, resolution, source, stored file bitrate and local play count when available |
| Song actions | Existing song menu for playlist, radio, sharing, downloads and editing; folder navigation and artist radio shortcuts; radio-specific station actions |
| Lyrics | Existing source, search, translation, save, word/line synchronization and seek controls; remote lyrics follow the desktop clock |
| Sidebar visualizer | Deliberately excluded |

The sidebar content stack explicitly fills its pane so Lyrics and Queue retain their full width after Details is hidden. Queue rows play tracks in place. Reduced-motion lyric rows lay out directly when the renderer is moved or resized, without zero-duration size animations. The compact and full-height lyric views share one renderer instance so source selection and browsing survive tab changes. The sidebar uses one compact icon toolbar for save, translation/romanization, source selection, file import and online search, with tooltips and accessible labels. Timing/source details and linked-file reset live in the source chooser instead of badge rows or large action pills. At 300 logical pixels wide and 200% text, the toolbar remains one row and the lyric stage retains more than 350 pixels of a 420-pixel card. Metadata sheets also scroll on short screens.

Radio lyrics wait for real artist/title metadata and use a recording-specific identity, so changing songs on one station does not retain the previous song's lyrics.

Metadata is shown only when known. File bitrate comes from the scanner's persisted record for that exact recording; radio bitrate comes from the station. Neither is inferred from file size or PCM resolution. Desktop snapshots do not currently expose every library metadata field, so unavailable values are omitted.

## Other tablet screens

The Home mode selector is capped at 420 logical pixels instead of stretching across the pane; utility actions stay at the trailing edge. Local home uses a larger carousel with bounded artwork up to 380 pixels and previous/next browsing controls. Mixes, collection tiles, album grids and discovery shelves adapt their density to the content pane. Landscape modern, classic, radio and desktop-controlled players place the stage beside controls. Full-cover mode has a tablet-specific composition: a large square cover on the left, track identity and controls on the right, and the existing mobile artwork blur behind it. Local, radio and desktop-controlled players retain square artwork instead of the phone poster overlay. Narrow split views retain a vertical fallback. Phones retain their existing full-cover behavior. Wide album headers, Settings and You use wider compositions. Standard modal sheets are bounded to 640 pixels and all chrome uses Lokal theme tokens.

## Rotation

Android's manifest no longer forces portrait. Flutter preserves portrait on phone displays and allows tablet rotation, including restoring the correct policy after fullscreen video. The existing iPad orientation declarations already include landscape. Split-view window dimensions choose layout; display dimensions choose orientation policy.

## Validation and device checks

Run:

```sh
flutter analyze --no-pub
flutter test --no-pub
```

The tablet tests exercise dark/light themes, 200% text, keyboard and safe-area insets, pane geometry, independent collapse/reopen, resizing/overlay state retention, navigation and scroll retention, carousel selection, Settings search, real compact lyric rendering, below-cover card selection, full-height lyric/queue switching, likes, moving-art preferences and footer transport/seek routing. Radio and desktop-controlled playback have landscape regressions as well.

The tablet refinement passed the full Flutter suite: **3,132 tests passed, 4 skipped**. After rebasing onto the latest main, all **47** editorial/autoplay/sidebar/workspace checks passed. The pane tests verify no footer overlap across all sidebar combinations, overlay/docked modes, resizing and safe areas, full-width and tappable Lyrics/Queue content, one peer navigation list and real header Search focus/refocus. Coverage also includes the shared phone/tablet glass optics, expanded/collapsed layout matrix, scroll folding and reversal, real compact synchronized lyrics, source-picker actions, square-cover geometry and settings descriptions. Flutter analysis reported no errors; existing repository warnings and Flutter prerelease deprecation notices remain.

Widget rendering is not physical-device certification. The debug APK attempt stopped with **No Android SDK found** in this Linux workspace. APK installation, iPad builds, real-device rotation/multitasking, hardware keyboard/pointer behavior and native USB/casting playback remain device checks. This UI work does not establish new audio hardware capabilities.
