import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'radio_catalog.dart';

const stationMinimumBitrate = 256;
const _mirrors = [
  'de1.api.radio-browser.info',
  'nl1.api.radio-browser.info',
  'at1.api.radio-browser.info',
];
const _lossless = {'FLAC', 'ALAC', 'WAV', 'PCM'};
const _lossy = {'MP3', 'AAC', 'AAC+', 'HE-AAC', 'OPUS', 'OGG', 'VORBIS'};

@immutable
class RadioBrowseResult {
  const RadioBrowseResult({
    required this.stations,
    required this.nextOffset,
    required this.hasMore,
  });
  final List<RadioStation> stations;
  final int nextOffset;
  final bool hasMore;
}

/// Directory metadata is an eligibility signal, not measured fidelity.
/// A reported 320 kbps stream may not deliver that actual bitrate.
bool qualifiesRadioBrowserStation(Map<String, dynamic> data) {
  if (data['lastcheckok'] == false ||
      data['lastcheckok'] == 0 ||
      data['lastcheckok'] == '0') {
    return false;
  }
  final codec = (data['codec'] ?? '').toString().trim().toUpperCase();
  final bitrate = num.tryParse((data['bitrate'] ?? '').toString())?.toInt() ?? 0;
  if (!_lossless.contains(codec) &&
      (!_lossy.contains(codec) || bitrate < stationMinimumBitrate)) {
    return false;
  }
  final uuid = (data['stationuuid'] ?? '').toString().trim();
  final name = (data['name'] ?? '').toString().trim();
  final link = (data['url_resolved'] ?? data['url'] ?? '').toString().trim();
  final uri = Uri.tryParse(link);
  return uuid.isNotEmpty &&
      name.isNotEmpty &&
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

RadioStation stationFromRadioBrowser(Map<String, dynamic> data) {
  final codec = (data['codec'] ?? '').toString().trim().toUpperCase();
  final tags = (data['tags'] ?? '').toString().split(',')
      .map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();
  final favicon = (data['favicon'] ?? '').toString().trim();
  final icon = Uri.tryParse(favicon);
  return RadioStation(
    id: 'rb:' + (data['stationuuid'] ?? '').toString(),
    title: (data['name'] ?? '').toString().trim(),
    url: (data['url_resolved'] ?? data['url']).toString().trim(),
    icon: (icon != null && (icon.scheme == 'https' || icon.scheme == 'http'))
        ? favicon : null,
    genre: tags.isEmpty ? null : tags.first,
    description: (data['language'] ?? '').toString().trim(),
    country: (data['country'] ?? '').toString().trim(),
    countryCode: (data['countrycode'] ?? '').toString().trim(),
    codec: codec,
    bitrate: num.tryParse((data['bitrate'] ?? 0).toString())?.toInt() ?? 0,
    lossless: _lossless.contains(codec),
  );
}

/// Small, paginated requests rather than downloading all worldwide stations.
/// Fixed, trusted mirrors prevent arbitrary user-supplied server endpoints.
class RadioBrowserClient {
  RadioBrowserClient({http.Client? client}) : _client = client ?? http.Client(),
    _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<dynamic>> _request({
    required String query,
    required String country,
    required String tag,
    required int offset,
    required int limit,
    required bool lossless,
  }) async {
    final params = <String, String>{
      'hidebroken': 'true',
      'bitrateMin': lossless ? '0' : '$stationMinimumBitrate',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '$limit',
      'offset': '$offset',
      if (lossless) 'codec': 'FLAC',
      if (query.trim().isNotEmpty) 'name': query.trim().length > 80
          ? query.trim().substring(0, 80) : query.trim(),
      if (country.isNotEmpty) 'countrycode': country,
      if (tag.isNotEmpty) 'tag': tag,
    };
    Object? lastError;
    for (final mirror in _mirrors) {
      try {
        final uri = Uri.https(mirror, '/json/stations/search', params);
        final response = await _client.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'Lokal-Stations/1.0',
        }).timeout(const Duration(seconds: 9));
        if (response.statusCode != 200) {
          throw RadioCatalogException(
            'Station directory returned HTTP ' + response.statusCode.toString(),
          );
        }
        final result = jsonDecode(response.body);
        if (result is! List) {
          throw const RadioCatalogException('Invalid station directory response');
        }
        return result;
      } catch (error) {
        lastError = error;
      }
    }
    throw RadioCatalogException('Could not reach Radio Browser: $lastError');
  }

  Future<RadioBrowseResult> browse({
    String query = '',
    String country = '',
    String tag = '',
    int offset = 0,
    int limit = 60,
  }) async {
    final count = limit.clamp(1, 80).toInt();
    final safeOffset = offset.clamp(0, 20000).toInt();
    final primary = await _request(
      query: query, country: country, tag: tag,
      offset: safeOffset, limit: count, lossless: false,
    );
    List<dynamic> flac = [];
    if (safeOffset == 0) {
      try {
        flac = await _request(
          query: query, country: country, tag: tag,
          offset: 0, limit: 25, lossless: true,
        );
      } catch (_) {
        // The main 256+ kbps list remains usable if lossless lookup fails.
      }
    }
    final seenIds = <String>{};
    final seenUrls = <String>{};
    final stations = <RadioStation>[];
    for (final row in [...flac, ...primary]) {
      if (row is! Map) continue;
      final data = Map<String, dynamic>.from(row);
      if (!qualifiesRadioBrowserStation(data)) continue;
      final station = stationFromRadioBrowser(data);
      if (!seenIds.add(station.id)) continue;
      if (!seenUrls.add(station.url.trim().toLowerCase())) continue;
      stations.add(station);
    }
    stations.sort((a, b) {
      final losslessOrder = (b.lossless ? 1 : 0) - (a.lossless ? 1 : 0);
      return losslessOrder != 0 ? losslessOrder :
          b.bitrate.compareTo(a.bitrate);
    });
    return RadioBrowseResult(
      stations: stations,
      nextOffset: safeOffset + primary.length,
      hasMore: primary.length == count,
    );
  }
}
