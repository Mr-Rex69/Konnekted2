import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large recap worker preserves all week/month/year totals and lead artist', () async {
    final now = DateTime(2026, 11, 2, 15);
    const song = Song(
      id: '1',
      title: 'Track',
      artist: 'M83 feat. ZHU',
      album: 'Album',
      duration: Duration(minutes: 4),
      fileType: 'FLAC',
    );
    final entries = [
      for (var i = 0; i < 150; i++)
        RecentlyPlayedEntry(
          song: song,
          playedAt: now.subtract(Duration(minutes: i)),
          listenedMs: 120000,
        ),
    ];
    final ranges = {
      for (final period in [
        ListeningRecapPeriod.weekly,
        ListeningRecapPeriod.monthly,
        ListeningRecapPeriod.yearly,
      ])
        period: period.rangeFor(now),
    };
    final direct = await aggregateListeningRecapsFromEntries(
      entries: entries.take(20).toList(),
      ranges: ranges,
      unknownArtist: 'Unknown artist',
      unknownAlbum: 'Unknown album',
    );
    final worker = await aggregateListeningRecapsFromEntries(
      entries: entries,
      ranges: ranges,
      unknownArtist: 'Unknown artist',
      unknownAlbum: 'Unknown album',
      forceWorker: true,
    );
    for (final period in ranges.keys) {
      expect(direct[period]!.totalPlays, 20);
      expect(worker[period]!.totalPlays, 150);
      expect(worker[period]!.totalListeningTime.inMinutes, 300);
      expect(worker[period]!.uniqueSongs, 1);
      expect(worker[period]!.uniqueArtists, 1);
      expect(worker[period]!.topArtist!.artist, 'M83');
      expect(worker[period]!.topSong!.song.title, 'Track');
      expect(worker[period]!.topAlbum!.album, 'Album');
      expect(worker[period]!.activeDays, 1);
    }
  });

  test('recap worker excludes plays outside the requested period', () async {
    final now = DateTime(2026, 11, 2);
    const song = Song(
      id: '2', title: 'History', artist: 'Asake',
      duration: Duration(minutes: 3), fileType: 'FLAC',
    );
    final entries = [
      RecentlyPlayedEntry(song: song, playedAt: now.subtract(const Duration(days: 40))),
      RecentlyPlayedEntry(song: song, playedAt: now),
    ];
    final results = await aggregateListeningRecapsFromEntries(
      entries: entries,
      ranges: {
        for (final period in ListeningRecapPeriod.values)
          period: period.rangeFor(now),
      },
      unknownArtist: 'Unknown artist',
      unknownAlbum: 'Unknown album',
      forceWorker: true,
    );
    expect(results[ListeningRecapPeriod.daily]!.totalPlays, 1);
    expect(results[ListeningRecapPeriod.weekly]!.totalPlays, 1);
    expect(results[ListeningRecapPeriod.monthly]!.totalPlays, 1);
    expect(results[ListeningRecapPeriod.yearly]!.totalPlays, 2);
  });
}
