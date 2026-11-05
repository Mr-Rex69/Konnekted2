import 'dart:async';

import 'package:flick/data/entities/artist_entity.dart';
import 'package:flick/core/utils/artist_credits.dart';
import 'package:flick/features/library_jobs/artist_metadata.dart';
import 'package:flick/features/library_jobs/library_jobs.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Song song(int id, String artist) => Song(
  id: '$id',
  title: 'Song $id',
  artist: artist,
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

class _Metadata extends ArtistMetadata {
  _Metadata({super.parseCredits});
  final refreshed = <String>[];
  void publishPortrait(String name, String path) =>
      state = {...state, ArtistMetadata.key(name): path};

  @override
  Future<void> refresh(String name, {bool force = false}) async {
    refreshed.add(name);
  }
}

void main() {
  test(
    '5500-song warmup yields and only parses changed credit pairs',
    () async {
      var parsed = 0;
      final worker = _Metadata(
        parseCredits: (song) {
          parsed++;
          return songArtistNames(song);
        },
      );
      final container = ProviderContainer(
        overrides: [artistMetadataProvider.overrideWith(() => worker)],
      );
      addTearDown(container.dispose);
      container.read(artistMetadataProvider);
      final songs = [for (var i = 0; i < 5500; i++) song(i, 'Artist $i')];
      worker.warm(songs);
      expect(parsed, 0); // The library listener itself does no credit parsing.
      var parsedAtYield = -1;
      Timer.run(() => parsedAtYield = parsed);
      await worker.warmupIdle;
      expect(parsedAtYield, inInclusiveRange(1, 64));
      expect(parsed, 5500);
      worker.warm(
        songs.map((s) => s.copyWith(albumArt: '/new/cover.jpg')).toList(),
      );
      await worker.warmupIdle;
      expect(parsed, 5500);
      worker.warm([songs.first.copyWith(artist: 'New Artist feat. Guest')]);
      await worker.warmupIdle;
      expect(parsed, 5501);
    },
  );

  test(
    'newer snapshots supersede queued work and dispose stops parsing',
    () async {
      final parsed = <String>[];
      final worker = _Metadata(
        parseCredits: (song) {
          parsed.add(song.artist);
          return [song.artist];
        },
      );
      final container = ProviderContainer(
        overrides: [artistMetadataProvider.overrideWith(() => worker)],
      );
      container.read(artistMetadataProvider);
      worker.warm([for (var i = 0; i < 5500; i++) song(i, 'Old $i')]);
      worker.warm([song(1, 'Newest')]);
      await worker.warmupIdle;
      expect(parsed, ['Newest']);
      worker.warm([song(2, 'Disposed')]);
      container.dispose();
      await worker.warmupIdle;
      expect(parsed, ['Newest']);
    },
  );

  test('artist portrait path changes update list subscribers immediately', () {
    final worker = _Metadata();
    final container = ProviderContainer(
      overrides: [artistMetadataProvider.overrideWith(() => worker)],
    );
    addTearDown(container.dispose);
    final observed = <String?>[];
    final subscription = container.listen<String?>(
      artistMetadataProvider.select((paths) => paths[ArtistMetadata.key('M83')]),
      (previous, next) => observed.add(next),
    );
    addTearDown(subscription.close);
    worker.publishPortrait('M83', '/cache/old-portrait.jpg');
    worker.publishPortrait('M83', '/cache/new-portrait.jpg');
    expect(observed, ['/cache/old-portrait.jpg', '/cache/new-portrait.jpg']);
  });

  test('saved Spotify-only artist portrait is included without local tracks', () {
    final followedOnly = ArtistEntity()
      ..name = 'Imported Spotify Artist'
      ..artPath = '/app/support/artist_portraits/spotify-art.img';
    final local = ArtistEntity()
      ..name = 'Local Artist'
      ..artPath = '/app/support/artist_portraits/local-art.img';
    final missing = ArtistEntity()
      ..name = 'Unresolved Artist';
    final paths = savedArtistPortraitPaths([followedOnly, local, missing]);
    expect(paths['imported spotify artist'],
        '/app/support/artist_portraits/spotify-art.img');
    expect(paths['local artist'],
        '/app/support/artist_portraits/local-art.img');
    expect(paths.containsKey('unresolved artist'), isFalse);
  });

  test('manual refresh sorts local and followed artist names together', () {
    final order = alphabeticalArtistRefreshNames(
      ['ZHU', 'Tyler, the Creator', 'M83'],
      ['Asake', 'zhu', 'Burna Boy', 'M83'],
    );
    expect(
      order,
      ['Asake', 'Burna Boy', 'M83', 'Tyler, the Creator', 'ZHU'],
    );
    expect(alphabeticalArtistRefreshNames([], ['B', 'a']), ['a', 'B']);
  });

  test('forced portrait refresh uses a new cache identity', () {
    final first = DateTime.fromMicrosecondsSinceEpoch(1700000000000000);
    final second = first.add(const Duration(microseconds: 1));
    final originalKey = refreshedArtistPortraitCacheKey(' M83 ', first);
    expect(originalKey, contains('m83'));
    expect(originalKey, refreshedArtistPortraitCacheKey('m83', first));
    expect(originalKey, isNot(refreshedArtistPortraitCacheKey('m83', second)));
    expect(originalKey, isNot(refreshedArtistPortraitCacheKey('other', first)));
  });

  test('album refresh reports actual upgraded covers', () {
    const status = LibraryJobStatus(
      job: LibraryJob.releases,
      done: 120,
      total: 120,
      updated: 38,
      failed: 3,
    );
    expect(status.message, contains('38 covers upgraded'));
    expect(status.message, contains('3 unavailable'));
    expect(status.message, contains('Finished'));
  });

  test('artist refresh reports updated portraits separately from unavailable', () {
    const status = LibraryJobStatus(
      job: LibraryJob.artists,
      done: 4,
      total: 4,
      updated: 3,
      failed: 1,
    );
    expect(status.message, contains('3 artist assets refreshed'));
    expect(status.message, contains('1 unavailable'));
    expect(status.message, contains('Finished'));
  });

}
