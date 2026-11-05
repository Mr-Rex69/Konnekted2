import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/providers/automatic_update_preference.dart';

void main() {
  test('automatic release checks default on and persist explicit opt-out', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    expect(await first.read(automaticUpdatePreferenceProvider.future), isTrue);
    await first.read(automaticUpdatePreferenceProvider.notifier).select(false);
    expect(first.read(automaticUpdatePreferenceProvider).value, isFalse);
    first.dispose();

    final second = ProviderContainer();
    expect(await second.read(automaticUpdatePreferenceProvider.future), isFalse);
    await second.read(automaticUpdatePreferenceProvider.notifier).select(true);
    expect(second.read(automaticUpdatePreferenceProvider).value, isTrue);
    second.dispose();
  });
}
