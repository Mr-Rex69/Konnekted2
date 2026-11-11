# Desktop library merge and file copies

The Desktop link screen keeps a merge status card after approval. It reports
catalogue song counts, history/library activity, profile finalization,
completion time, and paused/disconnected state. Sync now retries the merge.
The last successful timestamp is retained for the paired desktop/user.

Merge imports desktop songs as streamable entries and combines likes, playlists
and completed-play history. It does not silently copy every audio file. The
paired desktop profile supplies the You display name, username and a locally
saved avatar. Older desktop builds without the profile endpoint still merge
history and library data. A desktop update is required for profile import.

Copy missing song files is a separate action with a two-direction count preview.
The phone compares local readable files with the desktop's playable catalogue,
using the existing desktop track matching and artist/title/duration matching on
the phone. These are song-level matches, not proof that two encodings are
byte-identical. Existing local versions are kept. Content URI access is checked
when its individual upload is staged; an inaccessible grant is a failed copy.

Copies run sequentially while both apps stay open and linked. Each file becomes
permanent only after a complete response (and the SHA-256 check when provided).
The desktop original-file endpoint avoids playback transcodes. The phone never
overwrites an existing destination file, and originals are never moved/deleted.
The result lists failed song titles. Checking again rebuilds the plan, skipping
completed files and retrying unfinished work. There is no background/resumable
byte-range transfer service: a disconnected/incomplete file starts over next
time. Desktop uploads retain the existing supported-format and 1 GiB limit.
A desktop update is required for two-way original-file copying.

Badge calculations and earned thresholds are unchanged. The You page and
milestone screen refresh from milestone change notifications.

Desktop artwork markers are retained even when thumbnail indexing has not
finished. The artwork service can recover an older markerless desktop row from
its source URI, ask the desktop for full/embedded artwork, and let newly mounted
cover cards immediately reuse an already resolved local image.

Validation is source-level only; paired-device transfer, image display and
interrupted-copy behavior still need device verification.

Pairings no longer disconnect after three idle minutes. A saved pair retries
network or temporary profile failures, and returning from the background reopens
the socket unless the user explicitly disconnected it. The OS may suspend
background networking; keeping a pairing does not keep the PC awake. With an
updated desktop, a changed LAN address is rediscovered and proved against the
existing pairing before its bearer is sent or its secure origin is updated.
Forget and replacement pairing remain guarded against late recovery callbacks.
Physical overnight iOS/Android recovery still needs device validation.

The Milestones screen uses Lokal surfaces, accent colors and achievement cards;
badge calculations remain unchanged. Online artist pages group releases into
Albums, EPs, Singles, Features and other available release categories. Playback
source order is configured globally in Settings instead of on artist pages.

New playback requests cancel foreground resolution and take precedence over
prefetch work. Guest YouTube resolution prefers the native resolver and retries
refused streams with smaller client-appropriate download chunks. These changes
still require Android playback verification. Startup restores the saved accent
before rendering, and launcher aliases follow the selected theme. The full-player
device picker is centered inside the safe area with a dimmed backdrop.

Library operation sync applies likes and playlists before listening history.
Each received page rebuilds a changed playlist once, saves the batch of winning
likes once, and reuses one song-library snapshot plus cached matches. Hash-only
metadata operations and already-current tag values do not rewrite song rows.
The progress label includes metadata because the same operation log carries
song tag edits as well as likes and playlists. Phone edits trigger a debounced
sync; desktop changes are checked more often during recent interaction, with
slower checks while idle. Pairing recovery remains enabled while idle.

Desktop-control notifications fetch covers through the authenticated artwork
service and pass the locally cached image to Android. Position-only notification
updates retain artwork. Late cover completions are guarded against track,
connection and output changes. Missing art uses Lokal branding, and the output
label shows the device name without a product prefix.

These follow-ups have source-level validation only; notification artwork and
sync latency still require a paired-device check.

Phone uploads now fall back to the scanner's saved Android MediaStore URI when
scoped storage denies a filesystem read. The planner also includes such songs
when only the URI remains accessible. Container extensions come from the
original filename when available, with aliases for WavPack/DSD and common codec
labels. An unreadable or unsupported song fails explicitly rather than being
counted as sent. Upload completion requires an acknowledged desktop track ID;
failures show a reason beside the song title. The upload/response operation has
one overall timeout and observes both stream and response errors.

Local FLAC and WebM receiver probes using temporary files and an isolated
in-memory DB confirmed that the desktop endpoint saves those uploads. WebM
acceptance requires the desktop receiver update. It does not
validate Android permissions, phone networking or the paired-device transfer.

Home retains established shelf/mix data while library and favorite providers
reload during sync. Empty operation pages and successful no-change checks do
not invalidate favorites/playlists; profile refresh has its own callback.
History import bursts are coalesced before Home re-queries them, with a trailing
refresh so the last changes are still reflected.

Android library sync now has a separate, silent progress notification. Explicit
merges show Preparing immediately; automatic checks notify only when work is
reported. It shows phase and processed counts, uses a determinate bar only when
a total is known, and ends in Complete or Paused. Progress updates are coalesced;
terminal states flush immediately. It does not replace playback controls.
Notifications use the app's existing Android notification permission and open
the app when tapped. Completed/paused notices expire after 20 seconds; ongoing
notices expire after two minutes without an update if the process is killed.
This status notification does not itself keep transfers running in the
background. Android notification rendering and the recorded Home flicker still
require verification on the reported phone; validation here is source-level.
