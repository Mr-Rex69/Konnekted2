import 'dart:convert';
import 'dart:io';

import 'package:flick/models/song.dart';
import 'package:flick/services/casting/cast_content_server.dart';
import 'package:flick/services/casting/cast_receiver_presentation.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached artwork with an opaque filename is served as its real image type',
    () async {
      await binding.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp('cast-cover-');
        final file = File('${directory.path}/opaque.file');
        final bytes = base64Decode(
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
          expect(response.headers.contentType?.mimeType, 'image/png');
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
  test('receiver completion advances once, ignores buffering, cancellation and old loads', () {
    final gate = CastCompletionGate()..loaded('load-1');
    expect(
      gate.accept({
        'finished': false,
        'loadId': 'load-1',
      }, changingOutput: false),
      false,
    );
    expect(
      gate.accept({'finished': true, 'loadId': 'old'}, changingOutput: false),
      false,
    );
    expect(
      gate.accept({'finished': true, 'loadId': 'load-1'}, changingOutput: true),
      false,
    );
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'load-1',
      }, changingOutput: false),
      true,
    );
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'load-1',
      }, changingOutput: false),
      false,
    );
    gate.loaded('repeat-same-recording');
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'load-1',
      }, changingOutput: false),
      false,
    );
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'repeat-same-recording',
      }, changingOutput: false),
      true,
    );
    gate.loaded('disconnect');
    gate.clear();
    expect(
      gate.accept({
        'finished': true,
        'loadId': 'disconnect',
      }, changingOutput: false),
      false,
    );
  });
}
