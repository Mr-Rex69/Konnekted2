# YouTube playback recovery — 8 November 2026

The supplied iPhone logs show repeated direct YouTube resolution failures,
while account discovery continues to load shelves and mixes. The later log
also shows an add-on completing downloads, adopting the cache and initializing
`IOS_SYSTEM`. This is evidence of successful add-on acquisition, not a device
test of every add-on or proof of audible output.

The Android log contains both failed YouTube resolutions and successful
`source=yt` acquisitions. It also records a null assertion in Dart's
`_HttpClient._returnConnection`. The iPhone logs have unsymbolicated null
assertions; their exact call sites cannot be established from those logs.
The old exported `DiscoveryException` label does not identify the individual
YouTube client's refusal, so it cannot prove a particular country, account,
PO-token or signature error.

## Changes

- Android still prefers InnerTubeX, but a failed extraction can now recover
  through the independent direct clients. Cancellation stops the operation;
  the same failed native walk is not repeated at the end.
- The shared fallback uses the SDK-less Android profile, without advertising
  an Android SDK for which it cannot provide device attestation.
- iOS and Android's recovery path can decode AAC `signatureCipher`/`cipher`
  links and `n` throttling challenges using the current YouTube player script.
  TV and Music requests receive its signature timestamp. The original media
  client version and signature parameter name are preserved. Unsolved formats
  are discarded; actual audio bytes are still probed before cache download.
- yt-dlp EJS 0.8.0 is bundled with its licenses and pinned hashes. It runs in
  the app's existing QuickJS engine with a ten-second execution deadline and
  a bounded 256 MiB heap. The minimal adapter exposes no host bridge or network,
  file, storage or account APIs. Script downloads are bounded, cancellable,
  cookie-free HTTPS requests to validated YouTube player paths. No third-party
  extraction service or runtime solver download is introduced.
- Partial media probes disable persistent connections, so their abort cannot
  race a keep-alive handoff into Dart's connection pool.
- Exported logs now identify the attempted YouTube client and a fixed failure
  category, without copying provider errors, signed media URLs or credentials.

## Validation and limits

The discovery and selected catalogue/quality regression suites pass 320 tests
(two optional checks skipped). The changed Dart files pass focused analysis.
Repository-wide analysis still reports unrelated existing diagnostics.
The debug Dart/asset bundle builds successfully, and the packaged solver,
sandbox and license bytes match their source files. This is not an IPA or APK.

Nine native tests pass using the production `rust/src/morneye.rs` in an
isolated host Cargo harness. This includes the exact bundled EJS modules and
sandbox adapter decoding synthetic signature and throttling challenges, plus
the engine's runaway-code deadline test. It is not a full native audio build.

The controlled HTTP tests cover native failure recovery, cancellation, the
SDK-less request, ciphered TV playback including timestamp and byte preflight,
player-script host validation, credential-free requests, pinned solver hashes,
and refusing to download an unsolved encrypted format.

Live YouTube access from the repair environment is blocked by an HTTP CONNECT
403. No physical iPhone/Android playback or Apple build is claimed. Updated
builds still need verification on the affected phones, including the original
recordings, signed-in and anonymous playback, cancellation and queue advance.
