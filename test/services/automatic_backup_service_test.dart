import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flick/services/automatic_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> snapshot(SharedPreferences prefs) => {
  'format': 'lokal-mobile-backup',
  'version': 1,
  'preferences': AutomaticBackupService.exportedPreferences(prefs),
  'songs': <Object>[],
  'folders': <Object>[],
  'artists': <Object>[],
  'recentlyPlayed': <Object>[],
  'playEvents': <Object>[],
  'libraryOps': <Object>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backup includes saved playlists and display settings but not credentials', () async {
    SharedPreferences.setMockInitialValues({
      'playlists': '[{"name":"Saved"}]',
      'theme': 'dark',
      'spotify_sp_dc_cookie': 'very-secret',
      'lastfm_session_key': 'hidden',
      'youtube_home_cache': 'large',
      'app_password': 'hidden',
      'lokal_auto_backup_frequency': 'daily',
    });
    final prefs = await SharedPreferences.getInstance();
    final values = AutomaticBackupService.exportedPreferences(prefs);
    expect(values['playlists'], '[{"name":"Saved"}]');
    expect(values['theme'], 'dark');
    expect(values.containsKey('spotify_sp_dc_cookie'), false);
    expect(values.containsKey('lastfm_session_key'), false);
    expect(values.containsKey('youtube_home_cache'), false);
    expect(values.containsKey('app_password'), false);
    expect(values.containsKey(AutomaticBackupService.frequencyKey), false);
  });

  test('disabled and daily backups: due on foreground, compressed and rotated', () async {
    SharedPreferences.setMockInitialValues({'playlists': '[]'});
    final prefs = await SharedPreferences.getInstance();
    final folder = await Directory.systemTemp.createTemp('lokal-backup-test-');
    addTearDown(() => folder.delete(recursive: true));
    var now = DateTime.utc(2026, 11, 8, 12);
    final service = AutomaticBackupService(
      directory: () async => folder,
      clock: () => now,
      snapshot: (prefs) async => snapshot(prefs),
    );

    expect(await service.runIfDue(), null);
    expect(await service.latestBackup(), null);
    await service.setFrequency('daily');
    final first = await service.runIfDue();
    expect(first, isNotNull);
    expect(first!.path.endsWith('.json.gz'), true);
    final decoded = AutomaticBackupService.decodeBackup(
      Uint8List.fromList(await first.readAsBytes()),
    );
    expect(decoded['format'], 'lokal-mobile-backup');
    expect((decoded['preferences'] as Map)['playlists'], '[]');

    now = now.add(const Duration(hours: 12));
    expect(await service.runIfDue(), null);
    now = now.add(const Duration(hours: 12));
    expect(await service.runIfDue(), isNotNull);

    final directory = await service.backupDirectory();
    await File('${directory.path}/manual-export.json').writeAsString('{}');
    for (var i = 0; i < 14; i++) {
      now = now.add(const Duration(days: 1));
      await service.runIfDue();
    }
    final names = await directory.list().map((entity) => entity.path.split('/').last).toList();
    expect(names.where(AutomaticBackupService.isAutomaticBackupFile).length, 10);
    expect(names.contains('manual-export.json'), true);
    expect((await service.lastSuccess())?.isAtSameMomentAs(now), true);
  });

  test('manual backup still writes after an overlapping due check', () async {
    SharedPreferences.setMockInitialValues({});
    final folder = await Directory.systemTemp.createTemp('lokal-backup-overlap-');
    addTearDown(() => folder.delete(recursive: true));
    final service = AutomaticBackupService(
      directory: () async => folder,
      snapshot: (prefs) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return snapshot(prefs);
      },
    );
    final due = service.runIfDue(); // Off, may resolve without creating a file.
    final manual = service.backupNow();
    await due;
    final file = await manual;
    expect(file, isNotNull);
    expect(await file!.exists(), true);
  });

  test('bounded gzip decode refuses expansion before accumulating excess bytes', () {
    final compressed = Uint8List.fromList(gzip.encode(List<int>.filled(200000, 65)));
    expect(
      () => AutomaticBackupService.decompressLimited(
        compressed, maxOutputBytes: 1024,
      ),
      throwsFormatException,
    );
    final decoded = AutomaticBackupService.decompressLimited(
      compressed, maxOutputBytes: 200000,
    );
    expect(decoded.length, 200000);
  });

  test('an invalid or incomplete import is rejected before any library mutation', () {
    expect(
      () => AutomaticBackupService.decodeBackup(Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode({
        'format': 'lokal-mobile-backup',
        'version': 1,
        'preferences': <String, Object>{},
        'songs': [],
      }))))),
      throwsFormatException,
    );
  });
}
