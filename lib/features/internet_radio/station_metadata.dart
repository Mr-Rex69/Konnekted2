import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'radio_catalog.dart';

class StationLiveMetadata {
  const StationLiveMetadata({required this.artist, required this.title});
  final String artist;
  final String title;
  String get label => artist.isEmpty ? title : artist + ' — ' + title;
}

class _CachedStatus {
  _CachedStatus(this.pending, this.expires);
  final Future<Object?> pending;
  DateTime expires;
}

/// Read broadcaster-published Icecast JSON only for lazy-built station rows.
/// Per-origin dedupe, two concurrent requests and negative caching avoid any
/// need to open dozens of background audio streams.
class StationMetadataLookup {
  static final _cache = <String, _CachedStatus>{};
  static final _waiting = Queue<Completer<void>>();
  static int _active = 0;
  static const _successTtl = Duration(seconds: 60);
  static const _failureTtl = Duration(minutes: 5);

  static Future<T> _withSlot<T>(Future<T> Function() job) async {
    if (_active >= 2) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    }
    _active++;
    try {
      return await job();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }

  static Uri? _statusUri(RadioStation station) {
    if (!station.id.startsWith('rb:')) return null;
    final url = Uri.tryParse(station.url);
    if (url == null ||
        (url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty) return null;
    final host = url.host.toLowerCase();
    // Don't silently probe local or literal IP-based network services.
    if (host == 'localhost' || host.endsWith('.local') ||
        host.endsWith('.internal') || host.contains(':') ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) return null;
    return url.replace(path: '/status-json.xsl', query: '', fragment: '');
  }

  static StationLiveMetadata? _parse(Object? json, String streamUrl) {
    if (json is! Map || json['icestats'] is! Map) return null;
    final sources = (json['icestats'] as Map)['source'];
    final rows = sources is List ? sources : [sources];
    final path = Uri.tryParse(streamUrl)?.path;
    Map? matched;
    for (final source in rows) {
      if (source is! Map) continue;
      if (Uri.tryParse((source['listenurl'] ?? '').toString())?.path == path) {
        matched = source;
        break;
      }
    }
    if (matched == null && rows.length == 1 && rows.first is Map) {
      matched = rows.first as Map;
    }
    if (matched == null) return null;
    final text = (matched['title'] ?? matched['song'] ?? '')
        .toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'unknown' ||
        text.toLowerCase() == 'offline') return null;
    final at = text.indexOf(' - ');
    return at <= 0 ? StationLiveMetadata(artist: '', title: text) :
        StationLiveMetadata(
          artist: text.substring(0, at),
          title: text.substring(at + 3),
        );
  }

  /// Pure parser exposed for focused regression tests (never fetches audio).
  static StationLiveMetadata? parseIcecastStatusForTest(
    Object? data, String streamUrl,
  ) => _parse(data, streamUrl);

  static Future<Object?> _fetch(Uri uri) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      final response = await client.send(request)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > 128 * 1024) return null;
      final bytes = <int>[];
      await for (final chunk in response.stream
          .timeout(const Duration(seconds: 4))) {
        if (bytes.length + chunk.length > 128 * 1024) return null;
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<StationLiveMetadata?> lookup(RadioStation station) async {
    final uri = _statusUri(station);
    if (uri == null) return null;
    final key = uri.toString();
    final now = DateTime.now();
    var entry = _cache[key];
    if (entry == null || now.isAfter(entry.expires)) {
      final pending = _withSlot(() => _fetch(uri));
      entry = _CachedStatus(pending, now.add(_successTtl));
      _cache[key] = entry;
      final captured = entry;
      pending.then((value) {
        captured.expires = DateTime.now()
            .add(value == null ? _failureTtl : _successTtl);
      });
      if (_cache.length > 150) _cache.remove(_cache.keys.first);
    }
    return _parse(await entry.pending, station.url);
  }
}
