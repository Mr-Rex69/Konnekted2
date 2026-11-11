import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/models/progress_bar_style.dart';
import 'package:flick/providers/progress_bar_style_provider.dart';
import 'package:flick/services/progress_bar_style_preference_service.dart';

class DelayedStyleService extends ProgressBarStylePreferenceService {
  final loaded = Completer<ProgressBarStyle>();
  ProgressBarStyle? saved;
  @override
  Future<ProgressBarStyle> getStyle() => loaded.future;
  @override
  Future<void> setStyle(ProgressBarStyle style) async {
    saved = style;
  }
}

void main() {
  test(
    'default stays line and all existing/new choices survive restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = ProgressBarStylePreferenceService();
      expect(await service.getStyle(), ProgressBarStyle.line);
      for (final style in ProgressBarStyle.values) {
        final container = ProviderContainer();
        container.read(progressBarStyleProvider);
        await Future<void>.delayed(Duration.zero);
        await container.read(progressBarStyleProvider.notifier).setStyle(style);
        container.dispose();
        final restarted = ProviderContainer();
        restarted.read(progressBarStyleProvider);
        await Future<void>.delayed(Duration.zero);
        expect(restarted.read(progressBarStyleProvider), style);
        restarted.dispose();
      }
      expect(
        ProgressBarStyleX.fromStorageValue('unknown'),
        ProgressBarStyle.line,
      );
    },
  );
  test('a late preference load cannot overwrite a user selection, including default', () async {
    for (final choice in [ProgressBarStyle.wavy, ProgressBarStyle.line]) {
      final service = DelayedStyleService();
      final container = ProviderContainer(
        overrides: [
          progressBarStylePreferenceServiceProvider.overrideWithValue(service),
        ],
      );
      container.read(progressBarStyleProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(progressBarStyleProvider.notifier).setStyle(choice);
      service.loaded.complete(ProgressBarStyle.waveform);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(progressBarStyleProvider), choice);
      expect(service.saved, choice);
      container.dispose();
    }
  });
}
