import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/discovery/recommendation_match.dart';
import 'apple_music_metadata_service.dart';
import 'apple_music_models.dart';
import 'apple_artist_logo_cache.dart';

/// Apple's editorial artist-page media. These are not generated fonts or
/// local animations; many artists have no logo or motion artwork.
@immutable
class AppleArtistVisuals {
  const AppleArtistVisuals({
    required this.heroUrl,
    this.logoUrl,
    this.logoAspect = 1,
    this.motionUrl,
    this.logoLocalPath,
  });

  final String heroUrl;
  final String? logoUrl;
  final double logoAspect;
  final String? motionUrl;
  final String? logoLocalPath;

  AppleArtistVisuals withLogo(String? path) => AppleArtistVisuals(
    heroUrl: heroUrl,
    logoUrl: logoUrl,
    logoAspect: logoAspect,
    motionUrl: motionUrl,
    logoLocalPath: path,
  );
}

/// Parses the embedded artist header without depending on Apple's page layout.
/// Apple does not publish this JSON as a supported API, so absence and schema
/// changes must result in a normal static artist page, never an exception.
@visibleForTesting
AppleArtistVisuals? parseAppleArtistVisuals(String html) {
  final script = RegExp(
    r'<script[^>]*id="serialized-server-data"[^>]*>(.*?)</script>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(html);
  if (script == null) return null;

  Object? data;
  try {
    data = jsonDecode(script.group(1)!);
  } catch (_) {
    return null;
  }

  Map<String, dynamic>? asMap(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  Map<String, dynamic>? findHeader(Object? node, int depth) {
    if (depth > 32) return null;
    if (node is Map<String, dynamic>) {
      if (node.containsKey('artistLogo') &&
          (node.containsKey('artwork') ||
              node.containsKey('colorBackdropArtwork'))) {
        return node;
      }
      for (final value in node.values) {
        final found = findHeader(value, depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = findHeader(value, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  final header = findHeader(data, 0);
  if (header == null) return null;

  Map<String, dynamic>? dictionary(Object? value) =>
      asMap(asMap(value)?['dictionary']);

  String? safeUrl(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return value;
  }

  String? artwork(Map<String, dynamic>? asset, int width, String format) {
    if (asset == null) return null;
    final template = asset['url'];
    final sourceWidth = (asset['width'] as num?)?.toInt() ?? 0;
    final sourceHeight = (asset['height'] as num?)?.toInt() ?? 0;
    if (template is! String ||
        !template.contains('{w}') ||
        sourceWidth <= 0 ||
        sourceHeight <= 0) {
      return null;
    }
    final height = (width * sourceHeight / sourceWidth).round().clamp(1, 4000);
    return safeUrl(template
        .replaceAll('{w}', '$width')
        .replaceAll('{h}', '$height')
        .replaceAll('{c}', 'bb')
        .replaceAll('{f}', format));
  }

  final hero = dictionary(
    header['artwork'] ?? header['colorBackdropArtwork'],
  );
  final heroUrl = artwork(hero, 1200, 'jpg');
  if (heroUrl == null) return null;

  final logo = dictionary(header['artistLogo']);
  final logoUrl = artwork(logo, 1000, 'png');
  final logoWidth = (logo?['width'] as num?)?.toDouble() ?? 0;
  final logoHeight = (logo?['height'] as num?)?.toDouble() ?? 0;

  final videoArt = dictionary(header['videoArtwork']);
  final square = asMap(videoArt?['motionArtistSquare1x1']);
  final motionUrl = safeUrl(square?['video']);
  return AppleArtistVisuals(
    heroUrl: heroUrl,
    logoUrl: logoUrl,
    logoAspect: logoWidth > 0 && logoHeight > 0
        ? (logoWidth / logoHeight).clamp(0.4, 6).toDouble()
        : 1,
    motionUrl: motionUrl,
  );
}

/// Enriches artist headers with Apple's editorial media. An identical artist
/// name does not prove identity; require at least one shared song or release
/// title before accepting a candidate. All misses fall back to Lokal artwork.
class AppleArtistVisualsService {
  AppleArtistVisualsService({
    AppleMusicMetadataService? metadata,
    http.Client? client,
  }) : _metadata = metadata ?? AppleMusicMetadataService.instance,
       _client = client ?? http.Client();

  static final instance = AppleArtistVisualsService();
  final AppleMusicMetadataService _metadata;
  final http.Client _client;
  final _cache = <String, (DateTime, AppleArtistVisuals?)>{};
  final _pending = <String, Future<AppleArtistVisuals?>>{};

  Future<AppleArtistVisuals?> lookup({
    required String artistName,
    required Iterable<String> knownTitles,
  }) async {
    final artistKey = recommendationKey(artistName);
    final expected = knownTitles
        .map(recommendationKey)
        .where((title) => title.isNotEmpty)
        .toSet();
    if (artistKey.isEmpty || expected.isEmpty) return null;

    // The evidence is part of the key: two artists with the same displayed
    // name but different local catalogues must not share an unverified hit.
    final evidence = expected.toList()..sort();
    final key = '$artistKey|${evidence.join('|')}';
    final cached = _cache[key];
    if (cached != null && cached.$1.isAfter(DateTime.now())) {
      return cached.$2;
    }
    if (_pending[key] case final work?) return work;
    final future = _lookup(artistName, artistKey, expected);
    _pending[key] = future;
    try {
      final result = await future;
      _cache[key] = (
        DateTime.now().add(
          result == null ? const Duration(minutes: 20) : const Duration(hours: 6),
        ),
        result,
      );
      while (_cache.length > 48) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } catch (_) {
      // Network errors are not negative-cache entries.
      return null;
    } finally {
      _pending.remove(key);
    }
  }

  Future<AppleArtistVisuals?> _lookup(
    String artistName,
    String artistKey,
    Set<String> expected,
  ) async {
    final artist = await _metadata.resolveArtist(artistName);
    if (artist == null ||
        artist.artistId.isEmpty ||
        recommendationKey(artist.name) != artistKey) {
      return null;
    }

    final topSongs = await _metadata.getTopSongs(artist.artistId, limit: 25);
    var verified = topSongs.any((song) =>
        expected.contains(recommendationKey(song.trackName)) ||
        expected.contains(recommendationKey(song.collectionName ?? '')));
    if (!verified) {
      final releases = await _metadata.getArtistReleases(artistName);
      verified = releases.any((album) =>
          expected.contains(recommendationKey(album.name)));
    }
    if (!verified) return null;

    final url = Uri.tryParse(artist.url ?? '');
    final page = url != null &&
            url.scheme == 'https' &&
            url.host == 'music.apple.com'
        ? url
        : Uri.parse(AppleMusicMetadataService.artistPageUrl(
            artist.artistId,
            _metadata.deviceStorefront,
          ));
    return _fetchEditorial(artistName, page);
  }

  /// Reuse the already resolved artist from the manual Refresh Artist Info
  /// job instead of resolving the same name a second time. A matching artist
  /// name is the minimum requirement for followed-only Spotify artists.
  /// Where local track titles exist the normal page lookup also cross-checks
  /// recordings; we do not apply an unknown album cover as a logo.
  Future<bool> refreshFromArtistData(
    String artistName,
    AppleMusicArtistData data,
  ) async {
    final expected = recommendationKey(artistName);
    if (expected.isEmpty || recommendationKey(data.artist.name) != expected ||
        data.artist.artistId.isEmpty) return false;
    final source = Uri.tryParse(data.artist.url ?? '');
    final page = source != null &&
            source.scheme == 'https' &&
            source.host == 'music.apple.com'
        ? source
        : Uri.parse(AppleMusicMetadataService.artistPageUrl(
            data.artist.artistId, _metadata.deviceStorefront));
    final art = await _fetchEditorial(artistName, page, forceLogo: true);
    if (art == null) return false;
    final current = AppleArtistLogoCache.instance.cachedFor(artistName);
    return current != null;
  }

  Future<AppleArtistVisuals?> _fetchEditorial(
    String artistName,
    Uri page, {
    bool forceLogo = false,
  }) async {
    final response = await _client
        .get(page, headers: const {
          'User-Agent': 'Mozilla/5.0 (compatible; Lokal/artist-art)',
        })
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    // Decode the often-large hydration payload away from the UI isolate.
    final art = await compute(parseAppleArtistVisuals, response.body);
    if (art == null || art.logoUrl == null) return art;
    final cached = await AppleArtistLogoCache.instance.save(
      artistName: artistName,
      logoUrl: art.logoUrl!,
      aspect: art.logoAspect,
      force: forceLogo,
    );
    return art.withLogo(cached?.path);
  }
}
