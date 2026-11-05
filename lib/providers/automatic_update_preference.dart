import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manual update checks remain available regardless of this preference.
class AutomaticUpdatePreference extends AsyncNotifier<bool> {
  static const key = 'lokal.automatic_update_checks';
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? true;

  Future<void> select(bool enabled) async {
    state = AsyncData(enabled);
    await (await SharedPreferences.getInstance()).setBool(key, enabled);
  }
}

final automaticUpdatePreferenceProvider =
    AsyncNotifierProvider<AutomaticUpdatePreference, bool>(
      AutomaticUpdatePreference.new,
    );
