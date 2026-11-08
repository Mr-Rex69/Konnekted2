import 'dart:async';
import 'dart:convert';

import 'package:flick/features/discovery/discovery_controller.dart';
import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_registry.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const alpha = DiscoveryAddonConfig(
  id: 'alpha',
  endpoint: 'https://alpha.example/private-path',
  label: 'Home music',
  token: 'alpha-fixture-token',
  enabled: true,
);
const beta = DiscoveryAddonConfig(
  id: 'beta',
  endpoint: 'https://beta.example',
  label: 'Second library',
  token: 'beta-fixture-token',
  enabled: true,
);
const disabled = DiscoveryAddonConfig(
  id: 'disabled',
  endpoint: 'https://disabled.example',
);
const manifest = {
  'id': 'fixture',
  'resources': ['search', 'stream'],
};
const rows = {
  'tracks': [
    {'id': 'same-id', 'title': 'Fixture recording', 'artist': 'Fixture artist'},
  ],
};
http.Response jsonResponse(Object data) => http.Response(jsonEncode(data), 200);

DiscoveryTrack pinned({String? id = 'alpha', String? endpoint}) =>
    DiscoveryTrack(
      id: 'same-id',
      title: 'Fixture recording',
      artist: 'Fixture artist',
      source: DiscoverySource.addon,
      addonId: id,
      addonBase: Uri.parse(endpoint ?? alpha.endpoint),
    );

void main() {
  test(
    'search order is saved order, not completion order; tokens stay isolated',
    () async {
      final slow = Completer<http.Response>();
      final secondStarted = Completer<void>();
      final client = MockClient((request) async {
        expect(request.url.pathSegments.last, 'search');
        expect(request.url.queryParameters['q'], 'song');
        if (request.url.host == 'alpha.example') {
          expect(request.headers['Authorization'], 'Bearer ${alpha.token}');
          return slow.future;
        }
        expect(request.url.host, 'beta.example');
        expect(request.headers['Authorization'], 'Bearer ${beta.token}');
        secondStarted.complete();
        return jsonResponse(rows);
      });
      addTearDown(client.close);
      final pending = searchDiscovery(
        DiscoveryHttp(client),
        const DiscoverySettings(addons: [alpha, disabled, beta]),
        'song',
      );
      await secondStarted.future;
      slow.complete(jsonResponse(rows));
      final result = await pending;
      expect(result.errors, isEmpty);
      expect(result.tracks.map((t) => t.addonId), ['alpha', 'beta']);
      expect(result.tracks.map((t) => t.sourceName), [
        'Home music',
        'Second library',
      ]);
      // Identical provider IDs are separate recordings, not incorrectly deduped.
      expect(result.tracks.map((t) => t.key).toSet(), hasLength(2));
    },
  );

  test(
    'partial source failure preserves other results and redacts transport details',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'alpha.example') {
          throw http.ClientException(
            'private-path ${alpha.token}',
            request.url,
          );
        }
        expect(request.url.host, 'beta.example');
        return jsonResponse(rows);
      });
      addTearDown(client.close);
      final result = await searchDiscovery(
        DiscoveryHttp(client),
        const DiscoverySettings(addons: [alpha, beta]),
        'song',
      );
      expect(result.tracks.single.addonId, 'beta');
      expect(result.errors.single, startsWith('Home music:'));
      expect(result.errors.single, isNot(contains('private-path')));
      expect(result.errors.single, isNot(contains(alpha.token)));
    },
  );

  test(
    'search row identity comes from local config, not remote claims',
    () async {
      final client = MockClient(
        (_) async => jsonResponse({
          'tracks': [
            {
              'id': 'same-id',
              'title': 'Fixture recording',
              'addonId': 'beta',
              'sourceName': 'Forged library',
              'addonBase': beta.endpoint,
            },
          ],
        }),
      );
      addTearDown(client.close);
      final result = await searchDiscovery(
        DiscoveryHttp(client),
        const DiscoverySettings(addons: [alpha]),
        'song',
      );
      expect(result.tracks.single.addonId, 'alpha');
      expect(result.tracks.single.addonBase.toString(), alpha.endpoint);
      expect(result.tracks.single.sourceName, alpha.label);
    },
  );

  test('selecting a result resolves only its own enabled addon', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.url.host, 'beta.example');
      expect(request.headers['Authorization'], 'Bearer ${beta.token}');
      return jsonResponse(
        request.url.path.endsWith('manifest.json')
            ? manifest
            : {'url': 'https://cdn.example/audio.flac'},
      );
    });
    addTearDown(client.close);
    final registry = DiscoverySourceRegistry(
      DiscoveryHttp(client),
      const DiscoverySettings(addons: [alpha, disabled, beta]),
    );
    final audio = await registry.resolve(
      pinned(id: 'beta', endpoint: beta.endpoint),
    );
    expect(audio.url.toString(), 'https://cdn.example/audio.flac');
    expect(requests.map((r) => r.url.path), [
      '/stream/same-id',
    ]);
  });

  test(
    'disabled, removed, replaced, and unbound rows fail before network traffic',
    () async {
      final client = MockClient(
        (_) async => fail('Stale source contacted a server'),
      );
      addTearDown(client.close);
      final disabledAlpha = DiscoveryAddonConfig(
        id: 'alpha',
        endpoint: alpha.endpoint,
      );
      final replacement = DiscoveryAddonConfig(
        id: 'replacement',
        endpoint: alpha.endpoint,
        enabled: true,
      );
      const editedAlpha = DiscoveryAddonConfig(
        id: 'alpha',
        endpoint: 'https://new.example',
        enabled: true,
      );
      for (final configs in [
        [disabledAlpha, beta],
        [beta],
        [replacement, beta],
        [editedAlpha, beta],
      ]) {
        await expectLater(
          DiscoverySourceRegistry(
            DiscoveryHttp(client),
            DiscoverySettings(addons: configs),
          ).resolve(pinned()),
          throwsA(isA<DiscoveryException>()),
        );
      }
      final registry = DiscoverySourceRegistry(
        DiscoveryHttp(client),
        const DiscoverySettings(addons: [alpha]),
      );
      for (final id in [null, '', 'remote-forged-id']) {
        await expectLater(
          registry.resolve(pinned(id: id)),
          throwsA(isA<DiscoveryException>()),
        );
      }
      await expectLater(
        registry.resolve(
          const DiscoveryTrack(
            id: 'abcdefghijk',
            title: 'Catalog row',
            artist: 'Artist',
            source: DiscoverySource.youtubeMusic,
          ),
        ),
        throwsA(isA<DiscoveryException>()),
      );
    },
  );

  test(
    'a failed pinned source never silently falls back to another recording',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        expect(request.url.host, 'alpha.example');
        return http.Response('private error payload', 503);
      });
      addTearDown(client.close);
      await expectLater(
        DiscoverySourceRegistry(
          DiscoveryHttp(client),
          const DiscoverySettings(addons: [alpha, beta]),
        ).resolve(pinned()),
        throwsA(isA<DiscoveryException>()),
      );
      expect(requests, hasLength(2));
    },
  );

  test('cancelled resolution aborts the selected stream without contacting another addon', () async {
    final manifestRequested = Completer<void>();
    final response = Completer<http.Response>();
    final cancel = Completer<void>();
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.host, 'alpha.example');
      expect(request.url.pathSegments.last, 'same-id');
      manifestRequested.complete();
      return response.future;
    });
    addTearDown(client.close);
    final resolution = DiscoverySourceRegistry(
      DiscoveryHttp(client),
      const DiscoverySettings(addons: [alpha, beta]),
    ).resolve(pinned(), cancel: cancel.future);
    final assertion = expectLater(
      resolution,
      throwsA(isA<DiscoveryException>()),
    );
    await manifestRequested.future;
    cancel.complete();
    response.complete(jsonResponse(manifest));
    await assertion;
    expect(requests, 1);
  });

  test(
    'reordered settings change result order without changing source identity',
    () async {
      final client = MockClient((_) async => jsonResponse(rows));
      addTearDown(client.close);
      final first = await searchDiscovery(
        DiscoveryHttp(client),
        const DiscoverySettings(addons: [alpha, beta]),
        'song',
      );
      final second = await searchDiscovery(
        DiscoveryHttp(client),
        const DiscoverySettings(addons: [beta, alpha]),
        'song',
      );
      expect(second.tracks.map((t) => t.addonId), ['beta', 'alpha']);
      expect(second.tracks.last.key, first.tracks.first.key);
      expect(second.tracks.first.key, first.tracks.last.key);
    },
  );
}
