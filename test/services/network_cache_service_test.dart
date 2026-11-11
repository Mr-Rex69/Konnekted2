import 'dart:io';

import 'package:flick/services/network_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late NetworkCacheService service;

  // FS mtime granularity can be 1s, so LRU order is controlled explicitly.
  final base = DateTime(2020, 1, 1, 12);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('network_cache_test');
    service = NetworkCacheService(
      sizeCapBytes: 100,
      rootDirectory: Directory('${root.path}/network_cache'),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('stash then getPath returns the same file', () async {
    final path = await service.stash(1, 'songA', [1, 2, 3], extension: 'flac');
    final cached = await service.getPath(1, 'songA', extension: 'flac');
    expect(cached, path);
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('getPath returns null when not cached or for another server', () async {
    await service.stash(1, 'songA', [1, 2, 3], extension: 'flac');
    expect(await service.getPath(1, 'songB', extension: 'flac'), isNull);
    expect(await service.getPath(2, 'songA', extension: 'flac'), isNull);
  });

  test(
    'a PC prefetch part is not playable until the completed file is published',
    () async {
      final path = await service.pathFor(1, 'next-track', extension: 'flac');
      final part = File('$path.part');
      await part.writeAsBytes([1, 2]);
      expect(await service.getPath(1, 'next-track'), isNull);
      expect(await service.getPath(1, 'next-track', extension: 'flac'), isNull);
      await part.writeAsBytes([1, 2, 3, 4]);
      await part.rename(path);
      expect(await service.getPath(1, 'next-track'), path);
      expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'waveform cache inspection does not change the source file stamp',
    () async {
      final path = await service.stash(1, 'waveform', [
        1,
        2,
        3,
      ], extension: 'flac');
      final before = DateTime(2020);
      await File(path).setLastModified(before);
      expect(await service.getPath(1, 'waveform', touch: false), path);
      expect((await File(path).stat()).modified, before);
    },
  );

  test(
    'a staged retry cannot shadow an existing complete cache entry',
    () async {
      final path = await service.pathFor(1, 'songA', extension: 'flac');
      await File('$path.part').writeAsBytes([9]);
      await service.stash(1, 'songA', [1, 2, 3], extension: 'flac');
      expect(await service.getPath(1, 'songA'), path);
      expect(await File((await service.getPath(1, 'songA'))!).readAsBytes(), [
        1,
        2,
        3,
      ]);
    },
  );

  test('cap is enforced and oldest entry is evicted first', () async {
    final p1 = await service.stash(
      1,
      'old',
      List.filled(40, 0),
      extension: 'flac',
    );
    await File(p1).setLastModified(base);
    final p2 = await service.stash(
      1,
      'mid',
      List.filled(40, 0),
      extension: 'flac',
    );
    await File(p2).setLastModified(base.add(const Duration(seconds: 1)));
    final p3 = await service.stash(
      1,
      'new',
      List.filled(40, 0),
      extension: 'flac',
    );
    await File(p3).setLastModified(base.add(const Duration(seconds: 2)));

    await service.stash(1, 'trigger', [1], extension: 'flac');

    expect(await service.getPath(1, 'old', extension: 'flac'), isNull);
    expect(await service.getPath(1, 'mid', extension: 'flac'), isNotNull);
    expect(await service.getPath(1, 'new', extension: 'flac'), isNotNull);
  });

  test('recently accessed entries survive eviction', () async {
    final p1 = await service.stash(
      1,
      'old',
      List.filled(40, 0),
      extension: 'flac',
    );
    await File(p1).setLastModified(base);
    final p2 = await service.stash(
      1,
      'fresh',
      List.filled(40, 0),
      extension: 'flac',
    );
    await File(p2).setLastModified(base.add(const Duration(seconds: 1)));

    expect(await service.getPath(1, 'old', extension: 'flac'), isNotNull);
    await File(p1).setLastModified(base.add(const Duration(seconds: 10)));

    await service.stash(1, 'new', List.filled(40, 0), extension: 'flac');

    expect(await service.getPath(1, 'old', extension: 'flac'), isNotNull);
    expect(await service.getPath(1, 'fresh', extension: 'flac'), isNull);
  });

  test('a single file exceeding the cap is still playable', () async {
    final path = await service.stash(
      1,
      'huge',
      List.filled(200, 0),
      extension: 'flac',
    );
    expect(await File(path).exists(), isTrue);
    expect(await service.getPath(1, 'huge', extension: 'flac'), path);
  });
}
