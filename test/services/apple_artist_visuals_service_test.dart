import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flick/services/apple_music/apple_artist_visuals_service.dart';
import 'package:flick/services/apple_music/apple_music_cache.dart';
import 'package:flick/services/apple_music/apple_music_metadata_service.dart';

const _hero = 'https://is1-ssl.mzstatic.com/image/thumb/hero/{w}x{h}{c}.{f}';
const _logo = 'https://is1-ssl.mzstatic.com/image/thumb/logo/{w}x{h}{c}.{f}';

String artistHtml({bool logo = true, bool video = true}) => '''
<html><script id="serialized-server-data">${jsonEncode([
  {
    'data': {
      'sections': [
        {
          'items': [
            {
              'header': {
                'artistLogo': logo
                    ? {
                        'dictionary': {
                          'url': _logo,
                          'width': 1600,
                          'height': 400,
                        },
                      }
                    : null,
                'artwork': {
                  'dictionary': {
                    'url': _hero,
                    'width': 1200,
                    'height': 800,
                  },
                },
                'videoArtwork': {
                  'dictionary': {
                    'motionArtistSquare1x1': video
                        ? {'video': 'https://video-ssl.itunes.apple.com/artist/master.m3u8'}
                        : null,
                  },
                },
              },
            },
          ],
        },
      ],
    },
  },
])}</script></html>
''';

void main() {
  test('parses artist hero, transparent logo aspect and silent HLS URL', () {
    final art = parseAppleArtistVisuals(artistHtml());
    expect(art?.heroUrl, contains('1200x800bb.jpg'));
    expect(art?.logoUrl, contains('1000x250bb.png'));
    expect(art?.logoAspect, 4);
    expect(art?.motionUrl, endsWith('/master.m3u8'));
  });

  test('missing logo and motion remain optional', () {
    final art = parseAppleArtistVisuals(artistHtml(logo: false, video: false));
    expect(art?.heroUrl, isNotNull);
    expect(art?.logoUrl, isNull);
    expect(art?.motionUrl, isNull);
  });

  test('malformed and unrelated embedded data fall back to static art', () {
    expect(parseAppleArtistVisuals('<html></html>'), isNull);
    expect(parseAppleArtistVisuals(
        '<script id="serialized-server-data">not-json</script>'), isNull);
    expect(parseAppleArtistVisuals(
        '<script id="serialized-server-data">[{"data":{}}]</script>'), isNull);
  });

  test('accepts a verified artist and returns editorial artwork', () async {
    final directory = await Directory.systemTemp.createTemp('artist_visuals_ok_');
    final cache = AppleMusicCache.forDirectory(directory);
    var artistPageCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'itunes.apple.com' &&
          request.url.path == '/search') {
        return http.Response(jsonEncode({
          'results': [{
            'wrapperType': 'artist',
            'artistId': 123,
            'artistName': 'Colby!',
            'artistLinkUrl': 'https://music.apple.com/us/artist/colby/123',
          }]
        }), 200);
      }
      if (request.url.host == 'itunes.apple.com' &&
          request.url.path == '/lookup') {
        return http.Response(jsonEncode({
          'results': [{
            'wrapperType': 'track',
            'artistName': 'Colby!',
            'trackName': 'Fall Head First',
            'collectionName': 'Fall Head First',
          }]
        }), 200);
      }
      if (request.url.host == 'music.apple.com') artistPageCalls++;
      return http.Response(artistHtml(), 200);
    });
    try {
      final service = AppleArtistVisualsService(
        metadata: AppleMusicMetadataService.create(
          client: client, cache: cache,
        ),
        client: client,
      );
      final first = await service.lookup(
        artistName: 'Colby!',
        knownTitles: ['Fall Head First'],
      );
      expect(first?.logoUrl, contains('1000x250bb.png'));
      expect(first?.motionUrl, endsWith('.m3u8'));
      final again = await service.lookup(
        artistName: 'Colby!',
        knownTitles: ['Fall Head First'],
      );
      expect(again?.logoUrl, first?.logoUrl);
      expect(artistPageCalls, 1);
    } finally {
      await cache.flushPendingWrites();
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test('does not accept an unrelated same-named Apple artist', () async {
    final directory = await Directory.systemTemp.createTemp('artist_visuals_');
    final cache = AppleMusicCache.forDirectory(directory);
    var artistPageCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'itunes.apple.com' &&
          request.url.path == '/search') {
        return http.Response(jsonEncode({
          'results': [{
            'wrapperType': 'artist',
            'artistId': 123,
            'artistName': 'Colby!',
          }]
        }), 200);
      }
      if (request.url.host == 'itunes.apple.com' &&
          request.url.path == '/lookup') {
        // Return a different artist's recording as the homonymous hit.
        return http.Response(jsonEncode({
          'results': [{
            'wrapperType': 'track',
            'artistName': 'Colby!',
            'trackName': 'Wrong Song',
            'collectionName': 'Wrong Album',
          }]
        }), 200);
      }
      if (request.url.host == 'music.apple.com') artistPageCalls++;
      return http.Response(artistHtml(), 200);
    });
    try {
      final service = AppleArtistVisualsService(
        metadata: AppleMusicMetadataService.create(
          client: client,
          cache: cache,
        ),
        client: client,
      );
      final found = await service.lookup(
        artistName: 'Colby!',
        knownTitles: ['Hello', 'Fall Head First'],
      );
      expect(found, isNull);
      expect(artistPageCalls, 0);
    } finally {
      await cache.flushPendingWrites();
      client.close();
      await directory.delete(recursive: true);
    }
  });
}
