import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

typedef NotificationArtworkFetcher = Future<String?> Function(String url);
typedef NotificationSourceArtworkFetcher = Future<String?> Function(
  String audioSourcePath,
  String artwork,
);

/// Converts remote album covers into files Android's MediaSession can decode.
///
/// The Flutter player accepts HTTPS artwork URLs, but the native notification
/// currently accepts a local bitmap path. Never await artwork before starting
/// playback or publishing the initial media notification.
class NotificationArtworkResolver {
  NotificationArtworkResolver({
    NotificationArtworkFetcher? fetcher,
    NotificationSourceArtworkFetcher? sourceFetcher,
  }) : _fetcher = fetcher ?? _cacheRemoteImage,
       _sourceFetcher = sourceFetcher;

  final NotificationArtworkFetcher _fetcher;
  final NotificationSourceArtworkFetcher? _sourceFetcher;
  int _generation = 0;
  String? _identity;
  String? _resolvedPath;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// Returns an immediately usable local path, or null while a remote cover
  /// is being cached. Only the latest track can publish an async completion.
  String? pathFor({
    required String identity,
    required String? artwork,
    String? audioSourcePath,
    required void Function(String path) onResolved,
  }) {
    final source = artwork?.trim();
    final key =
        identity +
        '\u0000' +
        (source ?? '') +
        '\u0000' +
        (audioSourcePath ?? '');
    if (key == _identity) return _resolvedPath;

    _retryTimer?.cancel();
    _retryAttempt = 0;
    final generation = ++_generation;
    _identity = key;
    _resolvedPath = null;

    if (source == null || source.isEmpty) return null;
    final uri = Uri.tryParse(source);
    if (uri == null || !uri.hasScheme) {
      // Filesystem paths are already directly readable by Android.
      return _resolvedPath = source;
    }
    if (_sourceFetcher != null &&
        audioSourcePath != null &&
        {
          'lokal-cover',
          'subsonic-cover',
          'jellyfin-cover',
          'webdav-cover',
          'smb-cover',
          'upnp-cover',
          'tidal-cover',
        }.contains(uri.scheme)) {
      unawaited(
        _resolve(
          () => _sourceFetcher(audioSourcePath, source),
          generation,
          onResolved,
        ),
      );
      return null;
    }
    if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      // Do not hand arbitrary provider schemes to BitmapFactory.decodeFile.
      return null;
    }

    unawaited(_resolve(() => _fetcher(source), generation, onResolved));
    return null;
  }

  Future<void> _resolve(
    Future<String?> Function() fetch,
    int generation,
    void Function(String path) onResolved,
  ) async {
    try {
      final path = await fetch();
      if (generation != _generation) return;
      if (path != null && path.isNotEmpty) {
        _resolvedPath = path;
        onResolved(path);
        return;
      }
    } catch (_) {
      // Missing artwork must never prevent audio or the media notification.
    }
    // Covers can arrive after playback starts or after a brief LAN outage.
    // Retry twice without waiting on the playback/metadata publication path.
    if (generation == _generation && _retryAttempt < 2) {
      _retryTimer = Timer(Duration(seconds: 5 * ++_retryAttempt), () {
        unawaited(_resolve(fetch, generation, onResolved));
      });
    }
  }

  /// Invalidates late completions on notification dismissal/owner handoff.
  void invalidate() {
    _retryTimer?.cancel();
    ++_generation;
    _identity = null;
    _resolvedPath = null;
  }

  static Future<String?> _cacheRemoteImage(String url) async {
    // Reuse the same disk cache as other Flutter cover-art consumers.
    final image = await DefaultCacheManager()
        .getSingleFile(url)
        .timeout(const Duration(seconds: 15));
    return await image.exists() ? image.path : null;
  }
}
