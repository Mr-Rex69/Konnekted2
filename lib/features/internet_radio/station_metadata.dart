import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'radio_catalog.dart';

class StationLiveMetadata {
  const StationLiveMetadata({required this.artist, required this.title, this.cover});
  final String artist;
  final String title;
  final String? cover;
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
  static const novaUrl = 'https://www.nova.fr/radios-data/www.nova.fr/all.json';
  static const _novaHosts = <String, String>{
    'radionova.ice.infomaniak.ch': 'radio-nova',
    'nova-vnt.ice.infomaniak.ch': 'nova-classics',
    'nova-ln.ice.infomaniak.ch': 'nova-lanuit',
    'nova-dance.ice.infomaniak.ch': 'nova-danse',
    'nova-odn.ice.infomaniak.ch': 'nova-hip-hop',
    'nova-reggae.ice.infomaniak.ch': 'nova-reggae',
    'nova-soul.ice.infomaniak.ch': 'nova-soul',
    'nova-nouvo.ice.infomaniak.ch': 'nouvo-nova',
    'novalaplage.ice.infomaniak.ch': 'nova-la-plage',
  };

  /// Match only official stream hosts, never names supplied by directory users.
  static String? novaCodeForStation(RadioStation station) {
    final url = Uri.tryParse(station.url);
    return url == null ? null : _novaHosts[url.host.toLowerCase()];
  }

  static StationLiveMetadata? parseNovaForTest(Object? data, String code) {
    final stations = data is List ? data :
        (data is Map && data['radios'] is List ? data['radios'] as List : const []);
    for (final item in stations) {
      if (item is! Map || item['radio'] is! Map) continue;
      if ((item['radio'] as Map)['code'] != code) continue;
      final current = item['currentTrack'];
      if (current is! Map) return null;
      final artist = (current['artist'] ?? '').toString().trim();
      final title = (current['title'] ?? '').toString().trim();
      if (title.isEmpty) return null;
      final image = (current['image'] ?? '').toString().trim();
      final coverUrl = Uri.tryParse(image);
      return StationLiveMetadata(
        artist: artist,
        title: title,
        cover: coverUrl != null &&
            (coverUrl.scheme == 'https' || coverUrl.scheme == 'http')
            ? image : null,
      );
    }
    return null;
  }

  static const _successTtl = Duration(seconds: 45);
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
          (response.contentLength ?? 0) > 512 * 1024) return null;
      final bytes = <int>[];
      await for (final chunk in response.stream
          .timeout(const Duration(seconds: 4))) {
        if (bytes.length + chunk.length > 512 * 1024) return null;
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  // Cover lookups are made only for visible rows with a known artist/title.
  // Exact artist and title matching prevents assigning another song's cover.
  static final _artwork = <String, Future<String?>>{};

  static String _normalize(String text) => text.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Future<String?> _artworkFor(StationLiveMetadata track) {
    if (track.artist.trim().isEmpty || track.title.trim().isEmpty) {
      return Future<String?>.value(null);
    }
    final key = _normalize(track.artist) + '|' + _normalize(track.title);
    final cached = _artwork[key];
    if (cached != null) return cached;
    final pending = _withSlot<String?>(() async {
      final url = Uri.https('itunes.apple.com', '/search', {
        'term': track.artist + ' ' + track.title,
        'media': 'music',
        'entity': 'song',
        'limit': '5',
      });
      final data = await _fetch(url);
      if (data is! Map || data['results'] is! List) return null;
      for (final result in data['results'] as List) {
        if (result is! Map) continue;
        final artist = _normalize((result['artistName'] ?? '').toString());
        final title = _normalize((result['trackName'] ?? '').toString());
        if (artist != _normalize(track.artist) ||
            title != _normalize(track.title)) continue;
        final image = (result['artworkUrl100'] ?? '').toString();
        final uri = Uri.tryParse(image);
        if (uri == null || uri.scheme != 'https') continue;
        return image.replaceFirst(RegExp(r'/\d+x\d+bb\.'),
          '/600x600bb.');
      }
      return null;
    });
    _artwork[key] = pending;
    if (_artwork.length > 200) _artwork.remove(_artwork.keys.first);
    return pending;
  }


  static Uri? _metadataEndpoint(RadioStation station, String path, [Map<String, String>? query]) {
    final original = _statusUri(station);
    if (original == null) return null;
    return original.replace(path: path, queryParameters: query);
  }

  static Uri? _shoutcastEndpoint(RadioStation station) {
    final stream = Uri.tryParse(station.url);
    if (stream == null) return null;
    final match = RegExp(r'^/stream/(\d+)/?
    final novaCode = novaCodeForStation(station);
    final uri = novaCode == null ? _statusUri(station) : Uri.parse(novaUrl);
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
    final data = await entry.pending;
    final info = novaCode == null
        ? _parse(data, station.url) : parseNovaForTest(data, novaCode);
    if (info == null || info.cover != null) return info;
    final artwork = await _artworkFor(info);
    return artwork == null ? info : StationLiveMetadata(
      artist: info.artist, title: info.title, cover: artwork,
    );
  }
}
).firstMatch(stream.path);
    final sid = stream.queryParameters['sid'] ?? match?.group(1) ?? '1';
    if (!RegExp(r'^[1-9]\d{0,3}
    final novaCode = novaCodeForStation(station);
    final uri = novaCode == null ? _statusUri(station) : Uri.parse(novaUrl);
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
    final data = await entry.pending;
    final info = novaCode == null
        ? _parse(data, station.url) : parseNovaForTest(data, novaCode);
    if (info == null || info.cover != null) return info;
    final artwork = await _artworkFor(info);
    return artwork == null ? info : StationLiveMetadata(
      artist: info.artist, title: info.title, cover: artwork,
    );
  }
}
).hasMatch(sid)) return null;
    return _metadataEndpoint(station, '/stats', {'sid': sid, 'json': '1'});
  }

  static StationLiveMetadata? _splitTitle(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty || text.length > 300 ||
        {'unknown', 'offline', 'n/a'}.contains(text.toLowerCase())) {
      return null;
    }
    final at = text.indexOf(' - ');
    return at < 1 ? StationLiveMetadata(artist: '', title: text) :
        StationLiveMetadata(
          artist: text.substring(0, at),
          title: text.substring(at + 3),
        );
  }

  static StationLiveMetadata? parseShoutcastForTest(Object? data) {
    if (data is! Map || !data.containsKey('songtitle') ||
        (data['streamstatus'] != null &&
         num.tryParse((data['streamstatus'] ?? '').toString()) == 0)) return null;
    return _splitTitle(data['songtitle']);
  }

  static bool _sameStreamUrl(String? a, String b) {
    if (a == null) return false;
    final left = Uri.tryParse(a), right = Uri.tryParse(b);
    if (left == null || right == null) return false;
    final pathA = left.path.replaceFirst(RegExp(r'/+
    final novaCode = novaCodeForStation(station);
    final uri = novaCode == null ? _statusUri(station) : Uri.parse(novaUrl);
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
    final data = await entry.pending;
    final info = novaCode == null
        ? _parse(data, station.url) : parseNovaForTest(data, novaCode);
    if (info == null || info.cover != null) return info;
    final artwork = await _artworkFor(info);
    return artwork == null ? info : StationLiveMetadata(
      artist: info.artist, title: info.title, cover: artwork,
    );
  }
}
), '');
    final pathB = right.path.replaceFirst(RegExp(r'/+
    final novaCode = novaCodeForStation(station);
    final uri = novaCode == null ? _statusUri(station) : Uri.parse(novaUrl);
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
    final data = await entry.pending;
    final info = novaCode == null
        ? _parse(data, station.url) : parseNovaForTest(data, novaCode);
    if (info == null || info.cover != null) return info;
    final artwork = await _artworkFor(info);
    return artwork == null ? info : StationLiveMetadata(
      artist: info.artist, title: info.title, cover: artwork,
    );
  }
}
), '');
    return left.scheme == right.scheme &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port && pathA == pathB;
  }

  static StationLiveMetadata? parseAzuraCastForTest(Object? data, String streamUrl) {
    final entries = data is List ? data : data is Map && data['now_playing'] is Map ? [data] : const [];
    for (final row in entries) {
      if (row is! Map || row['station'] is! Map) continue;
      final station = row['station'] as Map;
      final links = <String?>[station['listen_url']?.toString()];
      for (final field in ['mounts', 'remotes']) {
        final list = station[field];
        if (list is List) {
          for (final mount in list) {
            if (mount is Map) {
              links.add((mount['url'] ?? mount['listen_url'])?.toString());
            }
          }
        }
      }
      if (!links.any((link) => _sameStreamUrl(link, streamUrl))) continue;
      final playing = row['now_playing'];
      if (playing is! Map || playing['song'] is! Map) continue;
      final song = playing['song'] as Map;
      final fallback = _splitTitle(song['text']);
      final title = (song['title'] ?? fallback?.title ?? '').toString().trim();
      if (title.isEmpty) continue;
      final artist = (song['artist'] ?? fallback?.artist ?? '').toString().trim();
      final image = (song['art'] ?? '').toString().trim();
      final uri = Uri.tryParse(image);
      return StationLiveMetadata(
        artist: artist,
        title: title,
        cover: uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
            ? image : null,
      );
    }
    return null;
  }

  static Future<Object?> _cachedJson(Uri uri) {
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
    return entry.pending;
  }

  static Future<StationLiveMetadata?> lookup(RadioStation station) async {
    StationLiveMetadata? info;
    final novaCode = novaCodeForStation(station);
    if (novaCode != null) {
      info = parseNovaForTest(
        await _cachedJson(Uri.parse(novaUrl)), novaCode);
    } else {
      // Only status APIs are polled; the actual audio stream is opened solely
      // by the playback engine for the currently selected station.
      final icecast = _statusUri(station);
      if (icecast != null) {
        info = _parse(await _cachedJson(icecast), station.url);
      }
      if (info == null) {
        final azura = _metadataEndpoint(station, '/api/nowplaying');
        if (azura != null) {
          info = parseAzuraCastForTest(
            await _cachedJson(azura), station.url);
        }
      }
      if (info == null) {
        final shoutcast = _shoutcastEndpoint(station);
        if (shoutcast != null) {
          info = parseShoutcastForTest(await _cachedJson(shoutcast));
        }
      }
    }
    if (info == null || info.cover != null) return info;
    final artwork = await _artworkFor(info);
    return artwork == null ? info : StationLiveMetadata(
      artist: info.artist, title: info.title, cover: artwork,
    );
  }
}
