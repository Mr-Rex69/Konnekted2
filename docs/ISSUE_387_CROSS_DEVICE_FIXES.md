# Issue #387 — Mobile fixes and verification

Source: https://github.com/lokal-music/lokal-mobile/issues/387 (including offline queue follow-up).

1. **Main artist and duplicates:** desktop catalogue album_artist now survives import/copy. For displayed linked tracks, use a credited album owner when present among artist credits; recording identity compares that owner, while preserving the complete artist text in stored tags.
2. **PC marker in Search:** a labelled computer icon distinguishes linked desktop song rows.
3. **PC lyrics on mobile:** streamed linked songs request their saved desktop lyrics using the existing paired-authenticated endpoint. Open Lyrics panels invalidate/reload when new lyrics arrive, with no obligatory audio-file copy.
4. **Save path:** Desktop Link → Copy missing songs offers a target among previously granted Android music folders, persisting the selection. An unavailable selected grant fails rather than writing somewhere else. Legacy default remains the first writable selected music folder.
5. **Artwork search:** when an exact album match fails for the first credited artist, query at most two other credited artists, still requiring exact album/artist match. Does not adopt random search hits.
6. **Offline bar:** shows briefly (five seconds), then collapses while connectivity remains offline. It can reappear for a fresh offline transition; underlying connectivity state remains accurate.
7. **Automatic updates:** About → Automatic update checks, enabled by default, persistent opt-out. Manual Check for updates remains available even when the toggle is off.
8. **Your Mixes:** tapping a mix title opens a browsable mix track page; tapping collage retains quick-play behavior.
9. **Offline desktop queue:** automatic next-track progression probes shared desktop availability (including locally cached originals), skips unreachable PC-only entries, and has a no-endless-loop guard.

Desktop PR complements this branch with album-artist duplicate preference, browsable mix titles and mobile-origin file placement under the selected desktop download drive.

## Test plan

- SZA/Kendrick-style multi-artist tags: import, library/search display, duplicate preference with same title and similar duration; unrelated masters must stay distinct.
- From Search, identify linked PC files; start PC song with paired desktop online and confirm saved synchronized lyrics populate before or shortly after playback.
- With desktop powered off, queue two PC-only tracks then a phone-local track: playback should continue to the local entry, not hang; with cached originals, cached PC tracks must still play. Also test all-offline queue and repeat-all.
- Choose a phone target in Desktop Link; copy, verify path and metadata; revoke SAF grant and verify actionable failure with no fallback. Reverse phone→PC test is in desktop PR.
- Artwork: try collaboration tracks, albums with many editions, and unrelated similarly named releases. Confirm only verified covers display.
- Offline notice: five-second auto-collapse, reconnect, brief network changes and app startup with airplane mode.
- Toggle automatic updates off, restart, reconnect, verify no background check/prompt; manual button still works. Toggle on and repeat.
- Tap mix title (browse), cover (play), and navigate Back.
- Verify on Android with large 5k+ libraries and NAS/WebDAV/SMB tracks.

## Limitations

Only source-level checks and added focused tests can be reported here; Flutter analyzer, tests, APK CI and real-device audio/network verification must be run before merge. The on-demand lyrics endpoint requires a recent paired desktop and saved lyrics on that desktop.
