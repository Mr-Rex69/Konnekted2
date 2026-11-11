import 'dart:async';

import 'package:flick/features/konnekted/tablet_sidebar_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit sidebar choices are independent and restored on recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = TabletSidebarPreferences();
      await first.ready;
      expect(first.rightOpen.value, isNull);
      first.leftOpen.value = false;
      first.rightOpen.value = true;
      await first.flushed;
      first.dispose();
      final reopened = TabletSidebarPreferences();
      await reopened.ready;
      expect(reopened.leftOpen.value, false);
      expect(reopened.rightOpen.value, true);
      reopened.rightOpen.value = false;
      await reopened.flushed;
      reopened.dispose();
      final again = TabletSidebarPreferences();
      await again.ready;
      expect(again.leftOpen.value, false);
      expect(again.rightOpen.value, false);
      again.dispose();
    },
  );

  test(
    'late restoration cannot overwrite a sidebar changed during startup',
    () async {
      SharedPreferences.setMockInitialValues({
        TabletSidebarPreferences.leftKey: true,
        TabletSidebarPreferences.rightKey: false,
      });
      final saved = await SharedPreferences.getInstance();
      final delayed = Completer<SharedPreferences>();
      final state = TabletSidebarPreferences(preferences: delayed.future);
      state.leftOpen.value = false;
      delayed.complete(saved);
      await state.ready;
      await state.flushed;
      expect(state.leftOpen.value, false);
      expect(state.rightOpen.value, false);
      expect(saved.getBool(TabletSidebarPreferences.leftKey), false);
      state.dispose();
    },
  );

  test(
    'default automatic player visibility does not become an explicit choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = TabletSidebarPreferences();
      await state.ready;
      final prefs = await SharedPreferences.getInstance();
      expect(state.rightOpen.value, isNull);
      expect(prefs.containsKey(TabletSidebarPreferences.rightKey), false);
      state.dispose();
    },
  );
}
