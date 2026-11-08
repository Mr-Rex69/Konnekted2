# Lokal Mobile navigation motion: no-black-frame redesign

## Reference study

Compared the two supplied 1 November 2026 screen recordings frame by frame and reviewed `PixelPlayerHQ/PixelPlayer`'s Compose `presentation/navigation/Transitions.kt` and `AppNavigation.kt`. PixelPlayer uses a shared-axis treatment with separate entering and exiting transforms; navigation preserves the previous screen while the next arrives. Its explicit Back paths reverse the direction. The examples in the recordings show artist, album, home, library, and player transitions.

In the supplied Lokal recording, the Rona Ray → Don't Know Yet album push (about 2.5–3.0 seconds) exposes a dark intermediate view and overlapping, translucent content. Root/tab/player paths also change visual treatments abruptly. The previous implementation layered a foreground `FadeTransition` on a secondary full-screen slide/scale, then wrapped Flutter's native Android predictive-back builder. Outside predictive gestures, that builder itself falls back to FadeForwards, adding another full-screen opacity pass.

## Changed architecture

1. **One full-opacity transition** for ordinary Material routes. The entering page slides from 34% of the screen toward the center; the previous page recedes 10%. Both always overlap. Pop reverses this without fading either route to black.
2. **Route consistency.** Settings, Folder Browser and online catalogue detail pages no longer bypass the standard transition with custom fade-based PageRouteBuilders. Navigation in these entry points now uses the same opacity-free route and Back treatment.
3. **Animation-layer isolation.** A RepaintBoundary protects expensive album/artist artwork while moving a rasterized scene. The previous page remains mounted until Flutter finishes the route transition.
4. **Transient tab continuity.** AnimatedSwitcher retains only the departing tab for ~230ms while the new tab appears. The old tab is disabled for input and animations during exit, then disposed. No permanent IndexedStack or library caches are introduced.
5. **Root player → nested album/artist sequencing.** Wait for `TransitionRoute.completed` (overlay actually removed) rather than racing a fixed timeout against the player close animation. This avoids concurrent transitions between the full-screen player and nested navigation.
6. **Accessibility / performance.** Animations-off and reduced-motion return the child immediately. Ultra Performance Mode disables old-page parallax; the incoming page still has a single lightweight translation and maintains full background coverage. RTL reverses the direction.

## PixelPlayer correspondence and intentional differences

PixelPlayer uses a ~350ms shared-axis slide and independent incoming/outgoing motion. This PR uses that **motion grammar** but avoids its opacity effects because Lokal's artist artwork, glass chrome, and dark dynamic backdrop make crossfade-to-background visually destructive. It also prioritizes GPU cost and transition continuity on low-memory Android devices.

A trade-off: Flutter's built-in `PredictiveBackPageTransitionsBuilder` creates a FadeForwards fallback for normal button/navigation pushes. We intentionally remove that nested fallback to eliminate black flashes. Regular Back actions and system Back commits remain supported by MaterialRoute/NavigatorPopHandler. **Interactive gesture-progress predictive-back visuals need separate Flutter-specific implementation and on-device verification; do not claim feature parity here.** The Android manifest opt-in remains.

## Acceptance matrix (device, not simulated)

- Repeated artist ↔ album navigation and Library/Search → album from the recordings: no uncovered black, double opacity, white flash or first-frame blank. Back must return in the opposite direction.
- Rapid push/pop, long titles, cache-missing covers, online/local/NAS artwork, 5500+ song libraries; ensure no UI freezes, incorrect routes or Hero flicker.
- Home/Search/Library/You switches while Now Playing is open, with both mini-player and bottom bar visible; verify no transient empty page and no permanent retained screen memory.
- From Now Playing, open current album/artist repeatedly. The player should fully finish exiting before the nested page moves in.
- Gesture Back on Android 13–17: verify commits, cancel/retry, root tab/back-exit behavior, and that no double-pop happens.
- Reduced motion, in-app animations off, Ultra Performance Mode, light/dark/OLED, RTL, large text, narrow 320dp displays.
- Profile `FrameTimingsMonitor` in profile mode: measure build/raster timings and shader compilations before/after on the same phone; static assertions alone cannot establish no jank.

## Build status

Review, syntax/source checks, tests and CI are separate from actual hardware validation. Do not merge only on the basis of the code review; the high-frequency visual complaint is best judged on device.

## Focused regression tests

- `test/core/navigation/lokal_page_motion_test.dart`: opaque foreground, absence of fade/scale layers, continuous overlap at progress 0–100%, back direction and zero-motion handling.
- `test/core/navigation/lokal_navigation_switcher_test.dart`: old tab stays present during a switch then disposes (no persistent cache), animations-off removes it immediately.
