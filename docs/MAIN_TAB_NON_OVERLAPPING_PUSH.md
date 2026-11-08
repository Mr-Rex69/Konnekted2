# Main-tab navigation: edge-to-edge, no overlapping pages

## Reference: 1 November 2026 screen recording

The user-recorded PixelPlayer segment (~9–17.9s) shows clear Home,
Search and Library navigation, while Lokal's preceding segment shows a much
less cohesive Home/Library transition. PR #390 still used `AnimatedSwitcher`
with a `Stack`, a 48%-width incoming translation and a 22%-width departing
translation. Both full-screen pages therefore occupied overlapping pixels
throughout most frames. Making those offsets larger did not remove the
visibly layered effect.

## Implementation

`LokalNavigationSwitcher` is now a dedicated stateful, single-controller
horizontal push. For normal forward navigation at animation progress `p`:

- The outgoing tab occupies horizontal interval `[-p, 1-p]` in viewport widths.
- The incoming tab occupies `[1-p, 2-p]`.
- Their boundaries **always meet at `1-p`**. Both are fully opaque, so
  they never overdraw one another or expose an unpainted gap.
- Reverse navigation and RTL mirror the intervals.
- One 330ms emphasized cubic drives both transforms. There are no two
  independent outgoing/incoming durations to drift apart.
- The incoming tab builds before its first visible region, while the old
  tab remains available behind the seam until completion.
- The widget ancestry and keyed `AnimatedBuilder` instances remain stable,
  so Cover Flow, Home sections and other stateful tab content aren't torn
  down and reconstructed when the transition starts or ends.
- On rapid additional selections, the prior outgoing tree is discarded and
  only the latest outgoing and current tab remain mounted.
- Outgoing trees are disabled for focusable semantics, input and animations,
  and fully disposed after the transition. No persistent IndexedStack.
- Reduced-motion, animation-off and Ultra Performance Mode suppress motion.

Unlike PixelPlayer's original Compose crossfade/half-translate, this is a
**strict spatial partition**. That intentionally obeys the explicit request
to remove overlapping layers and avoids ghosting on dark/glass Lokal pages.

## Device validation

1. Compare Home → Library → Search → Home with the PixelPlayer section of the
   recording. The boundary between the pages must remain crisp and never
   display both screens in the same pixel.
2. Repeat fast Home ↔ Library switches, including a third tab selection
   before 330ms. Only the newest outgoing screen should be retained.
3. Confirm Home Cover Flow keeps its state during departure, and the next
   page does not rebuild when the exit animation finishes.
4. Test RTL and forward/backward tab order, as well as reduced motion.
5. Check for black borders, keyboard inset changes, scroll retention,
   accessibility double focus, and mini-player/dock continuity.
6. Profile raster/build frame times on device. Static geometry tests cannot
   establish runtime FPS on real Android devices.

Focused widget tests assert adjacent bounds at multiple animation progress
samples, tab lifetime, rapid switching, RTL, and reduced-motion behavior.
Flutter build/device testing was unavailable in the current environment.
