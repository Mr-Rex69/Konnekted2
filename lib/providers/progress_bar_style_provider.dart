import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/models/progress_bar_style.dart';
import 'package:flick/services/progress_bar_style_preference_service.dart';

final progressBarStylePreferenceServiceProvider =
    Provider<ProgressBarStylePreferenceService>((ref) {
      return ProgressBarStylePreferenceService();
    });

class ProgressBarStyleNotifier extends Notifier<ProgressBarStyle> {
  bool _initialized = false;
  bool _selected = false;

  @override
  ProgressBarStyle build() {
    if (!_initialized) {
      _initialized = true;
      Future<void>.microtask(_loadFromPreferences);
    }
    return ProgressBarStyle.line;
  }

  Future<void> _loadFromPreferences() async {
    final style = await ref
        .read(progressBarStylePreferenceServiceProvider)
        .getStyle();
    if (ref.mounted && !_selected && state != style) {
      state = style;
    }
  }

  Future<void> setStyle(ProgressBarStyle style) async {
    _selected = true;
    state = style;
    await ref.read(progressBarStylePreferenceServiceProvider).setStyle(style);
  }
}

final progressBarStyleProvider =
    NotifierProvider<ProgressBarStyleNotifier, ProgressBarStyle>(
      ProgressBarStyleNotifier.new,
    );
