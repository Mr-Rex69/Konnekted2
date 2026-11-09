import 'dart:convert';
import 'dart:io';

import 'package:flick/features/morneye/morneye_network.dart';
import 'package:flick/features/morneye/morneye_session.dart';
import 'package:flick/features/morneye/morneye_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'morneye_fakes.dart';

class _Gateway extends MorneyeNetwork {
  _Gateway() : super(const MorneyePermissions(network: ['gateway.example']));

  final grants = <String>[];

  @override
  Future<Map<String, Object?>> jsonResponse(
    String raw, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    bool asFetch = false,
  }) async {
    if (method == 'GET') {
      return {
        'ok': true,
        'body': jsonEncode({'challenge_id': 'challenge'}),
      };
    }
    expect(Uri.parse(raw).path, '/session/exchange');
    grants.add((jsonDecode(body!) as Map)['grant'] as String);
    return {
      'ok': true,
      'body': jsonEncode({
        'session_id': 'test-session',
        'session_secret': 'test-secret',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
      }),
    };
  }
}

void main() {
  late Directory directory;
  late MorneyeSignedSession session;
  late _Gateway gateway;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('morneye-callback-');
    final storage = MorneyeStorage(
      directory,
      sealer: FakeNative(),
      vault: MemoryVault(),
    );
    await storage.open();
    gateway = _Gateway();
    session = MorneyeSignedSession(
      {'baseUrl': 'https://gateway.example'},
      storage,
      gateway,
      'test-addon',
    );
    expect(await session.bootstrap(), isFalse);
  });

  tearDown(() => directory.delete(recursive: true));

  String callback({String? grant = 'issued-grant', String? state}) => Uri(
    scheme: 'spotiflac',
    host: 'session-grant',
    queryParameters: {
      'state': state ?? session.pending!.state,
      'grant': ?grant,
    },
  ).toString();

  String wrapper(String target) =>
      Uri.https('gateway.example', '/return', {'cb': target}).toString();

  test(
    'the bootstrap challenge opens instead of being consumed as a callback',
    () {
      final page = session.pending!.url;
      expect(Uri.parse(page).queryParameters['cb'], contains('session-grant'));
      expect(session.isCallback(page), isFalse);
      expect(gateway.grants, isEmpty);
      expect(session.pending, isNotNull);
    },
  );

  test(
    'a callback template inside another web page is not a returned grant',
    () {
      expect(session.isCallback(wrapper(callback(grant: null))), isFalse);
      expect(session.isCallback(wrapper(callback(grant: ''))), isFalse);
      expect(session.isCallback('https://gateway.example/challenge'), isFalse);
    },
  );

  for (final wrapped in [false, true]) {
    test(
      'accepts ${wrapped ? 'wrapped' : 'direct'} issued grant and saves session',
      () async {
        final target = callback();
        final raw = wrapped ? wrapper(target) : target;
        expect(session.isCallback(raw), isTrue);
        expect(await session.callback(raw), {'success': true});
        expect(gateway.grants, ['issued-grant']);
        expect(session.status()['authenticated'], isTrue);
        expect(session.pending, isNull);
      },
    );
  }

  test('legacy code callbacks still exchange their code', () async {
    final url = Uri.parse(callback(grant: null))
        .replace(
          queryParameters: {
            'state': session.pending!.state,
            'code': 'legacy-code',
          },
        )
        .toString();
    expect(session.isCallback(url), isTrue);
    await session.callback(url);
    expect(gateway.grants, ['legacy-code']);
  });

  test(
    'a direct callback missing its grant is rejected without an exchange',
    () async {
      final raw = callback(grant: null);
      expect(session.isCallback(raw), isTrue);
      await expectLater(session.callback(raw), throwsStateError);
      expect(gateway.grants, isEmpty);
      expect(session.pending, isNotNull);
    },
  );

  test('empty grants cannot produce an authenticated session', () async {
    await expectLater(session.callback(callback(grant: '')), throwsStateError);
    expect(gateway.grants, isEmpty);
    expect(session.status()['authenticated'], isFalse);
  });

  test('state mismatch and foreign callbacks cannot exchange grants', () async {
    await expectLater(
      session.callback(callback(state: 'wrong')),
      throwsStateError,
    );
    final foreign = callback().replaceFirst('session-grant', 'other-target');
    expect(session.isCallback(foreign), isFalse);
    await expectLater(session.callback(foreign), throwsStateError);
    expect(gateway.grants, isEmpty);
  });

  test('expired callbacks cannot exchange grants', () async {
    final raw = callback();
    session.pending = MorneyePending(
      session.pending!.url,
      session.pending!.state,
      DateTime.now().subtract(const Duration(minutes: 4)),
    );
    await expectLater(session.callback(raw), throwsStateError);
    expect(gateway.grants, isEmpty);
  });
}
