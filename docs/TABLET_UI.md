# Tablet workspace

Android tablets, foldables and iPads use a shared Flutter workspace inspired by Lokal desktop. It keeps the existing playback, library and provider bindings.

## Navigation and space

- A window at least 600 logical pixels wide and 480 pixels high uses tablet chrome. Smaller windows retain the phone dock.
- Navigation and the player sidebar retract independently. The workspace toolbar always offers both reopen controls; playback remains available in the footer when both panels are closed.
- Wide windows dock the player on the right; windows below 1000 pixels open it over a dismissible scrim. Back dismisses that overlay before navigating away. The initial player panel opens automatically only when playback is available in a wide window.
- The navigation sidebar uses labels when space permits and an icon rail otherwise. The player panel can be resized from 300 to 420 logical pixels, including through accessibility increase/decrease actions.
- The central navigator and player-panel state remain mounted across collapse, rotation, overlay/docked changes and split view. Panel choices last for the current session. The keyboard does not change navigation mode.
- Content receives its actual pane dimensions and system insets, including when playback is absent. Home artwork, grids, mixes and shelves adapt independently; tablet text uses bounded sizing rather than viewport zoom.

## Desktop-style playback footer

The tablet footer is a flat, full-width desktop composition, not a floating pill. It contains artwork and identity, Like, previous/play/next, shuffle/repeat, a seekable timeline with timestamps, route-aware volume/mute, output selection, Lyrics/Queue/Now Playing shortcuts, fullscreen, and additional playback actions. It rearranges into rows on narrower tablets.

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

The compact and full-height lyric views share one renderer instance so source selection and browsing survive tab changes. Source/action controls wrap and scroll within a bounded header at large text sizes, leaving room for the lyrics themselves. Metadata sheets also scroll on short screens.

Radio lyrics wait for real artist/title metadata and use a recording-specific identity, so changing songs on one station does not retain the previous song's lyrics.

Metadata is shown only when known. File bitrate comes from the scanner's persisted record for that exact recording; radio bitrate comes from the station. Neither is inferred from file size or PCM resolution. Desktop snapshots do not currently expose every library metadata field, so unavailable values are omitted.

## Other tablet screens

Local home uses a larger carousel with bounded artwork up to 380 pixels and previous/next browsing controls. Mixes, collection tiles, album grids and discovery shelves adapt their density to the content pane. Landscape modern, classic, radio and desktop-controlled players place the stage beside controls. Wide album headers, Settings and You use wider compositions. Standard modal sheets are bounded to 640 pixels and all chrome uses Lokal theme tokens.

## Rotation

Android's manifest no longer forces portrait. Flutter preserves portrait on phone displays and allows tablet rotation, including restoring the correct policy after fullscreen video. The existing iPad orientation declarations already include landscape. Split-view window dimensions choose layout; display dimensions choose orientation policy.

## Validation and device checks

Run:

```sh
flutter analyze --no-pub
flutter test --no-pub
```

The tablet tests exercise dark/light themes, 200% text, keyboard and safe-area insets, pane geometry, independent collapse/reopen, resizing/overlay state retention, navigation and scroll retention, carousel selection, Settings search, real compact lyric rendering, below-cover card selection, full-height lyric/queue switching, likes, moving-art preferences and footer transport/seek routing. Radio and desktop-controlled playback have landscape regressions as well.

The sidebar/footer revision passed the full Flutter suite: **3,122 tests passed, 4 skipped**. The final sidebar/workspace regressions passed **17 tests**, including the recording-specific radio lyric guard. Flutter analysis reported no errors; existing repository warnings and Flutter prerelease deprecation notices remain.

Widget rendering is not physical-device certification. The debug APK attempt stopped with **No Android SDK found** in this Linux workspace. APK installation, iPad builds, real-device rotation/multitasking, hardware keyboard/pointer behavior and native USB/casting playback remain device checks. This UI work does not establish new audio hardware capabilities.
