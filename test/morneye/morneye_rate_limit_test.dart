import 'dart:convert';
import 'dart:io';

import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/morneye/morneye_host.dart';
import 'package:flick/features/morneye/morneye_network.dart';
import 'package:flick/features/morneye/morneye_runtime.dart';
import 'package:flick/features/morneye/morneye_session.dart';
import 'package:flick/features/morneye/morneye_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'morneye_fakes.dart';

class _Gateway extends MorneyeNetwork {
  _Gateway() : super(const MorneyePermissions(network: ['gateway.example']));
  int calls = 0;
  Map<String, Object?> response = {
    'ok': false,
    'status': 429,
    'body': '{}',
    'headers': {'retry-after': '120'},
  };

  @override
  Future<Map<String, Object?>> jsonResponse(
    String raw, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    bool asFetch = false,
  }) async {
    calls++;
    return response;
  }
}

void main() {
  late Directory directory;
  late MorneyeStorage storage;
  late MorneyeSignedSession session;
  late _Gateway gateway;
  late DateTime now;
  const config = {'baseUrl': 'https://gateway.example'};

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('morneye-rate-limit-');
    storage = MorneyeStorage(
      directory,
      sealer: FakeNative(),
      vault: MemoryVault(),
    );
    await storage.open();
    now = DateTime.utc(2026, 11, 9);
    gateway = _Gateway();
    session = MorneyeSignedSession(
      config,
      storage,
      gateway,
      'test',
      now: () => now,
    );
    storage.write(session.namespace, 'session', {
      'install_id': 'install',
      'session_id': 'session',
      'session_secret': 'secret',
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String(),
    });
  });

  tearDown(() async {
    gateway.close();
    await directory.delete(recursive: true);
  });

  test(
    '429 suppresses rapid ticket retries, including a new session instance',
    () async {
      for (var i = 0; i < 25; i++) {
        await expectLater(
          session.signedFetch('POST', '/tickets'),
          throwsA(isA<MorneyeRateLimitException>()),
        );
      }
      final replacement = MorneyeSignedSession(
        config,
        storage,
        gateway,
        'test',
        now: () => now,
      );
      await expectLater(
        replacement.signedFetch('POST', '/tickets'),
        throwsA(isA<MorneyeRateLimitException>()),
      );
      expect(gateway.calls, 1);
      expect(replacement.status()['authenticated'], isTrue);
      expect(
        replacement.rateLimitError!.retryAfter,
        const Duration(seconds: 120),
      );
    },
  );

  test('retry becomes possible after the server cooldown expires', () async {
    await expectLater(
      session.signedFetch('POST', '/tickets'),
      throwsA(isA<MorneyeRateLimitException>()),
    );
    now = now.add(const Duration(seconds: 121));
    gateway.response = {'ok': true, 'status': 200, 'body': '{}'};
    expect((await session.signedFetch('POST', '/tickets'))['ok'], isTrue);
    expect(session.rateLimitError, isNull);
    expect(gateway.calls, 2);
  });

  for (final delay in [60, 180]) {
    test('uses the longer body/header cooldown ($delay seconds)', () async {
      gateway.response = {
        'ok': false,
        'status': 429,
        'body': jsonEncode({'retry_after_seconds': delay}),
        'headers': {'Retry-After': '60'},
      };
      await expectLater(
        session.signedFetch('GET', '/search'),
        throwsA(isA<MorneyeRateLimitException>()),
      );
      expect(session.rateLimitError!.retryAfter, Duration(seconds: delay));
    });
  }

  test('HTTP-date Retry-After is honored', () async {
    gateway.response = {
      'ok': false,
      'status': 429,
      'body': 'not json',
      'headers': {
        'retry-after': HttpDate.format(now.add(const Duration(minutes: 5))),
      },
    };
    await expectLater(
      session.signedFetch('GET', '/search'),
      throwsA(isA<MorneyeRateLimitException>()),
    );
    expect(session.rateLimitError!.retryAfter, const Duration(minutes: 5));
  });

  test(
    'missing or invalid retry hints get a bounded default cooldown',
    () async {
      gateway.response = {
        'ok': false,
        'status': 429,
        'body': '{"retry_after_seconds":-1}',
        'headers': {'retry-after': 'invalid'},
      };
      await expectLater(
        session.signedFetch('POST', '/tickets'),
        throwsA(isA<MorneyeRateLimitException>()),
      );
      expect(session.rateLimitError!.retryAfter, const Duration(seconds: 60));
    },
  );

  test('a different gateway is not blocked by this cooldown', () async {
    await expectLater(
      session.signedFetch('POST', '/tickets'),
      throwsA(isA<MorneyeRateLimitException>()),
    );
    final other = MorneyeSignedSession(
      {'baseUrl': 'https://other.example'},
      storage,
      gateway,
      'test',
      now: () => now,
    );
    expect(other.rateLimitError, isNull);
  });

  test(
    'HTTP 403 remains a terminal provider error without a cooldown',
    () async {
      gateway.response = {'ok': false, 'status': 403, 'body': '{}'};
      final reply = await session.signedFetch('POST', '/tickets');
      expect(reply['status'], 403);
      expect(reply['retryMode'], 'none');
      expect(session.rateLimitError, isNull);
    },
  );

  for (final caught in [false, true]) {
    test(
      'rate limit survives the JS bridge ${caught ? 'returned failure' : 'exception'}',
      () async {
        final engine = FakeEngine();
        engine.scripts['code'] = {
          'download': (args, call) async {
            try {
              return await call('session.signedFetch', [
                'POST',
                '/tickets',
                '',
                {},
              ]);
            } catch (_) {
              if (!caught) rethrow;
              return {'success': false, 'error': 'Download timed out'};
            }
          },
        };
        final host = MorneyeHost(
          addon: MorneyeAddonInfo(
            key: 'test',
            name: 'deezer',
            manifest: manifestFor('deezer'),
          ),
          storage: storage,
          network: gateway,
          session: session,
          native: FakeNative(),
          root: directory.path,
        );
        final runtime = await MorneyeRuntime.start(
          'code',
          {},
          host,
          starter: engine.start,
        );
        addTearDown(runtime.close);
        await expectLater(
          runtime.invoke('download'),
          throwsA(isA<MorneyeRateLimitException>()),
        );
        expect(gateway.calls, 1);
      },
    );
  }

  test('autoplay holds service cooldowns and verification, but skips missing songs', () {
    expect(
      shouldHoldPendingPlayback(const DiscoveryRateLimited('Service busy')),
      isTrue,
    );
    expect(
      shouldHoldPendingPlayback(const DiscoveryVerificationRequired('Deezer')),
      isTrue,
    );
    expect(
      shouldHoldPendingPlayback(const DiscoveryException('Song missing')),
      isFalse,
    );
    expect(shouldHoldPendingPlayback(null), isFalse);
  });
}
