import 'dart:io';

import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Songs implements SongRepository {
  _Songs(this.songs);
  final List<Song> songs;

  @override
  Future<List<Song>> getAllSongs() async => songs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Song _song(String id, String title, String artist, String path) => Song(
      id: id,
      title: title,
      artist: artist,
      filePath: path,
      duration: const Duration(minutes: 3),
      fileType: 'FLAC',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PlaylistImportResult> importFixture(
    String content,
    List<Song> songs,
  ) async {
    final directory = await Directory.systemTemp.createTemp('lokal-m3u-test-');
    try {
      final file = File('\${directory.path}/import.m3u8');
      await file.writeAsString(content);
      final service = PlaylistService(songRepository: _Songs(songs));
      final results = await service.syncPlaylistsFromSources([
        PlaylistSourceFile(sourcePath: file.path, displayName: 'import.m3u8'),
      ]);
      expect(results, hasLength(1));
      return results.single;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  test('EXTINF matches a local SAF song with an opaque path', () async {
    final result = await importFixture(
      '#EXTM3U\n#EXTINF:190,Artist - A Song\n'
      r'C:\Music\old-device\unknown.mp3' '\n',
      [_song('1', 'A Song', 'Artist',
          'content://media/external/audio/media/70992')],
    );
    expect(result.importedSongs, 1);
    expect(result.playlist.songIds, ['1']);
    expect(result.unmatchedEntries, 0);
  });

  test('plain filenames match uniquely even if the file codec changed', () async {
    final result = await importFixture(
      '#EXTM3U\nArtist - A Song.mp3\n',
      [_song('2', 'A Song', 'Artist', '/storage/Music/unrelated.flac')],
    );
    expect(result.playlist.songIds, ['2']);
  });

  test('never guesses between two editions with identical metadata', () async {
    final result = await importFixture(
      '#EXTM3U\n#EXTINF:-1,Artist - A Song\nunknown.mp3\n',
      [
        _song('3', 'A Song', 'Artist', '/Music/album-a.flac'),
        _song('4', 'A Song', 'Artist', '/Music/album-b.flac'),
      ],
    );
    expect(result.importedSongs, 0);
    expect(result.unmatchedEntries, 1);
    expect(result.playlist.songIds, isEmpty);
  });

  test('an EXTINF artist does not match the wrong artist', () async {
    final result = await importFixture(
      '#EXTM3U\n#EXTINF:180,Artist A - A Song\nnot-in-library.mp3\n',
      [_song('5', 'A Song', 'Artist B', '/Music/song.flac')],
    );
    expect(result.importedSongs, 0);
  });
}
