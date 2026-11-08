# iOS add-on diagnostics and sign-in fixes

The additional iPhone report identifies Amazon and Deezer as the failing
add-ons. The older log's hashed source IDs and generic `DiscoveryException`
labels do not establish the underlying provider response. Successful cache
adoption from another add-on is not evidence that Amazon or Deezer works.

## Playback and diagnostics

Each add-on runtime/preparation now logs its provider category, installed
version, platform, operation mode and an attempt ID unique across app runs.
Stage and method events link metadata, availability, enrichment, signed HTTP
status, transfer, decryption, conversion and file validation. Failures use
closed categories such as `http_403`, `verification_required`,
`recording_unavailable`, `runtime_script`, `timeout` and `decryption`.
Metadata diagnostics are presence flags; quality labels are allowlisted.
Guest messages, response bodies, account values, track IDs, URLs, credentials
and local paths are not exported. Existing source hashes allow correlation
with the higher-level discovery messages.

Two host defects were corrected:

- Availability options now retain explicit Spotify/Deezer/Qobuz/Tidal mapping
  fields. Amazon's published add-on accepts `deezer_id` for cross-catalogue
  matching, but the old adapter only supplied its legacy `spotify_id` field.
  After enrichment, Deezer's check now receives the updated canonical ID;
  a foreign numeric ID is not implicitly asserted to be a Deezer recording.
  The provider's availability/authorization check still runs.
- Ordinary add-on HTTP responses no longer call `detachSocket()` during
  cleanup. That API removes the connection from Dart's pool before a pending
  return callback can finish. Completed responses keep normal pool ownership;
  unread or interrupted responses close through stream cancellation instead.

These are verified adapter defects, not proof that every failure in the old
log has the same cause. The new diagnostics are needed for any remaining
service, account, availability or codec refusal on the affected iPhone.

## Account page

iOS YouTube and add-on authentication now use full-screen, safe-area pages
whose layout resizes around the keyboard. Web views claim their own touch
gestures and retain vertical scrolling/text interaction. Other platforms keep
their modal sheet, with sheet dragging disabled and keyboard insets applied.
YouTube session capture still requires the live Music profile and signing
cookie; account material never appears in sign-in diagnostics.

Google passkeys cannot be enabled by a generic WKWebView setting. Apple's
[passkey documentation](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
requires an association with the relying-party domain for this embedded app
flow. Lokal cannot create Google's association. The page explains how to use
Google's “Try another way” option. A future system-browser OAuth integration
would need its own registered client/callback and an authorized account flow;
Safari cookies cannot simply be imported into the existing WebView session.

## Validation

The combined Morneye, discovery, sign-in-frame and short-stream regression
selection passes 413 tests, with two optional checks skipped. Coverage includes
Amazon cross-catalogue matching, Deezer canonical-ID retry, diagnostic redaction,
20 real HTTP response lifecycles, completed/unread/active response cleanup,
and compact iPhone keyboard layouts with a reachable submit button.
Focused analysis has no errors or warnings; the existing package file still
has style infos. The new regression tests are included in iOS CI.
The debug Dart/asset bundle builds successfully. This is not an IPA build.

Flutter widget tests validate the layout; they do not prove a Google login,
passkey authentication, native WebKit keyboard behavior, or audible playback
on a physical iPhone. No live Amazon/Deezer account or affected phone is
available in the repair environment.
