# Android Cast receiver handoff

Confirmed source faults: selecting a route returned success before the Cast session started; nullable media-client calls and swallowed Android bridge errors lost the subsequent load. Android dropped the MIME type, paused/autoplay flag and starting position passed by Dart. Local SAF grants were rejected instead of served over HTTP. The local-output list also included remote receivers, allowing route-only selection to open an empty Cast receiver app.

The sender now waits for session and media acknowledgements. Android uses the same confirmed paused-load ownership handoff as iOS. It keeps local playback until receiver preparation succeeds and pauses local output before remote Play. Receiver shutdown must be confirmed before local ownership resumes. Errors and timeouts propagate to the existing settings UI. Remote receivers are selected through the Cast handoff rather than the local-only output list.

Original SAF bytes use the existing bounded staging cache. The token-scoped media server supports GET, HEAD, ranges and CORS/private-network preflight, advertises a Wi-Fi/Ethernet address rather than cellular/VPN, and requests Android LAN access through the existing permission bridge. Authenticated network sources remain on the sender's authorized download path; account headers are not forwarded as Cast metadata. No audio transcoding or native PCM/DSD processing changes are introduced.

Automated checks cover ownership failure/cancellation/shutdown uncertainty, channel arguments and errors, staged-file identity, interface selection and real local HTTP range/preflight requests. Robolectric tests cover acknowledgement, timeout and late-callback completion plus actual Cast media request arguments. CI compiles the Android sender and MainActivity channel handler. These checks do not establish physical receiver playback.

Device validation still required:

- Start a supported MP3 or FLAC from an Android SAF library, seek into it, and select a docked Pixel Tablet or Google Hub. Confirm metadata/audio and the starting position, then exercise receiver/Google Home controls.
- Select receivers through the Cast list; verify the local output list contains local outputs only. Check success and failure UI during connection.
- Reject Android LAN permission, remove source access, disconnect Wi-Fi, or select an unavailable/unsupported source. Confirm an error instead of a false success and confirm local recovery only after receiver shutdown.
- Advance tracks, then stop casting and confirm local playback resumes the selected track at the receiver's position. Test paused handoff and a new user selection during connection.
- Verify the existing iOS sender still connects, loads paused, hands over audio and disconnects correctly.

The reported ordinary tablet lock-screen controls work while undocked. The user reproduced missing docked Hub Mode controls with other apps' direct playback too. This change fixes Lokal's Cast sender; it does not claim Google Home mirrors arbitrary direct local playback in Hub Mode.
