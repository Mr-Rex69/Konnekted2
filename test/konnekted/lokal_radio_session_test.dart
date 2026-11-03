import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/konnekted/library/lokal_radio_session.dart';
import 'package:flick/models/song.dart';

Song track(String title, String artist, {String? id}) => Song(
  id: id ?? '$artist-$title',
  title: title,
  artist: artist,
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

void main() {
  test('radio prefers online discoveries instead of filling local queue', () {
    final seed = track('Seed', 'Original');
    final online = [
      track('New A', 'Related', id: 'yt:one'),
      track('New B', 'Different', id: 'yt:two'),
    ];
    final local = [
      track('Local A', 'Original'),
      track('Local B', 'Original'),
    ];
    final selected = selectLokalRadioAdditions(
      existing: [seed],
      online: online,
      localFallback: local,
    );
    expect(selected, online);
  });

  test('cross-provider and local duplicate recordings are skipped', () {
    final selected = selectLokalRadioAdditions(
      existing: [track('The Song', 'Artist', id: 'local')],
      online: [
        track('The Song (Official Audio)', 'Artist', id: 'yt:duplicate'),
        track('The New Song', 'Second Artist', id: 'yt:new'),
        track('The New Song', 'Second Artist', id: 'qobuz:duplicate'),
      ],
      localFallback: [track('Fallback', 'Artist')],
    );
    expect(selected.map((song) => song.id), ['yt:new']);
  });

  test('offline fallback is bounded and excludes already queued tracks', () {
    final local = [
      track('Seed', 'Original', id: 'other-local-id'),
      track('Similar A', 'Original'),
      track('Similar A', 'Original', id: 'other-provider'),
      track('Similar B', 'Other'),
      track('Similar C', 'Other'),
    ];
    final selected = selectLokalRadioAdditions(
      existing: [track('Seed', 'Original')],
      online: const [],
      localFallback: local,
      limit: 2,
    );
    expect(selected.map((song) => song.title), ['Similar A', 'Similar B']);
  });

  test('no fallback if only the same online recording was suggested', () {
    final selected = selectLokalRadioAdditions(
      existing: [track('Seed', 'Original')],
      online: [track('Seed (Official Video)', 'Original')],
      localFallback: [track('Offline', 'Other')],
    );
    expect(selected.map((song) => song.title), ['Offline']);
  });

  test('maximum queue size is respected', () {
    final selected = selectLokalRadioAdditions(
      existing: const [],
      online: [for (var i = 0; i < 20; i++) track('Song $i', 'Artist $i')],
      localFallback: const [],
      limit: 12,
    );
    expect(selected, hasLength(12));
  });
}
