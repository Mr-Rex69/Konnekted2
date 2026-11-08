import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/youtube_audio.dart';
import 'package:flick/features/discovery/youtube_player_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> player({bool plain = false}) => {
  'playabilityStatus': {'status': 'OK'},
  'streamingData': {
    'adaptiveFormats': [
      {
        'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
        'contentLength': '1024',
        'bitrate': 130000,
        'signatureCipher': Uri(
          queryParameters: {
            'url':
                'https://rr1.googlevideo.com/videoplayback?n=xyz&cver=original',
            's': 'abc',
            'sp': 'sig',
          },
        ).query,
      },
      if (plain)
        {
          'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          'contentLength': '1024',
          'bitrate': 48000,
          'url': 'https://rr2.googlevideo.com/videoplayback?plain=true',
        },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockClient client;
  late List<Uri> requests;
  setUp(() {
    requests = [];
    client = MockClient((request) async {
      requests.add(request.url);
      expect(request.headers['cookie'], isNull);
      if (request.url.path == '/') {
        return http.Response(
          '<script src="/s/player/test/player_ias.vflset/en_US/base.js"></script>',
          200,
        );
      }
      return http.Response(
        await File('test/fixtures/youtube/player.js').readAsString(),
        200,
      );
    });
  });
  tearDown(() => client.close());

  test(
    'decodes both signature and n, preserves the media client version',
    () async {
      final cipher = YoutubePlayerCipher(
        DiscoveryHttp(client),
        evaluate: (code, input, cancel) async {
          expect(
            code,
            contains('registerExtension({solve: input => jsc(input)})'),
          );
          expect(input['requests'], [
            {
              'type': 'sig',
              'challenges': ['abc'],
            },
            {
              'type': 'n',
              'challenges': ['xyz'],
            },
          ]);
          return {
            'type': 'result',
            'responses': [
              {
                'type': 'result',
                'data': {'abc': 'cba', 'xyz': 'xyz_decoded'},
              },
            ],
          };
        },
      );
      final response = player();
      final decoded = await cipher.decipher(response);
      final audio = YoutubeAudio.pick(decoded, YoutubeAudio.clients.last);
      expect(audio.url.queryParameters['sig'], 'cba');
      expect(audio.url.queryParameters['n'], 'xyz_decoded');
      expect(audio.url.queryParameters['cver'], 'original');
      expect(
        (response['streamingData']['adaptiveFormats'] as List).first['url'],
        isNull,
      );
      expect(await cipher.signatureTimestamp(), 20300);
      expect(
        requests.length,
        2,
      ); // Shell and current script, cached for the request.
    },
  );

  test('does not hand undecoded formats to the downloader', () async {
    final cipher = YoutubePlayerCipher(
      DiscoveryHttp(client),
      evaluate: (_, _, _) async => {
        'type': 'result',
        'responses': [
          {'type': 'error', 'error': 'private provider error'},
        ],
      },
    );
    await expectLater(
      cipher.decipher(player()),
      throwsA(
        isA<DiscoveryException>().having(
          (e) => e.message,
          'message',
          'YouTube player signature decoding failed.',
        ),
      ),
    );
    final decoded = await cipher.decipher(player(plain: true));
    expect(
      YoutubeAudio.pick(decoded, YoutubeAudio.clients.first).url.host,
      'rr2.googlevideo.com',
    );
  });

  test(
    'rejects a cross-site player script without sending cookies or fetching it',
    () async {
      final cipher = YoutubePlayerCipher(
        DiscoveryHttp(client),
        evaluate: (_, _, _) async => {},
      );
      cipher.readPlayerUrl(
        '{"jsUrl":"https://evil.example/s/player/test/base.js"}',
      );
      expect(await cipher.signatureTimestamp(), 20300);
      expect(requests.every((u) => u.host == 'www.youtube.com'), isTrue);
    },
  );

  test(
    'cancellation is preserved instead of becoming a cipher failure',
    () async {
      final cipher = YoutubePlayerCipher(
        DiscoveryHttp(client),
        evaluate: (_, _, _) async {
          throw const DiscoveryException('Request cancelled.');
        },
      );
      await expectLater(
        cipher.decipher(player()),
        throwsA(
          isA<DiscoveryException>().having(
            (e) => e.message,
            'message',
            'Request cancelled.',
          ),
        ),
      );
    },
  );

  test('bundled solver files match the pinned upstream release', () async {
    expect(
      sha256
          .convert(
            await File('assets/youtube/yt.solver.lib.min.js').readAsBytes(),
          )
          .toString(),
      'c55987fe697e5b9ee18830163f7af85327e9bb5c3e674b969d38c8d205eaa577',
    );
    expect(
      sha256
          .convert(
            await File('assets/youtube/yt.solver.core.min.js').readAsBytes(),
          )
          .toString(),
      '18da6ce0758b416e7ae645084f4f8801f9f9d59d6c477c05eaa0ff94ebd8cc00',
    );
  });

  test('resolver requests the current signature timestamp and verifies decoded TV media', () async {
    final asked = <String>[];
    final transport = MockClient((request) async {
      if (request.url.host.endsWith('.googlevideo.com')) {
        expect(request.url.queryParameters['sig'], 'cba');
        expect(request.url.queryParameters['n'], 'xyz_decoded');
        expect(request.url.queryParameters['cver'], 'original');
        return http.Response.bytes(
          [0, 0, 0, 24, 102, 116, 121, 112],
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      }
      if (request.method == 'GET') {
        if (request.url.path == '/') {
          return http.Response('{"jsUrl":"/s/player/current/base.js"}', 200);
        }
        return http.Response(
          await File('test/fixtures/youtube/player.js').readAsString(),
          200,
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = body['context']['client']['clientName'] as String;
      asked.add(name);
      if (name != 'TVHTML5') {
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'UNPLAYABLE'},
          }),
          200,
        );
      }
      expect(
        body['playbackContext']['contentPlaybackContext']['signatureTimestamp'],
        20300,
      );
      return http.Response(jsonEncode(player()), 200);
    });
    addTearDown(transport.close);
    final web = DiscoveryHttp(transport);
    final audio = await YoutubeAudio(
      web,
      cipher: YoutubePlayerCipher(
        web,
        evaluate: (_, _, _) async => {
          'type': 'result',
          'responses': [
            {
              'type': 'result',
              'data': {'abc': 'cba', 'xyz': 'xyz_decoded'},
            },
          ],
        },
      ),
    ).resolve('dQw4w9WgXcQ');
    expect(asked.last, 'TVHTML5');
    expect(audio.url.host, 'rr1.googlevideo.com');
  });
}
