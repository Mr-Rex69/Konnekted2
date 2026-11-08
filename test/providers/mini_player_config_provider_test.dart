import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/models/mini_player_config.dart';
import 'package:flick/providers/mini_player_config_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an edit during startup preserves other saved fields and survives reload',
    () async {
      final saved = MiniPlayerConfig.defaultConfig.copyWith(
        height: 80,
        showArtist: false,
        shadow: MiniPlayerShadow.strong,
        showNext: true,
        titleMode: MiniPlayerTitleMode.scroll,
      );
      SharedPreferences.setMockInitialValues({
        MiniPlayerConfigNotifier.preferencesKey: jsonEncode(saved.toJson()),
      });
      final container = ProviderContainer();
      final notifier = container.read(miniPlayerConfigProvider.notifier);
      await notifier.update(
        (c) => c.copyWith(
          widthMode: MiniPlayerWidthMode.custom,
          widthFraction: 0.75,
        ),
      );
      final expected = saved.copyWith(
        widthMode: MiniPlayerWidthMode.custom,
        widthFraction: 0.75,
      );
      expect(
        container.read(miniPlayerConfigProvider).toJson(),
        expected.toJson(),
      );
      container.dispose();

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      reloaded.read(miniPlayerConfigProvider);
      await pumpEventQueue();
      expect(
        reloaded.read(miniPlayerConfigProvider).toJson(),
        expected.toJson(),
      );
    },
  );

  test(
    'rapid edits and reset persist the last state without touching navigation',
    () async {
      SharedPreferences.setMockInitialValues({
        'nav_bar_buttons': 'songs,favorites,settings',
        'nav_bar_size': 1.3,
        'bottom_bar_auto_collapse_enabled': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(miniPlayerConfigProvider.notifier);
      await Future.wait([
        notifier.update((c) => c.copyWith(height: 88)),
        notifier.update((c) => c.copyWith(showArtwork: false)),
        notifier.reset(),
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(MiniPlayerConfigNotifier.preferencesKey)!),
        MiniPlayerConfig.defaultConfig.toJson(),
      );
      expect(prefs.getString('nav_bar_buttons'), 'songs,favorites,settings');
      expect(prefs.getDouble('nav_bar_size'), 1.3);
      expect(prefs.getBool('bottom_bar_auto_collapse_enabled'), isTrue);
    },
  );

  for (final invalid in ['not json', '[]', 12]) {
    test('invalid stored value $invalid falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        MiniPlayerConfigNotifier.preferencesKey: invalid,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(miniPlayerConfigProvider);
      await pumpEventQueue();
      expect(
        container.read(miniPlayerConfigProvider).toJson(),
        MiniPlayerConfig.defaultConfig.toJson(),
      );
    });
  }

  test('out-of-range and unknown values are safe; valid fields still load', () {
    final config = MiniPlayerConfig.fromJson({
      'height': 1000,
      'widthFraction': -1,
      'cornerRadius': -10,
      'navigationGap': double.nan,
      'textScale': double.infinity,
      'backgroundOpacity': 'transparent',
      'titleMode': 'unknown',
      'shadow': 'unknown',
      'showBorder': 0,
      'showPrevious': true,
    });
    expect(config.height, 88);
    expect(config.widthFraction, 0.7);
    expect(config.cornerRadius, 0);
    expect(config.navigationGap, 8);
    expect(config.textScale, 1);
    expect(config.backgroundOpacity, 0.94);
    expect(config.titleMode, MiniPlayerConfig.defaultConfig.titleMode);
    expect(config.shadow, MiniPlayerShadow.subtle);
    expect(config.showBorder, isTrue);
    expect(config.showPrevious, isTrue);
  });
}
