# Embedded Soulseek on Lokal Mobile

Soulseek is integrated directly into the Android Rust library with an MIT-licensed
protocol client. This is **not** an installation of Seeker, slskd, or any
separately executable plugin. The user only supplies a username and password
in **Settings → Data → Accounts → Soulseek**. New unused usernames can create
accounts on first successful connection.

## User flow

- The opt-in account is secured by Android's Flutter secure storage; credentials
  are not copied to SharedPreferences or sent through HTTP endpoints.
- A dedicated **Soulseek** search scope sits next to All, Local, Online.
  Queries are rate-limited by input debounce and performed outside the UI isolate.
- Results identify peers, folder groups, sizes, formats and free slots. Select
  tracks or an album; downloads can be paused, resumed, retried or cancelled.
- Completed files are imported with Lokal's existing library saver; unfinished
  files can resume from their persisted private-app staging directory.
- Sharing is disabled by default. If enabled it shares the **first local music
  library folder**, never all library sources or the device root. It requires a
  readable filesystem directory. SAF-only document trees cannot currently be
  served by the Rust protocol library; Lokal reports that rather than
  pretending a share is active.
- **All files** inside the shared root are visible to other Soulseek users.
  That can include cover art, notes, playlists and lyrics files. Only enable
  sharing for a folder suitable for public access.
- A user-visible foreground service keeps downloads and opted-in sharing alive
  while Android permits. On Android 15+, dataSync foreground services are
  subject to a time budget. Dismissing the app or Android's service timeout
  closes the native P2P session. Android battery restrictions and NAT/ISP
  settings may still prevent some peer connections.

## Engineering notes

- Library: [soulseek-rs-lib 20.0.0](https://github.com/michel/soulseek-rs),
  pinned to commit 3c5f1d12f25f98730ad8f1ca57621250d7c3bd41. The vendored
  snapshot includes one Android file-limit-width compatibility fix; see
  `rust/vendor/soulseek-rs-lib/LOKAL_PATCHES.md`.
- Native ABI: rust/src/soulseek_ffi.rs; Dart facade:
  lib/services/soulseek_service.dart; Android foreground service:
  android/app/src/main/kotlin/com/mossapps/flick/SoulseekForegroundService.kt.
- The library allows one active session per Soulseek username. Using desktop
  and mobile simultaneously requires different usernames.

## Verification before merge

Run Android CI (`cargo test --locked`, `flutter test`, `flutter analyze`,
both APK flavors), then test on a real Android phone: login, same-username
collision, NAT/firewall fallback, search, downloads, resume after process death,
folder sharing/visibility, library metadata and background foreground-service
limits. No live network or handset validation is claimed by this document.
