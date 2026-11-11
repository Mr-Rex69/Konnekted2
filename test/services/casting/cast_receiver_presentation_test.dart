import 'dart:convert';
import 'dart:io';

import 'package:flick/models/song.dart';
import 'package:flick/services/casting/cast_content_server.dart';
import 'package:flick/services/casting/cast_receiver_presentation.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  for (final bmp in [false, true])
    test(
      'cached ${bmp ? 'BMP' : 'PNG'} artwork with an opaque filename is served as its real image type',
      () async {
        await binding.runAsync(() async {
          final directory = await Directory.systemTemp.createTemp(
            'cast-cover-',
          );
          final file = File('${directory.path}/opaque.file');
          final bytes = bmp
              ? <int>[0x42, 0x4d, ...List.filled(52, 0)]
              : base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6F4sAAAAASUVORK5CYII=',
                );
          final client = HttpClient();
          try {
            await file.writeAsBytes(bytes);
            final song = Song(
              id: 'art',
              title: 'Artwork',
              artist: 'Fixture',
              duration: const Duration(seconds: 10),
              fileType: 'flac',
              albumArt: file.path,
            );
            final url = await castArtwork(song);
            final response = await (await client.getUrl(
              Uri.parse(url!).replace(host: '127.0.0.1'),
            )).close();
            expect(
              response.headers.contentType?.mimeType,
              bmp ? 'image/bmp' : 'image/png',
            );
            expect(
              await response.fold<List<int>>(
                [],
                (all, bytes) => all..addAll(bytes),
              ),
              bytes,
            );
            expect(await castArtwork(song, stillCurrent: () => false), isNull);
          } finally {
            client.close(force: true);
            await CastContentServer.instance.stop();
            await directory.delete(recursive: true);
          }
        });
      },
    );
  test('lyrics carry stable recording identity and fractional timing', () {
    final message = castLyrics(
      'recording',
      const LyricsData(
        lines: [
          LyricsLine(timestamp: Duration(milliseconds: 1250), text: 'First'),
          LyricsLine(timestamp: Duration(milliseconds: 3500), text: 'Second'),
        ],
        isSynchronized: true,
        rawContent: '',
      ),
    );
    expect(message['trackId'], 'recording');
    expect(message['synced'], true);
    expect(message['lines'], [
      {'t': 1.25, 'text': 'First'},
      {'t': 3.5, 'text': 'Second'},
    ]);
    expect(castLyrics('next', null)['lines'], isEmpty);
  });
  Map<String, dynamic> finished(String id) => {
    'finished': true,
    'loadId': id,
    'trackId': 'recording',
  };

  test('completion is retained until a handoff or pending load commits', () {
    final gate = CastCompletionGate()..loaded('load-1');
    gate.observe({'finished': false, 'loadId': 'load-1'});
    gate.observe(finished('old'));
    expect(gate.takePending(ready: true), isNull);
    gate.observe(finished('load-1'));
    expect(gate.takePending(ready: false), isNull);
    // No second native event is required after the transition settles.
    expect(gate.takePending(ready: true)?['loadId'], 'load-1');
    gate.observe(finished('load-1'));
    expect(gate.takePending(ready: true), isNull);
    gate.begin('next');
    gate.observe(finished('next'));
    expect(gate.takePending(ready: false), isNull);
    gate.commit('next');
    expect(gate.takePending(ready: true)?['loadId'], 'next');
    expect(gate.takePending(ready: true), isNull);
  });

  test('failed replacement retains previous completion and consumed state', () {
    final gate = CastCompletionGate()..loaded('old');
    gate.begin('rejected');
    gate.observe(finished('old'));
    gate.observe(finished('rejected'));
    expect(gate.rollback('rejected'), true);
    expect(gate.loadId, 'old');
    expect(gate.takePending(ready: true)?['loadId'], 'old');
    gate.begin('another-rejected');
    gate.rollback('another-rejected');
    gate.observe(finished('old'));
    expect(gate.takePending(ready: true), isNull);
  });

  test(
    'old rollback and terminal events cannot replace a newer load or session',
    () {
      final gate = CastCompletionGate()..loaded('old');
      gate.begin('pending');
      gate.begin('newest');
      expect(gate.rollback('pending'), false);
      expect(gate.loadId, 'newest');
      gate.commit('newest');
      gate.observe(finished('pending'));
      expect(gate.takePending(ready: true), isNull);
      gate.observe(finished('newest'));
      gate.clear();
      expect(gate.takePending(ready: true), isNull);
      expect(gate.loadId, isNull);
    },
  );

  test('a saved video no-match does not repeat an online search', () async {
    SharedPreferences.setMockInitialValues({
      'lokal_music_video_matches': jsonEncode({'no-video': ''}),
    });
    final song = Song(
      id: 'no-video',
      title: 'Fixture',
      artist: 'Fixture',
      duration: const Duration(seconds: 10),
      fileType: 'flac',
    );
    expect(await castMusicVideo(song), isNull);
  });
}
