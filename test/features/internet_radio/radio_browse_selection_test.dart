import 'package:flick/features/internet_radio/radio_browse_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('station tab, lossless, country and genre persist across sessions', () async {
    const selected = RadioBrowseSelection(
      favoritesOnly: true,
      losslessOnly: true,
      country: 'FR',
      genre: 'jazz',
    );
    await selected.save();
    final restarted = await RadioBrowseSelection.load();
    expect(restarted.favoritesOnly, true);
    expect(restarted.losslessOnly, true);
    expect(restarted.country, 'FR');
    expect(restarted.genre, 'jazz');
  });

  test('Explore, all countries and all genres restore independently', () async {
    await const RadioBrowseSelection(
      favoritesOnly: true,
      country: 'JP',
      genre: 'rock',
    ).save();
    await const RadioBrowseSelection(
      favoritesOnly: false,
      losslessOnly: true,
    ).save();
    final restored = await RadioBrowseSelection.load();
    expect(restored.favoritesOnly, false);
    expect(restored.losslessOnly, true);
    expect(restored.country, '');
    expect(restored.genre, '');
  });

  test('missing and damaged station preferences use safe defaults', () async {
    expect(await RadioBrowseSelection.load(), isA<RadioBrowseSelection>());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(RadioBrowseSelection.storageKey, '{broken');
    final invalid = await RadioBrowseSelection.load();
    expect(invalid.favoritesOnly, false);
    expect(invalid.losslessOnly, false);
    expect(invalid.country, '');
    expect(invalid.genre, '');
  });
}
