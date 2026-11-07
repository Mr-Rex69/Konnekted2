# Install the iPhone beta from Windows

The iPhone app targets iOS 16 or later. An unsigned IPA must be signed for your
iPhone before installation. Hosted macOS/Xcode builds the app; you can download,
sign and install it from Windows without owning a Mac.

## Choose the matching beta

Use an iPhone beta from [GitHub Releases](https://github.com/lokal-music/mobile/releases).
A published sideload beta includes the exact IPA, SHA-256 checksum, matching
source archive, license notices, crash symbols and `qualification.json`. Its
release notes identify the source commit and successful qualification run.
Engineering artifacts from a different build do not qualify the current source.

Publication requires the Apple build, installed iOS 18.6 and 26 tests, mixed and
background transfer/process-recovery checks, and independent IPA/source audit.
Signing, physical installation/upgrade, live accounts and receivers, and real
playback routes remain your acceptance step. This is a pre-device beta.

## Transfer and feature behavior

Native desktop copies continue through the iOS background transfer service after
all files have been admitted. Keep Lokal open while the copy plan says it is
preparing files. Imported downloads are reconciled into the library when Lokal
is active. iOS decides scheduling; reopening Lokal reconciles interrupted work.
Do not use new copy plans to bypass an uncertain upload: use the queue's receipt,
retry and cancellation actions.

Older desktop peers without the durable upload protocol use the foreground copy
flow for the complete plan. Keep Lokal open and the desktop awake on Wi-Fi for
that flow. Source folders requiring foreground access retain that path too.

Soulseek search, downloads and optional sharing require Lokal in the foreground.
iPhone stops its peer session when the app backgrounds; reconnecting recovers
unfinished downloads. Background music playback, lock-screen controls, ordinary
imports, lyrics, library/playlists, add-ons, network libraries and supported
casting remain part of the iPhone app. Android parity is frozen through PR503
(Android 7.4.7) for this beta.

Home Screen widgets and Android direct USB/bit-perfect output are excluded. No
WidgetKit/App Group setup is required for sideloading.

## Historical engineering-build transfer behavior

The existing engineering build uses foreground desktop copying. Keep Lokal open with the iPhone
unlocked and the desktop awake on Wi-Fi during a copy. After an interruption, check for
missing files again; completed copies stay local. Background music playback and
lock-screen controls remain available. The replacement native background-copy
engine remains disabled while its [completion milestones](IOS_FIRST_RELEASE.md)
are implemented and qualified.

## Get the artifact

1. Open the **iPhone build and sideload package** run in the
   repository's Actions tab. During development the runs are linked from
   [the iPhone pull request](https://github.com/lokal-music/lokal-mobile/pull/172).
2. Download the `Lokal-iPhone-engineering-unsigned-<run>-attempt<attempt>` artifact (earlier runs omit the attempt suffix) and extract the outer ZIP.
   The app is **`Lokal-unsigned.ipa`** inside it. Keep the `.ipa` extension.
3. Check its SHA-256 against `Lokal-unsigned.ipa.sha256`, for example in
   PowerShell:

   ```powershell
   Get-FileHash .\Lokal-unsigned.ipa -Algorithm SHA256
   ```

`Lokal-unsigned.ipa.json` identifies the source commit, version/build and Apple
toolchain. The artifact also contains the project's license/notices and matching
source archive. Simulator screenshots/logs are in the diagnostics artifact.
The latest complete hosted engineering checkpoint recorded for this stack is
[build 111 on PR349](https://github.com/lokal-music/lokal-mobile/actions/runs/41005225249).
Its iPhone build, iOS26 acceptance and independent IPA-audit jobs passed. Use
its own packaged manifest and checksum when downloading; a checksum from an
earlier build does not verify build111.

The separately qualified
[build103 on PR345](https://github.com/lokal-music/lokal-mobile/actions/runs/40992683570)
also passed iOS18.6/26 acceptance and its independent package audit. Its artifact
is `Lokal-iPhone-engineering-unsigned-103-attempt1`, with IPA SHA-256
`b976c72a458edd43ad743da8241ddd1d1368e4aae821218824f86d3e72d62a7d`
and source tree `4e94d6a6c0ed685428ed7dad3afcc27a6939d0b6`.
These qualification records are distinct from downloading and reinspecting
the packages in this workspace, and neither is physical-device acceptance.

Newer source through PR355 and the subsequent Clear/Forget preservation
continuation is **not contained in those earlier artifacts**. Those older records do not qualify the current candidate; use a successful
matching newer artifact to test current source. Those historical builds keep
native import/upload disabled and use foreground copies. The enabled release
candidate described above must pass the installed and background/relaunch
[transfer gates](IOS_TRANSFERS.md) before publication. Signing, installation/upgrade,
live services and receivers, and physical playback acceptance remain outstanding.

Build86 remains a separately preserved older fallback:
[run40951126722](https://github.com/lokal-music/lokal-mobile/actions/runs/40951126722),
IPA SHA-256 `398d7b2f4d17de1f143bcb33c92673e379a2bcad669c9b13746b58dd94c7159e`.
Keep every package's frozen source and crash symbols with that exact build.

## Sign and install

1. Install [Sideloadly for Windows](https://sideloadly.io/) using its official
   instructions, including the Apple device/iTunes/iCloud prerequisites it lists.
   [AltStore Classic for Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
   is an alternative.
2. Connect an unlocked iPhone by USB and accept the computer trust prompt.
3. Select the iPhone, choose `Lokal-unsigned.ipa`, and sign/install using your own
   Apple account in the sideloading tool. Do not put your account/password,
   certificates or provisioning files in GitHub, CI, app logs or chat.
4. Follow iOS prompts to trust the developer profile under **Settings → General
   → VPN & Device Management**. On iOS 16 or later, enable **Developer Mode** in
   **Settings → Privacy & Security** if requested, including the required restart.
5. Launch Lokal. Release builds use AOT and should run without an attached
   debugger. Report the build number and iPhone/iOS version if launch fails.

A paid Apple Developer membership is not required for the free-account install
route documented by these tools. Free-account apps normally expire after seven
days and need refreshing; Apple also limits app/App ID slots. AltStore itself
uses a slot. Refresh requires the tool's current connectivity/setup conditions;
it is not guaranteed merely because an auto-refresh option is enabled.

## Import and listen

- In **You → Library → Folders**, choose **Import music** and select files or a
  folder from Files, including a File Provider such as iCloud Drive.
- Lokal copies the selection into its own `Music` folder. The original files
  remain with their provider. Folders keep artwork/lyrics sidecars alongside the
  music. Imports are snapshots; later changes in the original folder need a new
  import rather than Android-style whole-device watching.
- The copied music is visible through the iPhone Files app and file sharing.
  Database internals are stored separately. Do not delete imported music unless
  you intend to remove those local copies.
- Choose headphones/AirPlay through iPhone system controls or Lokal's iPhone
  output picker. Ordinary USB DAC playback uses iOS's system route. The app does
  not certify that route as bit-perfect or native DSD.

Import music before importing an M3U/M3U8 playlist from Library's playlist menu;
playlist entries are matched to the existing library. iPhone manual imports keep
an app-owned playlist snapshot, so removing the selected File Provider source
does not invalidate it. Later edits to that external source require another
import. M3U/M3U8 export and Replay's CSV/TXT export use the native Files save
picker; cancelling leaves the library unchanged. Playlist text must be UTF-8 and
no larger than 10 MB. These adapters have contract coverage; native picker and
File Provider acceptance remains pending.

## Refresh and update without losing the library

Use the same Apple account and stable app identity in the signing tool. Install
the newer IPA over the existing app. Refresh/re-sign the existing installation
before it expires. **Do not uninstall Lokal as a routine refresh step**: uninstall
can remove imported music and app data. Back up music and user data before
changing signing accounts or bundle identifiers.

The port includes container-path rebasing for iOS updates, but Windows refresh,
upgrade and Keychain preservation still need real-device acceptance testing.
Changing signing identity can affect Keychain access independently of whether
the ordinary app data survives.

## Device acceptance record

Record the exact source commit/build and results for:

- First installation, cold launch without a debugger, and file/folder import.
- Playback with the screen locked and app backgrounded; play/pause/seek/skip from
  lock screen and Control Center, plus radio/library ownership changes.
- Calls/Siri/alarms; wired and Bluetooth detach/reconnect; ordinary USB DAC and
  AirPlay output where hardware is available.
- Playlist/likes/history survival after a second-build upgrade and signing refresh.
- File Provider cancellation/errors, insufficient storage, and desktop copies
  across Wi-Fi changes and app suspension.
- Online source sign-in, playback/downloads and add-ons using opted-in accounts.

Keep tokens, cookies, pairing secrets and personal file paths out of shared logs.
Published sideload betas remain pre-device builds until these checks pass.
