import 'dart:convert';

import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'PC artwork loads with remote credentials and no mobile library',
    () async {
      final credentials = LokalRemoteCredentials(
        origin: Uri.parse('http://desktop:3421'),
        remoteToken: 'paired-token',
        apiKey: 'api-key',
      );
      final requests = <http.Request>[];
      final service = LokalRemoteService(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'desktop') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://covers.example/cover.png'},
            );
          }
          return http.Response.bytes([137, 80, 78, 71], 200);
        }),
      );
      addTearDown(service.close);
      expect(await service.fetchArtwork(credentials, 'track/a'), [
        137,
        80,
        78,
        71,
      ]);
      expect(requests.first.url.pathSegments, ['api', 'artwork', 'track/a']);
      expect(requests.first.url.queryParameters, {'full': '1'});
      expect(requests.first.headers['x-remote-token'], 'paired-token');
      expect(requests.last.headers.containsKey('x-remote-token'), isFalse);
      expect(requests.last.headers.containsKey('x-api-key'), isFalse);
      expect(requests.last.followRedirects, isFalse);
    },
  );

  test('PC artwork rejects credential-bearing or insecure redirects', () async {
    for (final target in [
      'http://covers.example/a',
      'https://secret@covers.example/a',
      '/other',
    ]) {
      var requests = 0;
      final service = LokalRemoteService(
        client: MockClient((request) async {
          requests++;
          return http.Response('', 302, headers: {'location': target});
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetchArtwork(
          LokalRemoteCredentials(
            origin: Uri.parse('http://desktop'),
            remoteToken: 'token',
          ),
          'one',
        ),
        throwsA(isA<LokalRemoteProtocolException>()),
      );
      expect(requests, 1);
    }
  });

  test(
    'PC artwork can recover on a later request after an unavailable cover',
    () async {
      var requests = 0;
      final service = LokalRemoteService(
        client: MockClient(
          (_) async => ++requests == 1
              ? http.Response('', 404)
              : http.Response.bytes([1, 2, 3], 200),
        ),
      );
      addTearDown(service.close);
      final credentials = LokalRemoteCredentials(
        origin: Uri.parse('http://desktop'),
        remoteToken: 'token',
      );
      await expectLater(
        service.fetchArtwork(credentials, 'one'),
        throwsA(isA<LokalRemoteProtocolException>()),
      );
      expect(await service.fetchArtwork(credentials, 'one'), [1, 2, 3]);
    },
  );

  test(
    'normalizes desktop origins and /remote links without query secrets',
    () {
      expect(
        LokalRemoteService.normalizeOrigin('http://192.168.1.20:3421/remote/'),
        Uri.parse('http://192.168.1.20:3421'),
      );
      expect(
        LokalRemoteService.normalizeOrigin('https://lokal.example/api/remote'),
        Uri.parse('https://lokal.example'),
      );
      expect(
        () => LokalRemoteService.normalizeOrigin(
          'http://user:secret@192.168.1.20:3421/remote',
        ),
        throwsA(isA<LokalRemoteConfigurationException>()),
      );
      expect(
        () => LokalRemoteService.normalizeOrigin(
          'http://192.168.1.20:3421/remote?token=secret',
        ),
        throwsA(isA<LokalRemoteConfigurationException>()),
      );
    },
  );

  test(
    'fetches state with auth headers and decodes a nullable track',
    () async {
      http.Request? received;
      final client = MockClient((request) async {
        received = request;
        return http.Response(
          jsonEncode({
            'connected': true,
            'isPlaying': true,
            'progress': 42.5,
            'duration': 215,
            'volume': .5,
            'repeat': 'all',
            'shuffle': false,
            'currentTrack': {
              'id': 'track-id',
              'title': 'Title',
              'artist': 'Artist',
              'album': 'Album',
              'artwork_path': r'C:\cover.jpg',
            },
            'updatedAt': 1234,
          }),
          200,
        );
      });
      final service = LokalRemoteService(client: client);
      final state = await service.fetchState(
        LokalRemoteCredentials(
          origin: Uri.parse('http://192.168.1.20:3421'),
          remoteToken: 'remote-secret',
          apiKey: 'api-secret',
        ),
      );

      expect(
        received!.url.toString(),
        'http://192.168.1.20:3421/api/remote/state',
      );
      expect(received!.headers['x-remote-token'], 'remote-secret');
      expect(received!.headers['x-api-key'], 'api-secret');
      expect(received!.url.query, isEmpty);
      expect(state.currentTrack!.title, 'Title');
      expect(state.progress, 42.5);
      expect(state.updatedAt, 1234);
    },
  );

  test(
    'sends supported commands as JSON and keeps credentials out of the URI',
    () async {
      http.Request? received;
      final client = MockClient((request) async {
        received = request;
        return http.Response('{"ok":true}', 200);
      });
      final service = LokalRemoteService(client: client);
      await service.sendCommand(
        LokalRemoteCredentials(
          origin: Uri.parse('http://192.168.1.20:3421'),
          remoteToken: 'remote-secret',
        ),
        LokalRemoteAction.seek,
        value: 99.25,
      );

      expect(received!.method, 'POST');
      expect(
        received!.url.toString(),
        'http://192.168.1.20:3421/api/remote/command',
      );
      expect(jsonDecode(received!.body), {'action': 'seek', 'value': 99.25});
      expect(received!.url.query, isEmpty);
      expect(received!.headers['x-remote-token'], 'remote-secret');
    },
  );

  test(
    'maps auth, unavailable and malformed responses to safe errors',
    () async {
      final credentials = LokalRemoteCredentials(
        origin: Uri.parse('http://host'),
      );
      for (final response in [
        http.Response('secret body', 401),
        http.Response('secret body', 503),
        http.Response('{"connected":true,"progress":"bad"}', 200),
      ]) {
        final service = LokalRemoteService(
          client: MockClient((_) async => response),
        );
        await expectLater(
          service.fetchState(credentials),
          throwsA(
            isA<LokalRemoteException>().having(
              (error) => error.message,
              'safe message',
              isNot(contains('secret body')),
            ),
          ),
        );
      }
    },
  );
}
