import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'radio_catalog.dart';

const _key = 'lokal_station_favorites_v1';

/// Favorites keep full station records so they remain visible without a
/// network response. Keys are Radio Browser UUIDs, not changeable stream URLs.
class StationFavoritesNotifier extends Notifier<Map<String, RadioStation>> {
  @override
  Map<String, RadioStation> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_key) ?? '{}');
      if (decoded is! Map) return;
      final records = <String, RadioStation>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final data = Map<String, dynamic>.from(entry.value as Map);
        final url = (data['url'] ?? '').toString();
        final title = (data['title'] ?? '').toString();
        if (title.isEmpty || !Uri.tryParse(url).toString().startsWith('http')) continue;
        final station = RadioStation(
          id: (data['id'] ?? entry.key).toString(),
          title: title,
          url: url,
          icon: data['icon']?.toString(),
          genre: data['genre']?.toString(),
          description: data['description']?.toString(),
          codec: (data['codec'] ?? '').toString(),
          bitrate: (data['bitrate'] as num?)?.toInt() ?? 0,
          lossless: data['lossless'] == true,
          country: (data['country'] ?? '').toString(),
          countryCode: (data['countrycode'] ?? '').toString(),
        );
        records[station.id] = station;
      }
      if (ref.mounted) state = records;
    } catch (_) {
      // Corrupted preferences must not prevent the Stations screen opening.
    }
  }

  /// Import legacy stream-URL favorites when a matching qualifying Radio
  /// Browser station is discovered. Low-quality favorites remain saved in
  /// their original preference key, but are not exposed as playable stations.
  Future<void> adoptLegacy(List<RadioStation> discovered) async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getStringList('lokal_radio_favorites')?.toSet() ?? <String>{};
    if (legacy.isEmpty) return;
    final next = Map<String, RadioStation>.of(state);
    var changed = false;
    for (final station in discovered) {
      if (legacy.contains(station.url) && !next.containsKey(station.id)) {
        next[station.id] = station;
        changed = true;
      }
    }
    if (!changed || !ref.mounted) return;
    state = next;
    await prefs.setString(_key, jsonEncode({
      for (final entry in next.entries) entry.key: entry.value.toJson(),
    }));
  }

  Future<void> toggle(RadioStation station) async {
    final next = Map<String, RadioStation>.of(state);
    if (next.containsKey(station.id)) {
      next.remove(station.id);
    } else {
      next[station.id] = station;
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      for (final entry in next.entries) entry.key: entry.value.toJson(),
    }));
  }
}

final stationFavoritesProvider =
    NotifierProvider<StationFavoritesNotifier, Map<String, RadioStation>>(
      StationFavoritesNotifier.new,
    );
