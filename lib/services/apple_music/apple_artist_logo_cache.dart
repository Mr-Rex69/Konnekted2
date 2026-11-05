import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/discovery/recommendation_match.dart';

/// An Apple-provided transparent PNG logo kept in app-support storage, not the
/// expendable HTTP thumbnail cache. This is only a display asset, never a font.
@immutable
class CachedArtistLogo {
  const CachedArtistLogo({required this.path, required this.aspect});
  final String path;
  final double aspect;
}

/// Artist logos must survive process death and force-closes. Load the tiny
/// index before runApp so already-visited artists render their logo on the
/// first frame rather than flashing the ordinary artist name.
///
/// Files are written before their index entry; interrupted writes leave the
/// old logo available. Unknown/missing logos never block artist navigation.
class AppleArtistLogoCache {
  AppleArtistLogoCache({
    Future<Directory> Function()? directory,
    Future<SharedPreferences> Function()? preferences,
    http.Client? client,
  })  : _directory = directory ?? getApplicationSupportDirectory,
        _preferences = preferences ?? SharedPreferences.getInstance,
        _client = client ?? http.Client();

  static final instance = AppleArtistLogoCache();
  static const storageKey = 'lokal.apple.artist.logos.v1';
  final Future<Directory> Function() _directory;
  final Future<SharedPreferences> Function() _preferences;
  final http.Client _client;
  final _logos = <String, CachedArtistLogo>{};
  final _pending = <String, Future<CachedArtistLogo?>>{};
  Future<void>? _restoring;
  Future<void> _writeTail = Future<void>.value();

  CachedArtistLogo? cachedFor(String artistName) =>
      _logos[recommendationKey(artistName)];

  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    SharedPreferences prefs;
    try {
      prefs = await _preferences();
    } catch (_) {
      // A platform preference failure must not prevent app startup.
      return;
    }
    final value = prefs.getString(storageKey);
    if (value == null) return;
    try {
      final data = jsonDecode(value);
      if (data is! Map) return;
      for (final item in data.entries) {
        if (item.key is! String || item.value is! Map) continue;
        final row = item.value as Map;
        final path = row['path'];
        final ratio = row['aspect'];
        if (path is! String || path.isEmpty || ratio is! num) continue;
        if (ratio <= 0 || ratio > 6) continue;
        _logos[item.key as String] = CachedArtistLogo(
          path: path,
          aspect: ratio.toDouble(),
        );
      }
    } catch (_) {
      // Invalid/stale indexes never interfere with opening artist pages.
    }
  }

  Future<CachedArtistLogo?> save({
    required String artistName,
    required String logoUrl,
    required double aspect,
    bool force = false,
  }) async {
    await restore();
    final key = recommendationKey(artistName);
    final uri = Uri.tryParse(logoUrl);
    // Logo URLs must come from Apple's image CDN, not arbitrary web hosts.
    if (key.isEmpty || uri == null || uri.scheme != 'https' ||
        !(uri.host == 'mzstatic.com' || uri.host.endsWith('.mzstatic.com'))) {
      return cachedFor(artistName);
    }
    final saved = _logos[key];
    if (!force && saved != null && await File(saved.path).exists()) return saved;
    if (_pending[key] case final existing?) return existing;
    final future = _download(key, uri, aspect);
    _pending[key] = future;
    try {
      return await future;
    } catch (_) {
      // Keep the previous disk-backed logo during network failures.
      return cachedFor(artistName);
    } finally {
      _pending.remove(key);
    }
  }

  Future<CachedArtistLogo?> _download(
    String key,
    Uri uri,
    double aspect,
  ) async {
    final response = await _client.get(uri).timeout(const Duration(seconds: 12));
    final bytes = response.bodyBytes;
    if (response.statusCode != 200 ||
        bytes.length < 8 ||
        bytes.length > 8 * 1024 * 1024 ||
        !(bytes[0] == 137 && bytes[1] == 80 &&
          bytes[2] == 78 && bytes[3] == 71 &&
          bytes[4] == 13 && bytes[5] == 10 &&
          bytes[6] == 26 && bytes[7] == 10)) {
      return cachedFor(key);
    }
    final folder = Directory('${(await _directory()).path}/artist_logos');
    await folder.create(recursive: true);
    final digest = sha256.convert(utf8.encode(key)).toString();
    // New revision paths bust Flutter's FileImage cache when a force refresh
    // updates the same artist logo. The old file stays valid while loading.
    final file = File('${folder.path}/$digest-${sha256.convert(bytes)}.png');
    if (!await file.exists()) {
      final temporary = File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
    final logo = CachedArtistLogo(path: file.path, aspect: aspect.clamp(.4, 6).toDouble());
    _logos[key] = logo;
    _writeTail = _writeTail.catchError((Object _) {}).then((_) async {
      final prefs = await _preferences();
      await prefs.setString(storageKey, jsonEncode({
        for (final entry in _logos.entries)
          entry.key: {'path': entry.value.path, 'aspect': entry.value.aspect},
      }));
    });
    await _writeTail;
    return logo;
  }
}
