import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/data/entities/song_audio_cache_entity.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute.uri;
    final packages =
        (jsonDecode(await File.fromUri(config).readAsString())
                as Map)['packages']
            as List;
    final package = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'isar_community_flutter_libs',
    );
    final root = config.resolve('${package['rootUri']}/');
    final path = root
        .resolve(Platform.isMacOS ? 'macos/libisar.dylib' : 'linux/libisar.so')
        .toFilePath();
    Isar.initializeIsarCore(libraries: {Abi.current(): path});
  });
  late Directory directory;
  late Isar database;
  late SongRepository repository;
  late SongEntity row;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lokal-waveform-db-');
    database = await Isar.open(
      [SongEntitySchema, SongAudioCacheEntitySchema],
      directory: directory.path,
      name: 'waveform-cache',
    );
    repository = SongRepository(isar: database);
    row = SongEntity()
      ..id = 10
      ..filePath = '/music/recording.flac'
      ..title = 'Fixture'
      ..artist = 'Artist'
      ..dateAdded = DateTime(2026)
      ..lastModified = DateTime.fromMillisecondsSinceEpoch(1000);
    await database.writeTxn(() => database.songEntitys.put(row));
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });
  Song song({
    String path = '/music/recording.flac',
    bool external = false,
    int? offset,
  }) => Song(
    id: '10',
    title: 'Fixture',
    artist: 'Artist',
    fileType: 'FLAC',
    filePath: path,
    duration: const Duration(minutes: 3),
    isExternal: external,
    startOffsetMs: offset,
  );
  SongAudioCacheEntity cache(int at) => SongAudioCacheEntity()
    ..songId = 10
    ..version = SongAudioCacheEntity.currentVersion
    ..computedAt = at
    ..peaks = [.25, .75, 0, .5];

  test('numeric provider IDs and other files cannot borrow or replace library peaks', () async {
    await repository.upsertAudioCacheForSong(song(), cache(2000));
    expect(await repository.getAudioCacheForSong(song()), isNotNull);
    for (final other in [
      song(external: true),
      song(path: '/elsewhere.flac'),
      song(offset: 10000),
    ]) {
      expect(await repository.getAudioCacheForSong(other), isNull);
      await repository.upsertAudioCacheForSong(other, cache(3000));
    }
    expect((await repository.getAudioCache(10))!.computedAt, 2000);
  });

  test(
    'a rescan invalidates old analysis and a late decoder cannot overwrite it',
    () async {
      await repository.upsertAudioCacheForSong(song(), cache(2000));
      row.lastModified = DateTime.fromMillisecondsSinceEpoch(4000);
      await database.writeTxn(() => database.songEntitys.put(row));
      expect(await repository.getAudioCacheForSong(song()), isNull);
      await repository.upsertAudioCacheForSong(song(), cache(3000));
      expect((await repository.getAudioCache(10))!.computedAt, 2000);
      await repository.upsertAudioCacheForSong(song(), cache(5000));
      await repository.upsertAudioCacheForSong(song(), cache(4500));
      expect((await repository.getAudioCacheForSong(song()))!.computedAt, 5000);
    },
  );

  test(
    'a deleted recording does not gain an orphaned late analysis row',
    () async {
      await database.writeTxn(() => database.songEntitys.delete(10));
      await repository.upsertAudioCacheForSong(song(), cache(2000));
      expect(await repository.getAudioCache(10), isNull);
    },
  );

  test(
    'old left-channel/estimated-duration waveforms are regenerated',
    () async {
      await repository.upsertAudioCache(cache(2000)..version = 1);
      expect(await repository.getAudioCacheForSong(song()), isNull);
    },
  );
}
