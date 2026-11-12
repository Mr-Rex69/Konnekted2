import 'dart:async';

import 'package:flick/features/konnekted/library/collection_downloads.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song song(
  String id, {
  String? path,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  int seconds = 180,
  String? source,
  bool external = false,
  bool atmos = false,
  String? package,
}) => Song(
  id: id,
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: seconds),
  fileType: 'FLAC',
  filePath: path,
  sourceType: source,
  isExternal: external,
  sourcePackage: package,
  atmosEncoded: atmos,
);

void main() {
  test(
    'only real library files count; playback caches and absent files do not',
    () async {
      final index = await OfflineCollectionIndex.build([
        song('local', path: '/music/song.flac'),
        song('gone', title: 'Gone', path: '/missing.flac'),
        song(
          'cache',
          title: 'Cache',
          path: '/cache/stream.flac',
          external: true,
        ),
        song(
          'stream',
          title: 'Stream',
          path: '/cache/live.flac',
          package: 'konnekted.progressive',
        ),
        song('network', title: 'Network', path: 'lokal://1/2', source: 'lokal'),
      ], exists: (path) async => path != '/missing.flac');
      expect(
        index.match(song('pending', package: Song.pendingSourcePackage))?.id,
        'local',
      );
      for (final title in ['Gone', 'Cache', 'Stream', 'Network']) {
        expect(index.match(song('reference', title: title)), isNull);
      }
      final restored = index.resolve(
        song('pending:playlist:x', package: Song.pendingSourcePackage),
      );
      expect(restored.id, 'pending:playlist:x');
      expect(restored.filePath, '/music/song.flac');
      expect(restored.isPending, isFalse);
    },
  );

  test(
    'offline matching preserves recording, album and Atmos requirements',
    () async {
      final index = await OfflineCollectionIndex.build([
        song('local', path: '/music/song.flac'),
      ], exists: (_) async => true);
      for (final different in [
        song('artist', artist: 'Other'),
        song('edit', seconds: 210),
        song('album', album: 'Other album'),
        song('live', title: 'Song (Live)'),
        song('atmos', atmos: true),
      ]) {
        expect(index.match(different), isNull, reason: different.id);
      }
    },
  );

  test('a whole collection skips owned songs and duplicate references, continues failures', () async {
    final calls = <String>[];
    final cancel = Completer<void>();
    final downloader = CollectionDownloader(
      library: () async => [
        song('owned', title: 'Owned', path: '/music/owned.flac'),
      ],
      exists: (_) async => true,
      download:
          (
            entry, {
            required cancel,
            required cancelled,
            required onStatus,
          }) async {
            calls.add(entry.id);
            if (entry.id == 'fail') throw StateError('Unavailable');
            return song(
              'saved-${entry.id}',
              title: entry.title,
              path: '/music/${entry.id}.flac',
            );
          },
    );
    final updates = <CollectionDownloadProgress>[];
    final result = await downloader.run(
      [
        song('owned-reference', title: 'Owned'),
        song('new'),
        song('new'),
        song('same-recording'),
        song('fail', title: 'Unavailable'),
        song('last', title: 'Last'),
      ],
      cancel: cancel.future,
      cancelled: () => false,
      onProgress: updates.add,
    );
    expect(calls, ['new', 'fail', 'last']);
    expect(result.saved, 2);
    expect(result.skipped, 3);
    expect(result.failed, 1);
    expect(result.completed, 6);
    expect(result.lastError, contains('Unavailable'));
    expect(updates.last, result);
  });

  test('Stop prevents later downloads even while the current original copy completes', () async {
    final cancel = Completer<void>();
    final calls = <String>[];
    final downloader = CollectionDownloader(
      library: () async => [],
      download:
          (
            entry, {
            required cancel,
            required cancelled,
            required onStatus,
          }) async {
            calls.add(entry.id);
            // A native original-file transfer cannot always be interrupted.
            return song('saved', path: '/music/song.flac');
          },
    );
    final result = await downloader.run(
      [song('one'), song('two', title: 'Second')],
      cancel: cancel.future,
      cancelled: () => cancel.isCompleted,
      onProgress: (progress) {
        if (progress.status.startsWith('Downloading') && !cancel.isCompleted)
          cancel.complete();
      },
    );
    expect(calls, ['one']);
    expect(result.saved, 1);
    expect(result.cancelled, isTrue);
    expect(result.completed, 1);
  });

  test('persisted downloaded copy resolves again in a fresh index without changing membership IDs', () async {
    final reference = song('liked-stable', package: Song.pendingSourcePackage);
    final library = [song('database-id', path: '/music/download.flac')];
    for (var session = 0; session < 2; session++) {
      final index = await OfflineCollectionIndex.build(
        library,
        exists: (_) async => true,
      );
      final resolved = index.resolve(reference);
      expect(resolved.id, reference.id);
      expect(resolved.filePath, '/music/download.flac');
      expect(resolved.isPending, isFalse);
    }
  });
}
