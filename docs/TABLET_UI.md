# Tablet interface

The Flutter app uses available logical window space to compose a tablet workspace on Android tablets, foldables and iPads. It shares Lokal's theme and playback/navigation bindings with the phone UI.

## Composition

- From 600 logical pixels wide and a 480-pixel window height, persistent navigation replaces the floating phone dock. A compact icon rail accommodates portrait and narrow windows; a labeled sidebar appears from 1000 pixels.
- With music playing, windows from 1180 pixels can show the existing editable queue in a 320-pixel right panel. With that panel open, the left sidebar stays compact until 1280 pixels. Its close control and the player's queue action toggle the panel. Radio retains its station queue.
- Playback occupies a dedicated bottom strip with artwork, track identity, previous/play/next, seeking, queue and full-player actions. It does not collapse while browsing. Radio has no fabricated seek progress.
- The central navigator remains mounted across resizing and panel changes. Pages receive their actual pane size and bottom clearance, so their grids and artwork respond to the space they have. The software keyboard does not change the navigation mode.
- Local home's carousel uses larger artwork with a bounded 380-pixel maximum and explicit previous/next browsing controls. Mixes, collection tiles, album grids and discovery shelves adapt their density independently of navigation. Tablet typography is bounded instead of scaling with screen width.
- Landscape playback places the artwork/stage beside a scrollable control column in the modern, classic, desktop-controlled and radio players. Their existing lyrics, queue, transport, artwork and dismissal behavior are retained.
- Wide album headers put artwork beside metadata. Wide You pages separate recap/statistics content from devices/accounts. Settings uses a category/detail layout when its content pane is at least 840 pixels wide; search remains available across categories.
- Standard modal sheets are bounded to 640 pixels. Colors come from the existing Lokal theme, including light themes.

## Rotation

Android's manifest no longer forces portrait. Flutter keeps phones in portrait and allows tablet rotation using the display's logical shortest dimension, including when restoring the orientation after fullscreen video. The existing iPad orientation declarations already include landscape. Window geometry, rather than platform names, chooses the rendered layout.

## Validation

`test/konnekted/tablet_workspace_test.dart` exercises portrait/landscape, narrow split windows, keyboard and safe-area insets, light/dark themes, 200% text, pane measurements, navigation/scroll retention, carousel selection, album headers, Settings categories/search and display-based rotation policy. Remote and radio player tests also cover landscape tablets and large text.

Run:

```sh
flutter analyze --no-pub
flutter test --no-pub
```

Widget rendering and interaction tests are not physical-device certification. Android APK installation, iPad builds, real-device rotation/multitasking, hardware keyboard/pointer behavior and native playback with USB/casting remain device checks. This UI change does not modify the audio engine or establish new hardware capability claims.

Observed in the Linux cloud workspace on 2026-11-10:

- Full Flutter suite: **3,107 passed, 4 skipped**.
- Final focused regression run: **74 passed**, followed by the **9 tablet workspace checks** after final inset adjustments.
- Analysis: **no errors**; the repository still reports warnings and SDK deprecation notices. The new layout files report only the Material import deprecation on this environment's Flutter 3.50 prerelease SDK.
- The debug APK command stopped with **No Android SDK found**. No APK or iPad device-build success is claimed.
