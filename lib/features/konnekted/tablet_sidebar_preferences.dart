import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Explicit choices survive a restart. An unset player panel still follows
/// the workspace's existing size/playback default until the user changes it.
class TabletSidebarPreferences {
  TabletSidebarPreferences({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance() {
    leftOpen.addListener(_leftChanged);
    rightOpen.addListener(_rightChanged);
    ready = _restore();
  }

  static const leftKey = 'lokal.tablet.left_sidebar_open';
  static const rightKey = 'lokal.tablet.right_sidebar_open';
  final leftOpen = ValueNotifier(true);
  final rightOpen = ValueNotifier<bool?>(null);
  final Future<SharedPreferences> _preferences;
  late final Future<void> ready;
  Future<void> _writes = Future.value();
  Future<void> get flushed => _writes;
  var _leftRevision = 0, _rightRevision = 0;
  var _restoring = false, _disposed = false;

  Future<void> _restore() async {
    try {
      final prefs = await _preferences;
      if (_disposed) return;
      _restoring = true;
      if (_leftRevision == 0) leftOpen.value = prefs.getBool(leftKey) ?? true;
      if (_rightRevision == 0) rightOpen.value = prefs.getBool(rightKey);
    } catch (_) {
      debugPrint('Tablet sidebar preferences could not be restored.');
    } finally {
      _restoring = false;
    }
  }

  void _leftChanged() {
    if (_restoring) return;
    _leftRevision++;
    _save(leftKey, leftOpen.value);
  }

  void _rightChanged() {
    if (_restoring) return;
    _rightRevision++;
    final value = rightOpen.value;
    if (value != null) _save(rightKey, value);
  }

  void _save(String key, bool value) {
    _writes = _writes
        .then((_) async {
          final prefs = await _preferences;
          await prefs.setBool(key, value);
        })
        .catchError((Object _) {
          debugPrint('Tablet sidebar preference could not be saved.');
        });
  }

  void dispose() {
    _disposed = true;
    leftOpen.removeListener(_leftChanged);
    rightOpen.removeListener(_rightChanged);
    leftOpen.dispose();
    rightOpen.dispose();
  }
}
