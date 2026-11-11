import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/link/link_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const token = 'synthetic-persisted-token';
const desktop = 'desktop-fixture', phone = 'phone-fixture', user = 'owner';
final credentials = LokalRemoteCredentials(
  origin: Uri.parse('http://192.0.2.1:3421'),
  remoteToken: token,
  desktopId: desktop,
  desktopUserId: user,
);
Map<String, Object> identity(
  String challenge, {
  String id = desktop,
  String profile = user,
  String secret = token,
}) => {
  'desktopId': id,
  'userId': profile,
  'proof': Hmac(sha256, sha256.convert(utf8.encode(secret)).bytes)
      .convert(
        utf8.encode(
          jsonEncode(['lokal-link-identity-v1', challenge, id, phone, profile]),
        ),
      )
      .toString(),
};

void main() {
  test(
    'fresh proof authenticates the same PC without sending either bearer',
    () async {
      final challenges = <String>{};
      final client = MockClient((request) async {
        expect(request.url.path, '/api/remote/identity');
        expect(request.headers.keys, isNot(contains('x-remote-token')));
        expect(request.headers.keys, isNot(contains('x-api-key')));
        expect(request.followRedirects, isFalse);
        expect(request.body, isNot(contains(token)));
        final body = jsonDecode(request.body) as Map;
        expect(body['deviceId'], phone);
        expect(challenges.add(body['challenge'] as String), isTrue);
        return http.Response(jsonEncode(identity(body['challenge'])), 200);
      });
      addTearDown(client.close);
      for (var i = 0; i < 2; i++) {
        expect(
          await verifyLinkedDesktop(
            client: client,
            origin: Uri.parse('http://192.0.2.8:3421'),
            credentials: credentials,
            deviceId: phone,
          ),
          isTrue,
        );
      }
    },
  );

  for (final scenario in [
    'wrong token',
    'wrong desktop',
    'wrong profile',
    'replayed proof',
    'revoked',
    'oversized',
    'redirect',
  ]) {
    test('rejects $scenario', () async {
      final client = MockClient((request) async {
        final challenge =
            (jsonDecode(request.body) as Map)['challenge'] as String;
        if (scenario == 'revoked') return http.Response('', 401);
        if (scenario == 'oversized') return http.Response('a' * 4097, 200);
        if (scenario == 'redirect')
          return http.Response(
            '',
            302,
            headers: {'location': 'http://elsewhere/'},
          );
        return http.Response(
          jsonEncode(
            identity(
              scenario == 'replayed proof' ? '0' * 64 : challenge,
              id: scenario == 'wrong desktop' ? 'other' : desktop,
              profile: scenario == 'wrong profile' ? 'other' : user,
              secret: scenario == 'wrong token' ? 'revoked-token' : token,
            ),
          ),
          200,
        );
      });
      addTearDown(client.close);
      expect(
        await verifyLinkedDesktop(
          client: client,
          origin: credentials.origin,
          credentials: credentials,
          deviceId: phone,
        ),
        isFalse,
      );
    });
  }
}
