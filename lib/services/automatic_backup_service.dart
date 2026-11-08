import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flick/data/database.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A portable backup of preferences, library metadata, playlists and listening
/// events. No audio files, network-server credentials or reproducible caches.
class AutomaticBackupService {
  AutomaticBackupService({
    Future<SharedPreferences> Function()? preferences,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
    Future<Map<String, dynamic>> Function(SharedPreferences)? snapshot,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _directory = directory ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now,
       _snapshot = snapshot;

  static final instance = AutomaticBackupService();
  static const frequencyKey = 'lokal_auto_backup_frequency';
  static const lastSuccessKey = 'lokal_auto_backup_last_success';
  static const keep = 10;
  static const day = Duration(days: 1);
  static const week = Duration(days: 7);
  static const retry = Duration(hours: 1);
  static const maxBackupBytes = 100 * 1024 * 1024;
  final Future<SharedPreferences> Function() _preferences;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final Future<Map<String, dynamic>> Function(SharedPreferences)? _snapshot;
  Future<File?>? _running;
  DateTime? _lastAttempt;

  static Duration? interval(String frequency) => switch (frequency) {
    'daily' => day,
    'weekly' => week,
    _ => null,
  };

  /// Never export cookies, authentication state, passwords or large caches.
  /// Local playlists are stored under 'playlists' and are intentionally kept.
  static bool safePreferenceKey(String key) {
    final lower = key.toLowerCase();
    if (lower.startsWith('lokal_auto_backup_')) return false;
    return !RegExp(
      r'(token|secret|password|cookie|credential|authorization|auth_|_auth|session|bearer|api[_-]?key|private|cache)',
    ).hasMatch(lower);
  }

  static Map<String, dynamic> exportedPreferences(SharedPreferences prefs) {
    final result = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!safePreferenceKey(key)) continue;
      final value = prefs.get(key);
      if (value is bool || value is int || value is double || value is String) {
        result[key] = value;
      } else if (value is List<String>) {
        result[key] = value;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _export(SharedPreferences prefs) async {
    final db = Database.instance;
    return {
      'format': 'lokal-mobile-backup',
      'version': 1,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'preferences': exportedPreferences(prefs),
      'songs': await db.songEntitys.where().exportJson(),
      'folders': await db.folderEntitys.where().exportJson(),
      'artists': await db.artistEntitys.where().exportJson(),
      'recentlyPlayed': await db.recentlyPlayedEntitys.where().exportJson(),
      'playEvents': await db.playEventEntitys.where().exportJson(),
      'libraryOps': await db.libraryOpEntitys.where().exportJson(),
    };
  }

  Future<Directory> backupDirectory() async {
    final docs = await _directory();
    return Directory(p.join(docs.path, 'Lokal Backups'));
  }

  Future<String> frequency() async =>
      (await _preferences()).getString(frequencyKey) ?? 'off';

  Future<DateTime?> lastSuccess() async {
    final ms = (await _preferences()).getInt(lastSuccessKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setFrequency(String value) async {
    if (value != 'off' && interval(value) == null) {
      throw ArgumentError.value(value, 'frequency');
    }
    await (await _preferences()).setString(frequencyKey, value);
  }

  Future<File?> latestBackup() async {
    final dir = await backupDirectory();
    if (!await dir.exists()) return null;
    final files = await dir.list().where((entry) =>
      entry is File && isAutomaticBackupFile(p.basename(entry.path)),
    ).cast<File>().toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.first;
  }

  static bool isAutomaticBackupFile(String name) =>
      RegExp(r'^lokal-auto-backup-\d{4}-\d{2}-\d{2}T[\d-]+Z\.json\.gz$').hasMatch(name);

  Future<File?> runIfDue() => _run(force: false);
  Future<File?> backupNow() => _run(force: true);

  Future<File?> _run({required bool force}) async {
    if (_running != null) return _running;
    final work = _perform(force: force);
    _running = work;
    try {
      return await work;
    } finally {
      _running = null;
    }
  }

  Future<File?> _perform({required bool force}) async {
    final prefs = await _preferences();
    final now = _clock();
    final cadence = interval(prefs.getString(frequencyKey) ?? 'off');
    if (!force) {
      if (cadence == null) return null;
      final last = prefs.getInt(lastSuccessKey);
      if (last != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(last)) < cadence) {
        return null;
      }
      if (_lastAttempt != null && now.difference(_lastAttempt!) < retry) {
        return null;
      }
    }
    _lastAttempt = now;
    final payload = await (_snapshot?.call(prefs) ?? _export(prefs));
    if (payload['version'] != 1 || payload['format'] != 'lokal-mobile-backup') {
      throw const FormatException('Invalid mobile backup data.');
    }
    final bytes = await Isolate.run(
      () => gzip.encode(utf8.encode(jsonEncode(payload))),
    );
    final dir = await backupDirectory();
    await dir.create(recursive: true);
    final stamp = now.toUtc().toIso8601String()
        .replaceAll(':', '-').replaceAll('.', '-');
    final file = File(p.join(dir.path, 'lokal-auto-backup-$stamp.json.gz'));
    final staging = File('${file.path}.tmp');
    try {
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(file.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    await prefs.setInt(lastSuccessKey, now.millisecondsSinceEpoch);
    // Existing, user-created files are never considered for rotation.
    final existing = await dir.list().where((entry) =>
      entry is File && isAutomaticBackupFile(p.basename(entry.path)),
    ).cast<File>().toList();
    existing.sort((a, b) => b.path.compareTo(a.path));
    for (final old in existing.skip(keep)) {
      try { await old.delete(); } catch (_) {}
    }
    return file;
  }

  /// A picked backup is fully parsed and type-validated before any mutation.
  /// Isar collections are replaced in one transaction; failed imports roll back.
  static Map<String, dynamic> decodeBackup(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const FormatException('Backup is empty or too large.');
    }
    final decoded = gzip.decode(bytes);
    if (decoded.length > 300 * 1024 * 1024) {
      throw const FormatException('Uncompressed backup is too large.');
    }
    final data = jsonDecode(utf8.decode(decoded));
    if (data is! Map<String, dynamic> ||
        data['format'] != 'lokal-mobile-backup' || data['version'] != 1) {
      throw const FormatException('Not a supported Lokal mobile backup.');
    }
    for (final key in const [
      'songs', 'folders', 'artists', 'recentlyPlayed', 'playEvents', 'libraryOps',
    ]) {
      if (data[key] is! List ||
          (data[key] as List).any((item) => item is! Map<String, dynamic>)) {
        throw FormatException('Invalid $key collection in backup.');
      }
    }
    if (data['preferences'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid preferences in backup.');
    }
    return data;
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) =>
      (data[key] as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();

  Future<void> restore(Uint8List bytes) async {
    // Do not clear an existing library until every section has been checked.
    final data = await Isolate.run(() => decodeBackup(bytes));
    final songs = _rows(data, 'songs');
    final folders = _rows(data, 'folders');
    final artists = _rows(data, 'artists');
    final recent = _rows(data, 'recentlyPlayed');
    final events = _rows(data, 'playEvents');
    final ops = _rows(data, 'libraryOps');
    final prefsData = Map<String, dynamic>.from(data['preferences'] as Map);
    final db = Database.instance;
    await db.writeTxn(() async {
      await db.libraryOpEntitys.clear();
      await db.playEventEntitys.clear();
      await db.recentlyPlayedEntitys.clear();
      await db.artistEntitys.clear();
      await db.folderEntitys.clear();
      await db.songEntitys.clear();
      await db.songEntitys.importJson(songs);
      await db.folderEntitys.importJson(folders);
      await db.artistEntitys.importJson(artists);
      await db.recentlyPlayedEntitys.importJson(recent);
      await db.playEventEntitys.importJson(events);
      await db.libraryOpEntitys.importJson(ops);
    });
    final prefs = await _preferences();
    for (final entry in prefsData.entries) {
      if (!safePreferenceKey(entry.key)) continue;
      switch (entry.value) {
        case bool value:
          await prefs.setBool(entry.key, value);
        case int value:
          await prefs.setInt(entry.key, value);
        case double value:
          await prefs.setDouble(entry.key, value);
        case String value:
          await prefs.setString(entry.key, value);
        case List value when value.every((item) => item is String):
          await prefs.setStringList(entry.key, value.cast<String>());
      }
    }
  }
}
