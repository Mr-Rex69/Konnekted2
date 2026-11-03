import 'package:flutter/foundation.dart';

/// Internet radio, as desktop has it: a station catalogue, a JSON file at a
/// link (Settings › Online sources). Only the parsed stations are kept.
///
/// The station list everyone starts with (Lokal's own radios.json), used
/// until another link is set.
const defaultRadioCatalogUrl =
    'https://raw.githubusercontent.com/sipbuu/lokal/refs/heads/main/radios.json';

@immutable
class RadioStation {
  const RadioStation({
    required this.id,
    required this.title,
    required this.url,
    this.genre,
    this.description,
    this.icon,
    this.codec = '',
    this.bitrate = 0,
    this.lossless = false,
    this.country = '',
    this.countryCode = '',
  });

  /// The stream link: stable across catalogue updates, so favourites use it.
  final String id;
  final String title;
  final String url;
  final String? genre;
  final String? description;
  final String? icon;
  final String codec;
  final int bitrate;
  final bool lossless;
  final String country;
  final String countryCode;

  Map<String, Object?> toJson() => {
    'title': title,
    'url': url,
    if (genre != null) 'genre': genre,
    if (description != null) 'description': description,
    if (icon != null) 'icon': icon,
    'id': id,
    'codec': codec,
    'bitrate': bitrate,
    'lossless': lossless,
    'country': country,
    'countrycode': countryCode,
  };

  /// Each genre of "House, Deep house / Lounge", trimmed.
  List<String> get genres => [
    for (final part in (genre ?? '').split(RegExp(r'\s*[,/;|]\s*')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

@immutable
class RadioCatalog {
  const RadioCatalog({required this.title, required this.stations});

  final String title;
  final List<RadioStation> stations;

  /// Every genre, in the catalogue's order, once each (case-insensitive).
  List<String> get genres {
    final seen = <String>{};
    return [
      for (final station in stations)
        for (final genre in station.genres)
          if (seen.add(genre.toLowerCase())) genre,
    ];
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'title': title,
    'stations': [for (final s in stations) s.toJson()],
  };
}

class RadioCatalogException implements Exception {
  const RadioCatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Bounds operations that feed a loading indicator, so stalled storage or
/// network calls always become a visible error instead of spinning forever.
Future<T> radioWithTimeout<T>(
  Future<T> operation, {
  required Duration timeout,
  required String timeoutMessage,
}) => operation.timeout(
  timeout,
  onTimeout: () => throw RadioCatalogException(timeoutMessage),
);

bool _isHttpUrl(Object? value) {
  if (value is! String) return false;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String? _text(Object? value, {int max = 500}) {
  if (value is! String) return null;
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  return text.length > max ? text.substring(0, max) : text;
}

/// The stations in a decoded catalogue. Desktop's format: `stations[]`, each
/// with a `title` and a stream `url`; `genre`, `description` and `icon` are
/// optional. Unlike desktop, a broken station is skipped rather than failing
/// the whole list; a list without one usable station is an error.
RadioCatalog parseRadioCatalog(Object? data) {
  if (data is! Map) {
    throw const RadioCatalogException('The station list isn’t a JSON object.');
  }
  final raw = data['stations'];
  if (raw is! List) {
    throw const RadioCatalogException('The station list has no stations.');
  }
  final stations = <RadioStation>[];
  final seen = <String>{};
  for (final item in raw.take(5000)) {
    if (item is! Map) continue;
    final title = _text(item['title'], max: 200);
    final url = item['url'];
    if (title == null || !_isHttpUrl(url)) continue;
    final stream = (url as String).trim();
    if (!seen.add(stream)) continue;
    final icon = item['icon'];
    stations.add(
      RadioStation(
        id: stream,
        title: title,
        url: stream,
        genre: _text(item['genre'], max: 200),
        description: _text(item['description']),
        icon: _isHttpUrl(icon) ? (icon as String).trim() : null,
      ),
    );
  }
  if (stations.isEmpty) {
    throw const RadioCatalogException(
      'The station list has no station with a title and a stream link.',
    );
  }
  return RadioCatalog(
    title: _text(data['title'], max: 200) ?? '',
    stations: List.unmodifiable(stations),
  );
}

/// Stations matching [query] (title, genre or description) and [genre].
List<RadioStation> filterStations(
  List<RadioStation> stations, {
  String query = '',
  String? genre,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final wantedGenre = genre?.toLowerCase();
  return [
    for (final station in stations)
      if ((wantedGenre == null ||
              station.genres.any((g) => g.toLowerCase() == wantedGenre)) &&
          words.every(
            (word) => [
              station.title,
              station.genre ?? '',
              station.description ?? '',
            ].any((field) => field.toLowerCase().contains(word)),
          ))
        station,
  ];
}
