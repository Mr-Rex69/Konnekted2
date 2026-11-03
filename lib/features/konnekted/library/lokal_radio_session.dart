import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../services/online_radio_recommendations.dart';
import '../../../services/player_service.dart' show PlayerService;

/// Share Flow's YouTube Music / Last.fm recommendations and playback resolver.
typedef LokalRadioTrackLookup = Future<List<Song>> Function(
  Song seed, Iterable<Song> existing, int count);
typedef LokalRadioArtistLookup = Future<List<Song>> Function(
  String artist, Iterable<Song> existing, int count);

final lokalRadioTrackLookupProvider = Provider<LokalRadioTrackLookup>(
  (ref) => (seed, existing, count) =>
      const OnlineRadioRecommendations().recommend(
        seed, existing: existing, count: count));
final lokalRadioArtistLookupProvider = Provider<LokalRadioArtistLookup>(
  (ref) => (artist, existing, count) =>
      const OnlineRadioRecommendations().recommendArtist(
        artist, existing: existing, count: count));

/// Online recommendations take priority. Only use the local safety net if
/// no usable online recommendation was returned.
@visibleForTesting
List<Song> selectLokalRadioAdditions({
  required Iterable<Song> existing,
  required Iterable<Song> online,
  required Iterable<Song> localFallback,
  int limit = 12,
}) {
  if (limit <= 0) return const [];
  final seen = existing
      .map((song) => radioRecordingKey(song.artist, song.title))
      .toSet();
  final selected = <Song>[];

  void add(Iterable<Song> songs) {
    for (final song in songs) {
      if (selected.length >= limit) break;
      if (song.artist.trim().isEmpty || song.title.trim().isEmpty) continue;
      if (seen.add(radioRecordingKey(song.artist, song.title))) {
        selected.add(song);
      }
    }
  }

  add(online);
  if (selected.isEmpty) add(localFallback);
  return selected;
}

/// A radio keeps its own queue context after the menu and source page close.
final lokalRadioSessionProvider = Provider<LokalRadioSession>((ref) {
  final session = LokalRadioSession(ref);
  ref.listen(playerProvider, (_, next) => session.observe(next));
  ref.onDispose(session.dispose);
  return session;
});

class LokalRadioSession {
  LokalRadioSession(this.ref) : _service = ref.read(playerServiceProvider);

  static const int maxTracks = 50;
  static const int fetchSize = 12;
  static const int refillThreshold = 4;

  final Ref ref;
  final PlayerService _service;
  int _generation = 0;
  int? _activeGeneration;
  String? _artist;
  bool _artistLookupPending = false;
  bool _starting = false;
  bool _fetching = false;
  bool? _previousAutoplay;
  String? _lastAttempt;
  List<Song> _planned = [];
  Future<List<Song>> Function()? _loadLocalFallback;

  String _contextId(int generation) => 'konnekted:radio:$generation';

  bool _owns(PlayerState state, int generation) {
    final current = state.currentSong;
    return _activeGeneration == generation &&
        _service.playbackContext.sourceId == _contextId(generation) &&
        current != null &&
        _planned.any((song) =>
            radioRecordingKey(song.artist, song.title) ==
            radioRecordingKey(current.artist, current.title));
  }

  void _release() {
    final previous = _previousAutoplay;
    // Flow also owns the runtime autoplay flag; don't overwrite its choice.
    if (previous != null &&
        !_service.playbackContext.sourceId.startsWith('konnekted:flow:') &&
        !_service.autoplayOnQueueEndNotifier.value) {
      _service.setAutoplayOnQueueEnd(previous);
    }
    _previousAutoplay = null;
    _activeGeneration = null;
    _artist = null;
    _artistLookupPending = false;
    _lastAttempt = null;
    _starting = false;
    _fetching = false;
    _planned = [];
    _loadLocalFallback = null;
  }

  void dispose() => _release();

  /// Start the selected recording immediately; don't await a network lookup
  /// or scan the library before starting a song radio.
  Future<void> start(
    Song first, {
    String? artist,
    List<Song> initialOnline = const [],
    Future<List<Song>> Function()? localFallback,
  }) async {
    _release();
    final generation = ++_generation;
    _activeGeneration = generation;
    _planned = [first];
    _artist = artist;
    _artistLookupPending = artist != null && initialOnline.isEmpty;
    _loadLocalFallback = localFallback;
    _starting = true;
    try {
      _previousAutoplay = _service.autoplayOnQueueEndNotifier.value;
      _service.setAutoplayOnQueueEnd(false);
      await ref.read(playerProvider.notifier).setShuffleMode(ShuffleMode.off);
      if (!ref.mounted || _activeGeneration != generation) return;
      await ref.read(playerProvider.notifier).setLoopMode(LoopMode.off);
      if (!ref.mounted || _activeGeneration != generation) return;
      await ref.read(playerProvider.notifier).play(
        first,
        playlist: [first],
        context: PlaybackContext(
          source: PlaybackSource.unknown,
          sourceId: _contextId(generation),
          sourceName: '${artist ?? first.title} Radio',
        ),
      );
      if (!ref.mounted || _activeGeneration != generation) return;
      _service.setAutoplayOnQueueEnd(false);
      if (!_owns(ref.read(playerProvider), generation)) {
        throw StateError('Radio playback could not start.');
      }
      // Artist radio can find the first online batch before playback.
      for (final song in selectLokalRadioAdditions(
        existing: _planned,
        online: initialOnline,
        localFallback: const [],
        limit: maxTracks - _planned.length,
      )) {
        if (!_owns(ref.read(playerProvider), generation)) break;
        await _service.appendToPlaylistTail(song);
        _planned.add(song);
      }
    } catch (_) {
      if (_activeGeneration == generation) _release();
      rethrow;
    } finally {
      if (_activeGeneration == generation) {
        _starting = false;
        unawaited(_topUp());
      }
    }
  }

  void observe(PlayerState state) {
    final generation = _activeGeneration;
    if (generation == null || _starting || _fetching) return;
    if (state.currentSong == null) return; // Transient engine handoff.
    if (!_owns(state, generation)) {
      _release();
      return;
    }
    if (state.upNext.length <= refillThreshold) unawaited(_topUp());
  }

  Future<void> _topUp() async {
    final generation = _activeGeneration;
    if (generation == null || _starting || _fetching ||
        !ref.mounted || _planned.length >= maxTracks) return;
    final state = ref.read(playerProvider);
    if (!_owns(state, generation) ||
        state.upNext.length > refillThreshold) return;
    final current = state.currentSong!;
    final attempt = '${current.id}:${_planned.length}';
    if (attempt == _lastAttempt) return;
    _lastAttempt = attempt;
    _fetching = true;
    var added = 0;
    try {
      final remaining = (maxTracks - _planned.length).clamp(0, fetchSize);
      List<Song> online = const [];
      try {
        if (_artistLookupPending && _artist != null) {
          _artistLookupPending = false;
          online = await ref.read(lokalRadioArtistLookupProvider)(
            _artist!, _planned, remaining).timeout(const Duration(seconds: 25));
        } else {
          online = await ref.read(lokalRadioTrackLookupProvider)(
            current, _planned, remaining).timeout(const Duration(seconds: 25));
        }
      } catch (_) {
        // No network/auth/available source must never interrupt audio.
      }

      if (!ref.mounted || !_owns(ref.read(playerProvider), generation)) return;
      var additions = selectLokalRadioAdditions(
        existing: _planned,
        online: online,
        localFallback: const [],
        limit: remaining,
      );

      if (additions.isEmpty && _loadLocalFallback != null) {
        try {
          final local = await _loadLocalFallback!();
          if (!ref.mounted || !_owns(ref.read(playerProvider), generation)) return;
          additions = selectLokalRadioAdditions(
            existing: _planned,
            online: const [],
            localFallback: local,
            limit: remaining.clamp(0, 3),
          );
        } catch (_) {
          // The offline library can also be inaccessible.
        }
      }

      for (final song in additions) {
        if (!ref.mounted || !_owns(ref.read(playerProvider), generation)) break;
        await _service.appendToPlaylistTail(song);
        _planned.add(song);
        added++;
      }
    } catch (_) {
      // Don't break the current recording when a queue append fails.
    } finally {
      // An older lookup must never clear the in-flight flag of a newer radio.
      if (ref.mounted && _activeGeneration == generation) {
        _fetching = false;
        if (added > 0) unawaited(Future<void>.microtask(_topUp));
      }
    }
  }
}
