import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flick/models/song.dart';
import 'package:flick/services/app_preferences_service.dart';
import 'package:flick/services/lyrics_service.dart';

/// Starts with the actual local lyrics as soon as a song becomes current,
/// before anyone opens a lyrics screen. The online search continues separately
/// and must never delay the initial local lines.
class LyricsPlaybackPrefetch {
  LyricsPlaybackPrefetch._();
  static final instance = LyricsPlaybackPrefetch._();

  /// A streamed desktop track's saved lyrics may arrive *after* the player
  /// initially displayed a local miss; notify open lyric panels to refresh.
  final ValueNotifier<String?> linkedLyricsUpdated = ValueNotifier(null);

  void desktopLyricsArrived(Song song) {
    invalidate(song);
    // Force a fresh event even if the same desktop song receives new lyrics.
    linkedLyricsUpdated.value = null;
    linkedLyricsUpdated.value = song.id;
  }

  final LyricsService _service = LyricsService();
  final _local = <String, Future<LyricsData?>>{};
  final _enhanced = <String, Future<LyricsData?>>{};
  static const maxEntries = 24;

  String _key(Song song) => '${song.id}|${song.filePath ?? ''}';

  void warm(Song song) {
    final key = _key(song);
    final local = _local.putIfAbsent(
      key, () => _service.loadLyricsForSong(song, fetchOnline: false)
          .catchError((Object _) => null),
    );
    _enhanced.putIfAbsent(key, () async {
      final own = await local;
      // Local lyrics should already be visible when remote providers run.
      bool enabled;
      try {
        enabled = (await AppPreferencesService().getPreferences()).lyricsAutoFetch;
      } catch (_) {
        enabled = false;
      }
      if (!enabled) return own;
      final fetched = await _service.loadLyricsForSong(
        song, fetchOnline: true,
      ).catchError((Object _) => null);
      return lyricQualityRank(fetched) > lyricQualityRank(own)
          ? fetched : own ?? fetched;
    });
    while (_local.length > maxEntries) {
      final stale = _local.keys.first;
      _local.remove(stale);
      _enhanced.remove(stale);
    }
  }

  Future<LyricsData?> local(Song song) {
    warm(song);
    return _local[_key(song)]!;
  }

  Future<LyricsData?> enhanced(Song song) {
    warm(song);
    return _enhanced[_key(song)]!;
  }

  void invalidate(Song song) {
    final key = _key(song);
    _local.remove(key);
    _enhanced.remove(key);
  }

  void clear() {
    _local.clear();
    _enhanced.clear();
  }
}

int lyricQualityRank(LyricsData? data) => data == null
    ? 0
    : data.lines.any((line) => line.words?.isNotEmpty == true)
        ? 3
        : data.isSynchronized ? 2 : 1;
