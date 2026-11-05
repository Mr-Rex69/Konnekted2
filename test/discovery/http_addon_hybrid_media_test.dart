import 'dart:io';
import 'dart:typed_data';

import 'package:flick/features/discovery/addon_hybrid_cenc.dart' as cenc;
import 'package:flick/features/discovery/addon_hybrid_media.dart';
import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_playback.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flick/src/rust/api/audio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _plan = {
  'cdnUrl': 'https://cdn.example/track.m4a',
  'initRange': {'start': 0, 'end': 11},
  'ranges': [
    {'start': 12, 'end': 15},
    {'start': 16, 'end': 19},
  ],
  'encrypted': true,
  'key': '00112233445566778899aabbccddeeff',
  'ivSize': 16,
};

Uint8List _box(String fourcc, List<int> payload) {
  final length = payload.length + 8;
  return Uint8List.fromList([
    (length >> 24) & 255, (length >> 16) & 255,
    (length >> 8) & 255, length & 255,
    ...fourcc.codeUnits,
    ...payload,
  ]);
}

void main() {
  test('signed hybrid-v1 stream contract is recognized without a direct URL', () {
    final addon = DiscoveryAddon(
      DiscoveryHttp(MockClient((_) async => http.Response('{}', 200))),
      endpoint: 'https://addon.example/a/example-token',
    );
    final audio = addon.parseStream({
      'encrypted': true,
      'format': 'dash',
      'data': {
        'stream': 'not-used',
        'hybrid': _plan,
      },
    });
    expect(audio.hybridPlan, isNotNull);
    expect(audio.hybridPlan!.encrypted, isTrue);
    expect(audio.length, 20);
    expect(audio.url.host, 'cdn.example');
  });

  test('hybrid plan cannot bypass DRM, private-host, key or size checks', () {
    final addon = DiscoveryAddon(
      DiscoveryHttp(MockClient((_) async => http.Response('{}', 200))),
      endpoint: 'https://addon.example/a/example-token',
    );
    for (final malformed in [
      {..._plan, 'key': ''},
      {..._plan, 'cdnUrl': 'https://127.0.0.1/private'},
      {..._plan, 'cdnUrl': 'http://cdn.example/not-secure'},
      {..._plan, 'ranges': []},
      {..._plan, 'ivSize': 3},
      {..._plan, 'constantIv': 'invalid-base64!'},
      {..._plan, 'ranges': [
        {'start': 12, 'end': 150000000},
      ]},
    ]) {
      expect(
        () => addon.parseStream({'encrypted': true, 'hybrid': malformed}),
        throwsA(isA<DiscoveryException>()),
      );
    }
    expect(
      () => addon.parseStream({'drm': true, 'hybrid': _plan}),
      throwsA(isA<DiscoveryException>()),
    );
    expect(
      () => addon.parseStream({
        'stream': {'hybrid': _plan, 'headers': {'X-Secret': 'no'}},
      }),
      throwsA(isA<DiscoveryException>()),
    );
    // An encryption marker is only allowed with a complete hybrid plan.
    expect(
      () => addon.parseStream({'encrypted': true,
        'url': 'https://cdn.example/file.flac'}),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('encryption key and arbitrary CDN hosts never become media headers', () async {
    final plan = AddonHybridPlan.parse({..._plan, 'encrypted': false})!;
    final ranges = <String>[];
    final client = MockClient((request) async {
      final range = request.headers['Range'];
      ranges.add(range ?? '');
      expect(request.headers['X-LW-Sign'], isNull);
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['Accept-Encoding'], 'identity');
      final start = range == 'bytes=0-11' ? 0 : range == 'bytes=12-15' ? 12 : 16;
      final end = start == 0 ? 11 : start + 3;
      final bytes = Uint8List.fromList(
        List.generate(end - start + 1, (i) => start + i),
      );
      return http.Response.bytes(bytes, 206, headers: {
        'content-range': 'bytes ' + start.toString() + '-' +
            end.toString() + '/20',
      });
    });
    addTearDown(client.close);
    final received = <int>[];
    await downloadAddonHybrid(
      DiscoveryHttp(client), plan,
      maxBytes: 64,
      timeout: const Duration(seconds: 4),
      onData: received.addAll,
    );
    expect(ranges, containsAll([
      'bytes=0-11', 'bytes=12-15', 'bytes=16-19',
    ]));
    expect(received, List.generate(20, (i) => i));
  });

  test('native-verified hybrid staging produces a playable local file', () async {
    final root = await Directory.systemTemp.createTemp('hybrid_addon_test');
    addTearDown(() async => root.delete(recursive: true));
    final fixture = Uint8List.fromList([
      0, 0, 0, 12, 102, 116, 121, 112, 105, 115, 111, 109,
      109, 111, 111, 102, 0, 0, 0, 8,
    ]);
    final client = MockClient((request) async {
      final header = request.headers['Range']!;
      final part = header.substring(6).split('-');
      final start = int.parse(part[0]);
      final end = int.parse(part[1]);
      return http.Response.bytes(
        fixture.sublist(start, end + 1), 206,
        headers: {
          'content-range': 'bytes ' + start.toString() + '-' +
              end.toString() + '/20',
        },
      );
    });
    addTearDown(client.close);
    final plan = AddonHybridPlan.parse({..._plan, 'encrypted': false})!;
    final audio = ResolvedDiscoveryAudio(
      plan.cdnUrl, hybridPlan: plan, length: plan.outputLength,
    );
    final track = DiscoveryTrack(
      id: 'hybrid-test',
      title: 'Hybrid fixture',
      artist: 'Fixture',
      source: DiscoverySource.addon,
      addonBase: Uri.parse('https://addon.example/a/example-token'),
    );
    var probes = 0;
    final cache = DiscoveryPlaybackCache(
      http: DiscoveryHttp(client),
      directory: () async => root,
      probe: (path) async {
        probes++;
        expect(await File(path).readAsBytes(), fixture);
        return const AudioProbeFormat(
          sampleRate: 44100, channels: 2, bitsPerSample: 16,
        );
      },
    );
    final song = await cache.prepare(track, audio);
    expect(probes, 1);
    expect(song.filePath, endsWith('.m4a'));
    expect(await File(song.filePath!).readAsBytes(), fixture);
  });

  test('nonmatching CDN Content-Range fails before writing audio', () async {
    final plan = AddonHybridPlan.parse({..._plan, 'encrypted': false})!;
    final client = MockClient((_) async =>
        http.Response.bytes(Uint8List(12), 206, headers: {
          'content-range': 'bytes 100-111/112',
        }));
    addTearDown(client.close);
    await expectLater(
      downloadAddonHybrid(
        DiscoveryHttp(client), plan,
        maxBytes: 128,
        timeout: const Duration(seconds: 2),
        onData: (_) {},
      ),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('AES-128-CTR decrypts the standardized NIST test vector', () {
    final key = cenc.importContentKey('2b7e151628aed2a6abf7158809cf4f3c');
    final iv = cenc.importContentKey('f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff');
    final bytes = Uint8List.fromList([
      0x87, 0x4d, 0x61, 0x91, 0xb6, 0x20, 0xe3, 0x26,
      0x1b, 0xef, 0x68, 0x64, 0x99, 0x0d, 0xb6, 0xce,
    ]);
    cenc.decryptSample(bytes, 0, bytes.length, iv, const [], key);
    expect(bytes, [
      0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
      0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
    ]);
  });

  test('CENC removes pssh metadata after local decryption', () {
    final bytes = Uint8List.fromList([0, 0, 0, 8, 112, 115, 115, 104]);
    cenc.neutralizePssh(bytes, 0, bytes.length);
    expect(String.fromCharCodes(bytes.sublist(4)), 'free');
  });

  test('CENC init patch exposes mp4a, neutralizes sinf and pssh', () {
    final frma = _box('frma', 'mp4a'.codeUnits);
    final schm = _box('schm', [0, 0, 0, 0, ...'cenc'.codeUnits]);
    final tenc = _box('tenc', [
      0, 0, 0, 0, 0, 0, 1, 16, ...List.filled(16, 0),
    ]);
    final sinf = _box('sinf', [
      ...frma, ...schm, ..._box('schi', tenc),
    ]);
    final entry = _box('enca', [...List.filled(28, 0), ...sinf]);
    final stsd = _box('stsd', [0, 0, 0, 0, 0, 0, 0, 1, ...entry]);
    final moov = _box('moov', [
      ..._box('trak', [
        ..._box('mdia', [
          ..._box('minf', [
            ..._box('stbl', stsd),
          ]),
        ]),
      ]),
      ..._box('pssh', []),
    ]);
    final init = Uint8List.fromList([
      ..._box('ftyp', 'isom'.codeUnits),
      ...moov,
    ]);
    final tencInfo = cenc.patchInitSegment(init);
    expect(tencInfo.ivSize, 16);
    expect(String.fromCharCodes(init).contains('enca'), isFalse);
    expect(String.fromCharCodes(init).contains('sinf'), isFalse);
    expect(String.fromCharCodes(init).contains('pssh'), isFalse);
    expect(String.fromCharCodes(init).contains('mp4a'), isTrue);
  });

  test('CENC decrypts an MP4 moof/mdat sample with senc IV', () {
    final iv = cenc.importContentKey('f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff');
    final key = cenc.importContentKey('2b7e151628aed2a6abf7158809cf4f3c');
    final encrypted = [
      0x87, 0x4d, 0x61, 0x91, 0xb6, 0x20, 0xe3, 0x26,
      0x1b, 0xef, 0x68, 0x64, 0x99, 0x0d, 0xb6, 0xce,
    ];
    Uint8List moof(int dataOffset) => _box('moof', [
      ..._box('traf', [
        ..._box('tfhd', [0, 0, 0, 0, 0, 0, 0, 1]),
        ..._box('trun', [
          0, 0, 2, 1, 0, 0, 0, 1,
          (dataOffset >> 24) & 255, (dataOffset >> 16) & 255,
          (dataOffset >> 8) & 255, dataOffset & 255,
          0, 0, 0, 16,
        ]),
        ..._box('senc', [0, 0, 0, 0, 0, 0, 0, 1, ...iv]),
      ]),
    ]);
    final offset = moof(0).length + 8;
    final segment = Uint8List.fromList([
      ...moof(offset), ..._box('mdat', encrypted),
    ]);
    cenc.decryptSegment(segment, key, 16, Uint8List(0), 0);
    expect(segment.sublist(offset), [
      0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
      0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
    ]);
    expect(String.fromCharCodes(segment).contains('senc'), isFalse);
  });

  test('hybrid sidx gap is retained for contiguous CDN fragments', () {
    final plan = AddonHybridPlan.parse({..._plan,
      'initRange': {'start': 0, 'end': 3},
    })!;
    expect(plan.expandedInitRange, (start: 0, end: 11));
    expect(plan.outputLength, 20);
  });
}
