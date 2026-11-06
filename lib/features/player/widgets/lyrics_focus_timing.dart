import 'package:flick/services/lyrics_service.dart';

/// Focus a lead until BOTH its lead words and its attached backing words
/// have finished. A subsequent lead may start while the previous background
/// singer is still sounding, but must not steal the focus until the later of
/// those two explicit end times. Start-only LRC (no end timestamps) retains
/// the standard next-line-start handoff.
int focusedLeadUntilVocalsFinish(
  List<LyricsLine> leads,
  Duration position, {
  Duration leadAhead = Duration.zero,
}) {
  var latest = -1;
  final lookAhead = position + leadAhead;
  for (var i = 0; i < leads.length; i++) {
    if (leads[i].timestamp <= lookAhead) latest = i;
    else break;
  }
  if (latest < 0) return -1;

  // Hold the oldest unfinished vocal group. On backward seeks this pure
  // selector recomputes directly from the new position, without sticky state.
  for (var i = 0; i < latest; i++) {
    final line = leads[i];
    if (line.timestamp > position) break;
    final words = line.words;
    final backing = line.backgroundWords;
    final leadEnd = words?.isNotEmpty == true ? words!.last.end : null;
    final backingEnd = backing?.isNotEmpty == true ? backing!.last.end : null;
    if ((leadEnd != null && leadEnd > position) ||
        (backingEnd != null && backingEnd > position)) {
      return i;
    }
  }
  return latest;
}
