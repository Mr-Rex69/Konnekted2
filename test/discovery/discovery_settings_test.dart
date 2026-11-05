import 'dart:async';
import 'dart:convert';

import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = 'konnekted.discovery.sources.v1';
const _invalidRecordMessage =
    'Saved source settings are invalid. Reconfigure sources to continue.';
const _first = DiscoveryAddonConfig(
  id: 'first',
  endpoint: 'https://first.example/fixture-private-path',
  label: 'First library',
  token: 'fixture-token-one',
  enabled: true,
);
const _second = DiscoveryAddonConfig(
  id: 'second',
  endpoint: 'https://second.example',
  token: 'fixture-token-two',
);
const _third = DiscoveryAddonConfig(
  id: 'third',
  endpoint: 'https://third.example',
  label: 'Third library',
  enabled: true,
);

Map<String, Object?> _addonRecord([
  Map<String, Object?> overrides = const {},
]) => {
  'id': 'fixture-addon',
  'endpoint': 'https://addon.example/fixture-private-path',
  'label': '',
  'token': 'fixture-token',
  'enabled': false,
  ...overrides,
};

Map<String, Object?> _v1([Map<String, Object?> overrides = const {}]) => {
  'version': 1,
  'youtubeEnabled': true,
  'addonEnabled': true,
  'endpoint': 'https://addon.example/fixture-private-path',
  'token': 'fixture-token',
  ...overrides,
};

Map<String, Object?> _v2([Map<String, Object?> overrides = const {}]) => {
  'version': 2,
  'youtubeEnabled': false,
  'addons': [_addonRecord()],
  ...overrides,
};

List<DiscoveryAddonConfig> _addons(int count) => List.generate(
  count,
  (index) => DiscoveryAddonConfig(
    id: 'addon-$index',
    endpoint: 'https://addon-$index.example',
  ),
);

// Keep the plugin's existing in-memory mock, adding only observable writes and
// an injectable pending/failing write to check the store's completion boundary.
class _ControlledStorage extends FlutterSecureStorage {
  int writeAttempts = 0;
  Completer<void>? writeGate;
  bool failReads = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (failReads) throw StateError('fixture-token storage read failure');
    return super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeAttempts++;
    final gate = writeGate;
    if (gate != null) await gate.future;
    await super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControlledStorage storage;
  late DiscoverySettingsStore store;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = _ControlledStorage();
    store = DiscoverySettingsStore(storage: storage);
  });

  group('DiscoveryAddonConfig', () {
    test('defaults off and display names never fall back to credentials', () {
      const addon = DiscoveryAddonConfig(
        id: 'fixture-id',
        endpoint: 'https://addon.example/fixture-private-path',
        token: 'fixture-token',
      );
      expect(addon.enabled, isFalse);
      expect(addon.label, isEmpty);
      expect(addon.displayName, 'Music addon');
      expect(_first.displayName, 'First library');
      expect(
        const DiscoveryAddonConfig(
          id: 'fixture',
          endpoint: 'https://addon.example',
          label: '   ',
        ).displayName,
        'Music addon',
      );
    });

    test('validation normalizes endpoint and trims label and token', () {
      final addon = const DiscoveryAddonConfig(
        id: 'Fixture_1-',
        endpoint: '  HTTPS://ADDON.EXAMPLE:443/library/manifest.json/  ',
        label: '  My library  ',
        token: '  fixture-token  ',
        enabled: true,
      ).validated();
      expect(addon.id, 'Fixture_1-');
      expect(addon.endpoint, 'https://addon.example/library');
      expect(addon.label, 'My library');
      expect(addon.displayName, 'My library');
      expect(addon.token, 'fixture-token');
      expect(addon.enabled, isTrue);
    });

    test('accepts maximum field lengths and an optional empty token', () {
      final addon = DiscoveryAddonConfig(
        id: 'a' * 80,
        endpoint: 'https://addon.example',
        label: 'b' * 80,
        token: 'c' * 4096,
      ).validated();
      expect(addon.id, hasLength(80));
      expect(addon.label, hasLength(80));
      expect(addon.token, hasLength(4096));
      expect(
        const DiscoveryAddonConfig(
          id: 'a',
          endpoint: 'https://addon.example',
        ).validated().token,
        isEmpty,
      );
    });

    test('rejects invalid IDs, labels, and tokens even when disabled', () {
      final invalid = <DiscoveryAddonConfig>[
        for (final id in ['', 'a' * 81, 'has space', 'a/b', 'a\n', 'é'])
          DiscoveryAddonConfig(id: id, endpoint: 'https://addon.example'),
        for (final label in [
          'a' * 81,
          'a\n',
          '\tname',
          'a\x00',
          'a\x7f',
          'a\x85',
        ])
          DiscoveryAddonConfig(
            id: 'fixture',
            endpoint: 'https://addon.example',
            label: label,
          ),
        for (final token in [
          'a' * 4097,
          'fixture token',
          'fixture\r\nInjected:value',
          'fixture\ttoken',
          'fixture\x00token',
          'fixture\x7ftoken',
          'fixture\x85token',
          'fixture☃token',
        ])
          DiscoveryAddonConfig(
            id: 'fixture',
            endpoint: 'https://addon.example',
            token: token,
          ),
      ];
      for (final addon in invalid) {
        expect(addon.validated, throwsA(isA<DiscoveryException>()));
      }
    });

    test('rejects malformed or unsafe addon URLs', () {
      for (final endpoint in [
        '',
        'addon.example',
        '/relative',
        'http://addon.example',
        'https://',
        'https://fixture-user:fixture-token@addon.example',
        'https://addon.example?token=fixture-token',
        'https://addon.example#fixture-token',
        'https://addon.example/a/../b',
        'https://addon.example/%2e%2e/b',
        'https://addon.example/a\\b',
        'https://addon.example/a%5cb',
        'https://addon.example/fixture path',
        'https://addon.example/fixture\npath',
        'https://addon.example:0',
        'https://addon.example:invalid',
        'https://addon.example/${'a' * 8192}',
      ]) {
        expect(
          () => DiscoveryAddonConfig(
            id: 'fixture',
            endpoint: endpoint,
          ).validated(),
          throwsA(isA<DiscoveryException>()),
        );
      }
    });

    test('generated IDs are distinct hex IDs accepted by validation', () {
      final ids = List.generate(64, (_) => DiscoveryAddonConfig.createId());
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(
          DiscoveryAddonConfig(
            id: id,
            endpoint: 'https://addon.example',
          ).validated().id,
          id,
        );
      }
    });
  });

  group('DiscoverySettings', () {
    test('defaults off and active addons keep their saved order', () {
      const defaults = DiscoverySettings();
      expect(defaults.youtubeEnabled, isFalse);
      expect(defaults.addons, isEmpty);
      expect(defaults.activeAddons, isEmpty);
      expect(defaults.hasSource, isFalse);
      expect(const DiscoverySettings(addons: [_second]).hasSource, isFalse);
      expect(const DiscoverySettings(youtubeEnabled: true).hasSource, isTrue);

      final settings = const DiscoverySettings(
        addons: [_third, _second, _first],
      ).validated();
      expect(settings.hasSource, isTrue);
      expect(settings.addons.map((addon) => addon.id), [
        'third',
        'second',
        'first',
      ]);
      expect(settings.activeAddons.map((addon) => addon.id), [
        'third',
        'first',
      ]);
    });

    test('rejects duplicate IDs and normalized endpoints', () {
      for (final duplicate in [
        const DiscoveryAddonConfig(
          id: 'first',
          endpoint: 'https://different.example',
        ),
        const DiscoveryAddonConfig(
          id: 'different-id',
          endpoint:
              ' HTTPS://FIRST.EXAMPLE:443/fixture-private-path/manifest.json/ ',
        ),
      ]) {
        expect(
          () => DiscoverySettings(addons: [_first, duplicate]).validated(),
          throwsA(isA<DiscoveryException>()),
        );
      }
    });

    test(
      'permits eight addons and rejects nine including disabled entries',
      () {
        expect(DiscoverySettings.maxAddons, 8);
        expect(
          DiscoverySettings(addons: _addons(8)).validated().addons,
          hasLength(8),
        );
        expect(
          () => DiscoverySettings(addons: _addons(9)).validated(),
          throwsA(isA<DiscoveryException>()),
        );
      },
    );

    test('validation produces a stable snapshot of the input list', () {
      final input = [_first, _second];
      final settings = DiscoverySettings(addons: input).validated();
      input.clear();
      expect(settings.addons.map((addon) => addon.id), ['first', 'second']);
      expect(() => settings.addons.clear(), throwsUnsupportedError);
    });
  });

  group('DiscoverySettingsStore', () {
    test('missing record defaults off without writing', () async {
      final settings = await store.load();
      expect(settings.youtubeEnabled, isFalse);
      expect(settings.addons, isEmpty);
      expect(settings.hasSource, isFalse);
      expect(storage.writeAttempts, 0);
      expect(await storage.readAll(), isEmpty);
    });

    for (final enabled in [true, false]) {
      test('v1 migrates enabled=$enabled without a silent write', () async {
        final raw = jsonEncode(_v1({'addonEnabled': enabled}));
        FlutterSecureStorage.setMockInitialValues({_key: raw});

        final settings = await store.load();
        final addon = settings.addons.single;
        expect(settings.youtubeEnabled, isTrue);
        expect(addon.id, 'legacy-addon');
        expect(addon.endpoint, 'https://addon.example/fixture-private-path');
        expect(addon.token, 'fixture-token');
        expect(addon.enabled, enabled);
        expect(addon.label, isEmpty);
        expect(addon.displayName, 'Music addon');
        expect(settings.activeAddons, hasLength(enabled ? 1 : 0));
        expect((await store.load()).addons.single.id, 'legacy-addon');
        expect(storage.writeAttempts, 0);
        expect(await storage.read(key: _key), raw);

        await store.save(settings);
        final saved = jsonDecode((await storage.read(key: _key))!) as Map;
        expect(saved['version'], 2);
        expect(saved['addons'], [
          _addonRecord({'id': 'legacy-addon', 'enabled': enabled}),
        ]);
        expect(storage.writeAttempts, 1);
        expect(await storage.readAll(), hasLength(1));
        final restored = await DiscoverySettingsStore().load();
        expect(restored.addons.single.id, 'legacy-addon');
        expect(restored.addons.single.enabled, enabled);
        expect(restored.youtubeEnabled, isTrue);
      });
    }

    test(
      'v1 preserves disabled configuration when all sources are off',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          _key: jsonEncode(
            _v1({'youtubeEnabled': false, 'addonEnabled': false}),
          ),
        });
        final settings = await store.load();
        expect(settings.hasSource, isFalse);
        expect(settings.addons.single.token, 'fixture-token');
        expect(settings.addons.single.enabled, isFalse);
        expect(storage.writeAttempts, 0);
      },
    );

    test('v1 with no endpoint or token migrates to an empty list', () async {
      for (final youtubeEnabled in [false, true]) {
        FlutterSecureStorage.setMockInitialValues({
          _key: jsonEncode(
            _v1({
              'youtubeEnabled': youtubeEnabled,
              'endpoint': '',
              'token': '',
            }),
          ),
        });
        final settings = await store.load();
        expect(settings.youtubeEnabled, youtubeEnabled);
        expect(settings.addons, isEmpty);
        expect(settings.hasSource, youtubeEnabled);
      }
      expect(storage.writeAttempts, 0);
    });

    test('v1 and v2 normalize saved endpoints and tokens on load', () async {
      for (final record in [
        _v1({
          'endpoint': ' https://addon.example/library/manifest.json/ ',
          'token': ' fixture-token ',
        }),
        _v2({
          'addons': [
            _addonRecord({
              'endpoint': ' https://addon.example/library/manifest.json/ ',
              'token': ' fixture-token ',
            }),
          ],
        }),
      ]) {
        final raw = jsonEncode(record);
        FlutterSecureStorage.setMockInitialValues({_key: raw});
        final settings = await store.load();
        expect(
          settings.addons.single.endpoint,
          'https://addon.example/library',
        );
        expect(settings.addons.single.token, 'fixture-token');
        expect(await storage.read(key: _key), raw);
      }
      expect(storage.writeAttempts, 0);
    });

    test(
      'v2 round-trips every field, order, removal, and an empty reload',
      () async {
        await store.save(
          const DiscoverySettings(
            youtubeEnabled: true,
            addons: [_third, _second, _first],
          ),
        );
        final saved = jsonDecode((await storage.read(key: _key))!) as Map;
        expect(saved, {
          'version': 2,
          'youtubeEnabled': true,
          'addons': [
            for (final addon in [_third, _second, _first])
              {
                'id': addon.id,
                'endpoint': addon.endpoint,
                'label': addon.label,
                'token': addon.token,
                'enabled': addon.enabled,
              },
          ],
        });
        expect((await storage.readAll()).keys, [_key]);

        final restored = await DiscoverySettingsStore().load();
        expect(restored.youtubeEnabled, isTrue);
        expect(restored.addons.map((addon) => addon.id), [
          'third',
          'second',
          'first',
        ]);
        expect(restored.addons.map((addon) => addon.endpoint), [
          _third.endpoint,
          _second.endpoint,
          _first.endpoint,
        ]);
        expect(restored.addons.map((addon) => addon.label), [
          _third.label,
          _second.label,
          _first.label,
        ]);
        expect(restored.addons.map((addon) => addon.token), [
          _third.token,
          _second.token,
          _first.token,
        ]);
        expect(restored.addons.map((addon) => addon.enabled), [
          true,
          false,
          true,
        ]);

        await store.save(
          DiscoverySettings(addons: [restored.addons[1], restored.addons[0]]),
        );
        final afterRemoval = await DiscoverySettingsStore().load();
        expect(afterRemoval.youtubeEnabled, isFalse);
        expect(afterRemoval.addons.map((addon) => addon.id), [
          'second',
          'third',
        ]);
        expect(await storage.read(key: _key), isNot(contains(_first.token)));
        expect(await storage.read(key: _key), isNot(contains(_first.endpoint)));

        await store.save(const DiscoverySettings());
        final empty = await DiscoverySettingsStore().load();
        expect(empty.hasSource, isFalse);
        expect(empty.addons, isEmpty);
        expect(jsonDecode((await storage.read(key: _key))!), {
          'version': 2,
          'youtubeEnabled': false,
          'addons': [],
        });
      },
    );

    test('save persists validated canonical values', () async {
      await store.save(
        const DiscoverySettings(
          addons: [
            DiscoveryAddonConfig(
              id: 'fixture',
              endpoint: ' HTTPS://ADDON.EXAMPLE/library/manifest.json/ ',
              label: ' Library ',
              token: ' fixture-token ',
            ),
          ],
        ),
      );
      final saved = jsonDecode((await storage.read(key: _key))!) as Map;
      expect(saved['addons'], [
        _addonRecord({
          'id': 'fixture',
          'endpoint': 'https://addon.example/library',
          'label': 'Library',
        }),
      ]);
    });

    test(
      'invalid saves never write or replace the last valid record',
      () async {
        await store.save(const DiscoverySettings(addons: [_first]));
        final raw = await storage.read(key: _key);
        for (final settings in [
          const DiscoverySettings(addons: [_first, _first]),
          const DiscoverySettings(
            addons: [
              DiscoveryAddonConfig(
                id: 'invalid',
                endpoint: 'http://addon.example',
              ),
            ],
          ),
          const DiscoverySettings(
            addons: [
              DiscoveryAddonConfig(
                id: 'invalid',
                endpoint: 'https://addon.example',
                token: 'fixture token',
              ),
            ],
          ),
          DiscoverySettings(addons: _addons(9)),
        ]) {
          await expectLater(
            store.save(settings),
            throwsA(isA<DiscoveryException>()),
          );
          expect(await storage.read(key: _key), raw);
        }
        expect(storage.writeAttempts, 1);
        expect((await store.load()).addons.single.id, 'first');
      },
    );

    test(
      'malformed and unknown records fail closed without leaking or writing',
      () async {
        final invalidRecords = <Object?>[
          null,
          [],
          'fixture-token',
          {},
          for (final version in [null, 0, 3, -1, '2', 2.0, true])
            _v2({'version': version}),
          _v2()..remove('version'),
          _v2()..remove('youtubeEnabled'),
          for (final value in [null, 1, 'true', []])
            _v2({'youtubeEnabled': value}),
          _v2()..remove('addons'),
          for (final value in [
            null,
            {},
            '',
            [null],
            ['fixture-token'],
          ])
            _v2({'addons': value}),
          for (final field in ['id', 'endpoint', 'label', 'token', 'enabled'])
            _v2({
              'addons': [_addonRecord()..remove(field)],
            }),
          for (final field in ['id', 'endpoint', 'label', 'token', 'enabled'])
            _v2({
              'addons': [
                _addonRecord({field: null}),
              ],
            }),
          for (final field in ['id', 'endpoint', 'label', 'token', 'enabled'])
            _v2({
              'addons': [
                _addonRecord({field: 1}),
              ],
            }),
          for (final overrides in [
            {'id': '../fixture'},
            {'label': 'fixture\nlabel'},
            {'label': 'a' * 81},
            {'endpoint': 'http://addon.example/fixture-private-path'},
            {'endpoint': ''},
            {'token': 'fixture\r\ntoken'},
            {'token': 'a' * 4097},
            {'enabled': 'true'},
          ])
            _v2({
              'addons': [_addonRecord(overrides)],
            }),
          _v2({
            'addons': [
              _addonRecord(),
              _addonRecord({'endpoint': 'https://other.example'}),
            ],
          }),
          _v2({
            'addons': [
              _addonRecord(),
              _addonRecord({
                'id': 'other',
                'endpoint':
                    'https://addon.example/fixture-private-path/manifest.json/',
              }),
            ],
          }),
          _v2({
            'addons': [
              for (var index = 0; index < 9; index++)
                _addonRecord({
                  'id': 'addon-$index',
                  'endpoint': 'https://addon-$index.example',
                }),
            ],
          }),
          for (final field in ['endpoint', 'token', 'addonEnabled'])
            _v1()..remove(field),
          _v1({'endpoint': 1}),
          _v1({'token': null}),
          _v1({'addonEnabled': 'true'}),
          _v1({'endpoint': '', 'token': 'fixture-token'}),
          _v1({'endpoint': 'http://addon.example', 'addonEnabled': false}),
          _v1({'token': 'fixture\r\ntoken', 'addonEnabled': false}),
        ];
        for (final raw in [
          'not-json fixture-token',
          '{"token":"fixture-token",',
          ...invalidRecords.map(jsonEncode),
        ]) {
          FlutterSecureStorage.setMockInitialValues({_key: raw});
          await expectLater(
            store.load(),
            throwsA(
              isA<DiscoveryException>().having(
                (error) => error.toString(),
                'safe message',
                _invalidRecordMessage,
              ),
            ),
          );
          expect(await storage.read(key: _key), raw);
        }
        expect(storage.writeAttempts, 0);
      },
    );

    test(
      'read errors are safe and never enable or overwrite sources',
      () async {
        storage.failReads = true;
        await expectLater(
          store.load(),
          throwsA(
            isA<DiscoveryException>().having(
              (error) => error.toString(),
              'safe message',
              _invalidRecordMessage,
            ),
          ),
        );
        expect(storage.writeAttempts, 0);
      },
    );

    test(
      'save waits for storage and failed writes never publish success',
      () async {
        await store.save(const DiscoverySettings(addons: [_first]));
        final raw = await storage.read(key: _key);
        final gate = storage.writeGate = Completer<void>();
        var publishedSuccess = false;
        final saving = store
            .save(const DiscoverySettings(addons: [_second]))
            .then((_) {
              publishedSuccess = true;
            });
        final failed = expectLater(
          saving,
          throwsA(
            isA<DiscoveryException>().having(
              (error) => error.toString(),
              'safe message',
              'Source settings could not be saved. Try again.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(publishedSuccess, isFalse);
        expect(await storage.read(key: _key), raw);
        gate.completeError(StateError('fixture-token write failure'));
        await failed;
        expect(publishedSuccess, isFalse);
        expect(await storage.read(key: _key), raw);
        expect(
          (await DiscoverySettingsStore().load()).addons.single.id,
          'first',
        );
      },
    );
  });
  test('per-add-on HMAC key persists and legacy records remain unsigned', () async {
    const addon = DiscoveryAddonConfig(
      id: 'signed-source',
      endpoint: 'https://addon.example/a/token',
      signingKey: 'unit-test-key',
      enabled: true,
    );
    await store.save(const DiscoverySettings(addons: [addon]));
    final raw = await storage.read(key: _key);
    expect(raw, contains('"signingKey":"unit-test-key"'));
    final loaded = await store.load();
    expect(loaded.addons.single.signingKey, 'unit-test-key');
    expect(
      const DiscoveryAddonConfig(
        id: 'legacy-source',
        endpoint: 'https://addon.example',
      ).signingKey,
      isEmpty,
    );
    expect(
      () => const DiscoveryAddonConfig(
        id: 'invalid-key',
        endpoint: 'https://addon.example',
        signingKey: 'bad\u0001key',
      ).validated(),
      throwsA(isA<DiscoveryException>()),
    );
  });
}
