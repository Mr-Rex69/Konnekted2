import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selected stations browser filters. These are persistent preferences
/// rather than temporary widget state, and are restored before the first
/// network browse to avoid querying the wrong country or genre on launch.
@immutable
class RadioBrowseSelection {
  const RadioBrowseSelection({
    this.favoritesOnly = false,
    this.losslessOnly = false,
    this.country = '',
    this.genre = '',
  });

  static const storageKey = 'lokal.stations.browse_selection.v1';

  final bool favoritesOnly;
  final bool losslessOnly;
  final String country;
  final String genre;

  static Future<RadioBrowseSelection> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return const RadioBrowseSelection();
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return const RadioBrowseSelection();
      return RadioBrowseSelection(
        favoritesOnly: parsed['favoritesOnly'] == true,
        losslessOnly: parsed['losslessOnly'] == true,
        country: parsed['country'] is String
            ? parsed['country'] as String : '',
        genre: parsed['genre'] is String
            ? parsed['genre'] as String : '',
      );
    } catch (_) {
      // A corrupt/older preference should not prevent station discovery.
      return const RadioBrowseSelection();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({
        'favoritesOnly': favoritesOnly,
        'losslessOnly': losslessOnly,
        'country': country,
        'genre': genre,
      }),
    );
  }
}
