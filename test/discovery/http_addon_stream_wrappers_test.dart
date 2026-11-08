import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final client = MockClient((_) async => http.Response('{}', 200));
  final addon = DiscoveryAddon(
    DiscoveryHttp(client),
    endpoint: 'https://addon.example/a/test-token',
  );
  tearDownAll(client.close);

  test(
    'lastwave-compatible stream wrapper with direct FLAC plays as progressive',
    () {
      final audio = addon.parseStream({
        'stream': {
          'directUrl': 'https://cdn.example/audio/file.flac',
          'format': 'dash',
          'manifest': 'dash',
          'codec': 'flac',
          'quality': 'LOSSLESS',
        },
      });
      expect(audio.url.path, '/audio/file.flac');
      expect(audio.codec?.toLowerCase(), 'flac');
      expect(audio.quality, 'LOSSLESS');
    },
  );

  test('data wrapper with boolean no-manifest is allowed', () {
    final audio = addon.parseStream({
      'data': {'url': 'https://cdn.example/file.m4a', 'manifest': false},
    });
    expect(audio.url.path, '/file.m4a');
  });

  test('outer encrypted flags cannot be cleared by a stream wrapper', () {
    expect(
      () => addon.parseStream({
        'encrypted': true,
        'stream': {'url': 'https://cdn.example/file.flac'},
      }),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('inner encrypted flags cannot be cleared by outer or sibling', () {
    expect(
      () => addon.parseStream({
        'data': {'encrypted': true},
        'stream': {'url': 'https://cdn.example/file.flac'},
      }),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('a real DASH/MPD URL uses the DASH plan, not progressive audio', () {
    final resolved = addon.parseStream({
      'stream': {
        'url': 'https://cdn.example/audio/manifest.mpd',
        'format': 'dash',
      },
    });
    expect(resolved.dashMedia?.manifestUrl?.path, '/audio/manifest.mpd');
    expect(resolved.requiresStaging, isFalse);
  });

  test('a hybrid-only encrypted plan is rejected without a playable URL', () {
    expect(
      () => addon.parseStream({
        'stream': {
          'encrypted': true,
          'hybrid': {'cdnUrl': 'https://cdn.example/file'},
        },
      }),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('stream mint HTTP 502 is retried once with signing intact', () async {
    var attempts = 0;
    final signed = <String?>[];
    final transientClient = MockClient((request) async {
      attempts++;
      signed.add(request.headers['X-LW-Sign']);
      if (attempts == 1)
        return http.Response('Temporary upstream failure', 502);
      return http.Response(
        '{"url":"https://cdn.example/file.flac","format":"flac"}',
        200,
      );
    });
    addTearDown(transientClient.close);
    final signedAddon = DiscoveryAddon(
      DiscoveryHttp(transientClient),
      endpoint: 'https://addon.example/a/test-token',
      configId: 'selected-source',
      signingKey: 'unit-test-only-key',
    );
    final track = DiscoveryTrack(
      id: 'song',
      title: 'Song',
      artist: 'Artist',
      source: DiscoverySource.addon,
      addonBase: signedAddon.base,
      addonId: 'selected-source',
    );
    final audio = await signedAddon.resolve(track);
    expect(audio.url.path, '/file.flac');
    expect(attempts, 2);
    expect(signed.every((signature) => signature != null), isTrue);
  });

  test('explicit HLS metadata is rejected for a FLAC-looking URL', () {
    expect(
      () => addon.parseStream({
        'url': 'https://cdn.example/file.flac',
        'mediaType': 'application/vnd.apple.mpegurl',
      }),
      throwsA(isA<DiscoveryException>()),
    );
  });
}
