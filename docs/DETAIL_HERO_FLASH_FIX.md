# Album and artist hero flash — 1 November 2026

## Recording evidence

The supplied 15.56-second Android recording shows the transition from the
Home/Now Playing surfaces into AC Soul Symphony's artist page around 3.9–4.2s.
The new detail header first appears dark/empty, followed by a sudden large
yellow artwork reveal. Later navigation among album, artist and fullscreen
player shows similar late media changes. These are visible changes inside the
detail hero, distinct from the existing push/pop slide itself.

## Code paths addressed

1. **Decoded artwork arrives after the page paints.** Existing
   `CachedImageWidget` switches directly from a placeholder to its decoded
   image on the first loaded frame. For artist/album heroes only,
   `revealOnLoad: true` now uses a 240ms image-only crossfade and
   `gaplessPlayback` for subsequent provider changes. All list thumbnails
   keep the original no-animation rendering path.
2. **Artist portrait can resolve asynchronously.** Artist metadata from Riverpod,
   Isar and online providers may arrive after the first route frame.
   `LokalArtworkReveal` retains the previously displayed hero while the
   replacement transitions in for 260ms. The rest of the page stays opaque.
   When no portrait exists yet, local song artwork is used instead of a
   black/empty canvas where available.
3. **A second decode after entry.** The detail page changed
   `CachedImageWidget.useThumbnail` from true to false when `_relatedReady`
   became true at the end of the route animation. That requests a different
   cache-width image and can briefly replace an already-painted frame. The
   hero now uses the same physical-size-aware decode on every build; full
   resolution appropriate to its displayed size is preserved, rather than
   launching another decode at 320ms.
4. **Asynchronous background recoloring.** A late dominant-color extraction
   used to instantly change the entire `Scaffold` and header gradient during
   navigation. The detail page now uses its stable theme background. Existing
   header theme/accent styling remains, and online artist portrait persistence
   in Isar is retained without the extra palette decoding.

## Device acceptance checklist

- Open local and online album/artist pages with cold and warm caches. The cover
  may resolve later, but must not blink from black to artwork or instantly
  recolor the entire page.
- Compare AC Soul Symphony opening at 3.9–4.2s and Art of Tones opening near
  the end of the recording with the new APK.
- Switch between online/local artwork, change an artist portrait while the
  screen is open, return with Back, then re-enter. Check there are no
  duplicate Heroes or broken artwork references.
- Recheck WebDAV/SMB and embedded local covers; existing media fallback and
  artwork sources must remain functional.
- Toggle reduced motion; image fades must become instantaneous. Small
  thumbnails and scroll lists should keep their original render path.
- Profile UI and raster frame time on a real Android device, including 4GB
  phones, because source checks cannot confirm smoothness.

## Validation limits

Tests cover the artwork-only crossfade, stable source identity, reduced
motion, gapless image provider updates and the default unanimated image path.
Flutter analyzer, automated test execution, APK build and on-device FPS
remain unverified in this environment.
