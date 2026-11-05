import 'package:flick/services/lyrics_service.dart';

/// The fullscreen player needs a separate visual lane for supporting vocals.
/// The source's [bg:] rows may already be attached to leads, or may be
/// standalone voice='bg' events. Never let them replace the lead timeline.
List<LyricsLine> flowingBackgroundVocalLines(Iterable<LyricsLine> source) {
  final found = <LyricsLine>[];
  for (final line in source) {
    if (line.backgroundText?.trim().isNotEmpty == true) {
      final words = line.backgroundWords;
      found.add(LyricsLine(
        timestamp: words?.isNotEmpty == true ? words!.first.start : line.timestamp,
        text: line.backgroundText!,
        words: words,
        voice: 'bg',
      ));
    }
    if (line.voice == 'bg' && line.text.trim().isNotEmpty) {
      found.add(line);
    }
  }
  found.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return found;
}

/// Only return a singer while its independent words are sounding.
/// The same singer can continue beneath a newly focused lead row.
int activeFlowingBackgroundVocalIndex(
  List<LyricsLine> voices,
  Duration position,
) {
  for (var i = 0; i < voices.length; i++) {
    final line = voices[i];
    final words = line.words;
    final start = words?.isNotEmpty == true ? words!.first.start : line.timestamp;
    final last = words?.isNotEmpty == true ? words!.last : null;
    var end = last?.end ?? start + const Duration(seconds: 4);
    if (last != null && end <= last.start) {
      end = last.start + const Duration(milliseconds: 500);
    }
    if (position >= start && position < end) return i;
  }
  return -1;
}
