import 'dart:async';

import 'package:flick/features/konnekted/tablet_sidebar_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RejectOnce extends InMemorySharedPreferencesStore {
  _RejectOnce() : super.empty();
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (++writes == 1) return false;
    return super.setValue(type, key, value);
  }
}

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
    'a delayed disposed shell cannot overwrite the new shell choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final delayed = Completer<SharedPreferences>();
      final old = TabletSidebarPreferences(preferences: delayed.future);
      old.rightOpen.value = true;
      old.dispose();
      final current = TabletSidebarPreferences();
      await current.ready;
      current.rightOpen.value = false;
      await current.flushed;
      delayed.complete(prefs);
      await old.flushed;
      expect(prefs.getBool(TabletSidebarPreferences.rightKey), false);
      current.dispose();
    },
  );

  test('a rejected platform save is retried before flushing', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _RejectOnce();
    SharedPreferencesStorePlatform.instance = store;
    final state = TabletSidebarPreferences();
    await state.ready;
    state.leftOpen.value = false;
    await state.flushed;
    expect(store.writes, 2);
    expect(
      (await store.getAll())['flutter.${TabletSidebarPreferences.leftKey}'],
      false,
    );
    state.dispose();
  });

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
