import 'dart:math' as math;

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

 
/// Smooth opacity and occupied height for independently timed fullscreen
/// supporting vocals. This is driven by the existing lyrics ticker rather than
/// an AnimatedSwitcher mounted inside a line rebuilt every frame.
///
/// When voices change, retain the outgoing line until it has faded to zero,
/// then reveal the incoming line. This prevents a replacement from flashing
/// at full opacity or jumping the following lyrics by its entire height.
class FlowingBackgroundVocalReveal {
  int visibleIndex = -1;
  double value = 0;

  void reset() {
    visibleIndex = -1;
    value = 0;
  }

  /// Returns true when visible content/geometry changed this frame.
  bool advance(
    int activeIndex,
    double elapsedSeconds, {
    bool reduceMotion = false,
  }) {
    final beforeIndex = visibleIndex;
    final beforeValue = value;
    if (reduceMotion) {
      visibleIndex = activeIndex;
      value = activeIndex < 0 ? 0 : 1;
      return beforeIndex != visibleIndex || beforeValue != value;
    }

    // New vocal: start the text at zero opacity *and* zero height.
    if (visibleIndex < 0 && activeIndex >= 0) {
      visibleIndex = activeIndex;
      value = 0;
    }
    final target = visibleIndex == activeIndex && activeIndex >= 0 ? 1.0 : 0.0;
    final dt = elapsedSeconds.clamp(0.0, 0.05);
    final amount = 1 - math.exp(-dt * 11);
    value += (target - value) * amount;
    if ((target - value).abs() < 0.012) value = target;

    if (value == 0 && visibleIndex != activeIndex) {
      visibleIndex = activeIndex;
      // Incoming vocals remain at zero for this frame before fading in.
    }
    return beforeIndex != visibleIndex || beforeValue != value;
  }
}
