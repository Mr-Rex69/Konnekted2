import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flick/features/discovery/addon_dash_media.dart';
import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_playback.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flick/src/rust/api/audio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const sampleMpd = '<MPD type="static">'
    '<Period><AdaptationSet mimeType="audio/mp4">'
    '<Representation id="music" bandwidth="1411200">'
    '<SegmentTemplate initialization="https://cdn.example/init.m4a" '
    'media="https://cdn.example/audio-\$Number\$.m4s" startNumber="1" timescale="44100">'
    '<SegmentTimeline><S d="44100" r="1"/></SegmentTimeline>'
    '</SegmentTemplate>'
    '</Representation></AdaptationSet></Period></MPD>';

DiscoveryAddon testAddon() => DiscoveryAddon(
  DiscoveryHttp(MockClient((_) async => http.Response('{}', 200))),
  endpoint: 'https://addon.example/a/example',
);

void main() {
  test('default DASH labels do not reject direct opaque signed media', () {
    final parsed = testAddon().parseStream({
      'url': 'https://cdn.example/proxy/audio?signature=example',
      'format': 'dash',
      'manifest': 'dash',
    });
    expect(parsed.url.path, '/proxy/audio');
    expect(parsed.requiresStaging, isTrue);
    expect(parsed.dashMedia, isNull);
  });

  test('default DASH labels do not reject a direct FLAC URL', () {
    final parsed = testAddon().parseStream({
      'stream': {
        'url': 'https://cdn.example/audio.flac?signature=example',
        'format': 'dash',
        'manifest': 'dash',
      },
    });
    expect(parsed.url.path, '/audio.flac');
    expect(parsed.dashMedia, isNull);
    expect(parsed.requiresStaging, isFalse);
  });

  test('a real inline MPD is accepted even with no direct URL', () {
    final parsed = testAddon().parseStream({
      'manifestXml': sampleMpd,
      'format': 'dash',
      'manifest': 'dash',
    });
    expect(parsed.dashMedia, isNotNull);
    expect(parsed.dashMedia!.inlineXml, sampleMpd);
  });

  test('LastWave dataUrl base64 manifest is accepted', () {
    final parsed = testAddon().parseStream({
      'dataUrl': 'data:application/dash+xml;base64,${base64.encode(utf8.encode(sampleMpd))}',
      'format': 'dash',
    });
    expect(parsed.dashMedia!.inlineXml, sampleMpd);
  });

  test('a recognized FLAC URL outranks a sibling inline DASH MPD', () {
    final parsed = testAddon().parseStream({
      'directUrl': 'https://cdn.example/audio.flac',
      'manifestXml': sampleMpd,
      'format': 'dash',
    });
    expect(parsed.dashMedia, isNull);
    expect(parsed.url.path, '/audio.flac');
  });

  test('remote .mpd is represented as a DASH source, not progressive', () {
    final parsed = testAddon().parseStream({
      'url': 'https://cdn.example/manifest.mpd?signature=example',
      'format': 'dash',
    });
    expect(parsed.dashMedia!.manifestUrl!.path, '/manifest.mpd');
  });

  test('parse MPD Number SegmentTimeline and select audio representation', () {
    final plan = parseAddonDashManifest(
      sampleMpd,
      manifestBase: Uri.parse('https://addon.example/a/test'),
      addonBase: Uri.parse('https://addon.example/a/test'),
    );
    expect(plan.initUrl.toString(), 'https://cdn.example/init.m4a');
    expect(plan.segments.map((u) => u.toString()), [
      'https://cdn.example/audio-1.m4s',
      'https://cdn.example/audio-2.m4s',
    ]);
  });

  test('MPD with ContentProtection must not bypass encryption checks', () {
    final protected = sampleMpd.replaceFirst(
      '<Representation',
      '<ContentProtection schemeIdUri="urn:uuid:test"/>'
      '<Representation',
    );
    expect(
      () => parseAddonDashManifest(
        protected,
        manifestBase: Uri.parse('https://addon.example/a/test'),
        addonBase: Uri.parse('https://addon.example/a/test'),
      ),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('MPD cannot refer to private, HTTP or loopback CDN segments', () {
    for (final bad in [
      'https://127.0.0.1/',
      'http://cdn.example/',
      'https://localhost/',
    ]) {
      expect(
        () => parseAddonDashManifest(
          sampleMpd.replaceAll('https://cdn.example/', bad),
          manifestBase: Uri.parse('https://addon.example/a/test'),
          addonBase: Uri.parse('https://addon.example/a/test'),
        ),
        throwsA(isA<DiscoveryException>()),
      );
    }
  });

  test('DASH downloader assembles ordered fMP4 segments and stages native probe',
      () async {
    final root = await Directory.systemTemp.createTemp('addon_mpd_test_');
    addTearDown(() async => root.delete(recursive: true));
    const init = [
      0, 0, 0, 12, 102, 116, 121, 112, 105, 115, 111, 109,
    ];
    const first = [0, 0, 0, 8, 109, 111, 111, 102];
    const second = [0, 0, 0, 8, 109, 100, 97, 116];
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add(request.url.toString());
      final bytes = request.url.path.endsWith('/init.m4a')
          ? init : request.url.path.endsWith('/audio-1.m4s')
          ? first : second;
      return http.Response.bytes(bytes, 200);
    });
    addTearDown(client.close);
    final track = DiscoveryTrack(
      id: 'mpd-example',
      title: 'DASH test',
      artist: 'Artist',
      source: DiscoverySource.addon,
      addonBase: Uri.parse('https://addon.example/a/example'),
    );
    final dash = AddonDashMedia(
      manifestBase: Uri.parse('https://addon.example/a/example'),
      inlineXml: sampleMpd,
    );
    final cache = DiscoveryPlaybackCache(
      http: DiscoveryHttp(client),
      directory: () async => root,
      probe: (path) async {
        expect(await File(path).readAsBytes(), [
          ...init, ...first, ...second,
        ]);
        return const AudioProbeFormat(
          sampleRate: 44100, channels: 2, bitsPerSample: 16,
        );
      },
    );
    final audio = ResolvedDiscoveryAudio(dash.manifestBase, dashMedia: dash);
    final song = await cache.prepare(track, audio);
    expect(song.filePath, endsWith('.m4a'));
    expect(seen, containsAll([
      'https://cdn.example/init.m4a',
      'https://cdn.example/audio-1.m4s',
      'https://cdn.example/audio-2.m4s',
    ]));
    expect(await File(song.filePath!).readAsBytes(), [
      ...init, ...first, ...second,
    ]);
  });

  test('MPD remote fetch requires genuine XML', () async {
    final client = MockClient((_) async => http.Response('not an MPD', 200));
    addTearDown(client.close);
    await expectLater(
      downloadAddonDash(
        DiscoveryHttp(client),
        AddonDashMedia(
          manifestBase: Uri.parse('https://cdn.example/track.mpd'),
          manifestUrl: Uri.parse('https://cdn.example/track.mpd'),
        ),
        addonBase: Uri.parse('https://addon.example/a/example'),
        maxBytes: 1024,
        timeout: const Duration(seconds: 3),
        onData: (_) {},
      ),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('cleartext media and HLS MIME remain rejected', () {
    expect(() => testAddon().parseStream({
      'url': 'http://cdn.example/file.flac',
    }), throwsA(isA<DiscoveryException>()));
    expect(() => testAddon().parseStream({
      'url': 'https://cdn.example/file.flac',
      'mediaType': 'application/vnd.apple.mpegurl',
    }), throwsA(isA<DiscoveryException>()));
  });
}
