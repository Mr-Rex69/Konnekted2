import 'dart:convert';
import 'dart:io';

import 'package:flick/core/utils/artist_credits.dart';
import 'package:flick/features/konnekted/library/lokal_library_groups.dart';
import 'package:flick/features/music_videos/music_video_providers.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song song(String id, String artist, {String? albumArtist}) => Song(
  id: id,
  title: 'Song',
  artist: artist,
  albumArtist: albumArtist,
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

void main() {
  final cases = jsonDecode(
    File('test/core/utils/desktop_artist_credit_cases.json').readAsStringSync(),
  ) as List;
  test('built-in artist credits agree with current desktop outputs', () {
    for (final fixture in cases) {
      expect(
        splitArtistCredits(fixture['credit']),
        fixture['artists'],
        reason: fixture['credit'],
      );
    }
  });
  test('lead artist lookup preserves compound names and removes collaborators', () {
    expect(primaryArtistCredit('M83, ZHU'), 'M83');
    expect(primaryArtistCredit('Asake feat. Wizkid'), 'Asake');
    expect(primaryArtistCredit('Davido; Omah Lay'), 'Davido');
    expect(
      primaryArtistCredit('Tyler, the Creator & Kali Uchis'),
      'Tyler, the Creator',
    );
    expect(
      primaryArtistCredit('Earth, Wind & Fire, Guest'),
      'Earth, Wind & Fire',
    );
    expect(primaryArtistCredit(''), isEmpty);
    expect(primaryArtistCredit(null), isEmpty);
  });

  test('one collaboration credits each performer without combined or repeated artist rows', () {
    final shared = song(
      'one',
      'Alpha, Beta, Gamma, Delta, Echo',
      albumArtist: 'Alpha, Beta',
    );
    final artists = lokalArtists([shared, song('two', 'Beta')]);
    expect(artists.map((a) => a.name), [
      'Alpha',
      'Beta',
      'Delta',
      'Echo',
      'Gamma',
    ]);
    expect(
      artists.singleWhere((a) => a.name == 'Beta').songs.map((s) => s.id),
      ['one', 'two'],
    );
    expect(songArtistNames(shared), [
      'Alpha',
      'Beta',
      'Gamma',
      'Delta',
      'Echo',
    ]);
  });
  test('five old song/credit rows pointing at one video display one card immediately', () {
    final songs = [for (var i = 0; i < 5; i++) song('$i', 'Artist $i')];
    final index = MusicVideoIndex(
      matches: {for (var i = 0; i < 5; i++) '$i': 'sameVideoId'},
    );
    expect(uniqueMusicVideoSongs(songs, index), [songs.first]);
    expect(index.matches.length, 5); // Keep song associations and history.
  });
}
