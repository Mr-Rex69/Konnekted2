import 'dart:io';

import 'package:flick/features/search/library_download_artwork.dart';
import 'package:flick/services/artwork_pixel_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  final pixels = image.Image(width: 64, height: 64);
  final png = image.encodePng(pixels);
  setUp(
    () async => root = await Directory.systemTemp.createTemp('download_art_'),
  );
  tearDown(() => root.delete(recursive: true));

  test(
    'cached covers and file URIs become valid portable JPEG bytes',
    () async {
      final cover = File(p.join(root.path, 'cached cover.png'));
      await cover.writeAsBytes(png);
      for (final location in [cover.path, cover.uri.toString()]) {
        final bytes = await readLibraryDownloadArtwork(location);
        expect(bytes, isNotNull);
        expect(bytes!.take(3), [0xff, 0xd8, 0xff]);
        expect(image.decodeJpg(bytes)?.width, 64);
      }
      expect(
        await cover.readAsBytes(),
        png,
        reason: 'the playback cache is never rewritten',
      );
    },
  );

  test('HTTPS cover retrieval follows checked artwork redirects and validates bytes', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (requested.length == 1) {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://covers.example/cover.png'},
        );
      }
      return http.Response.bytes(
        png,
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
    });
    addTearDown(client.close);
    final bytes = await readLibraryDownloadArtwork(
      'https://covers.example/cover',
      client: client,
    );
    expect(bytes, isNotNull);
    expect(image.decodeJpg(bytes!)?.height, 64);
    expect(requested.map((uri) => uri.path), ['/cover', '/cover.png']);
  });

  test(
    'missing, corrupt and oversized images cannot become saved artwork',
    () async {
      expect(
        await readLibraryDownloadArtwork(p.join(root.path, 'missing.jpg')),
        isNull,
      );
      final invalid = File(p.join(root.path, 'invalid.jpg'));
      await invalid.writeAsString('not an image');
      expect(await readLibraryDownloadArtwork(invalid.path), isNull);
      final huge = await File(p.join(root.path, 'huge.jpg'))
          .open(mode: FileMode.write);
      await huge.truncate(artworkMaxBytes + 1);
      await huge.close();
      expect(
        await readLibraryDownloadArtwork(p.join(root.path, 'huge.jpg')),
        isNull,
      );
      expect(
        await readLibraryDownloadArtwork('http://covers.example/cover.jpg'),
        isNull,
      );
    },
  );
}
