import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../models/lokal_remote_state.dart';

/// Discovery names and IDs are hints. A new address must prove it still owns
/// the paired phone's verifier before it receives any bearer credentials.
Future<bool> verifyLinkedDesktop({
  required http.Client client,
  required Uri origin,
  required LokalRemoteCredentials credentials,
  required String deviceId,
}) async {
  final abort = Completer<void>();
  final deadline = Timer(const Duration(seconds: 3), () {
    if (!abort.isCompleted) abort.complete();
  });
  try {
    final random = Random.secure();
    final challenge = List.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final request =
        http.AbortableRequest(
            'POST',
            origin.replace(path: '/api/remote/identity'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({'deviceId': deviceId, 'challenge': challenge});
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      return false;
    }
    // This endpoint only returns IDs and a digest. Bound even an untrusted peer.
    final bytes = await _readProofBody(response.stream);
    if (bytes == null) return false;
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['desktopId'] != credentials.desktopId ||
        value['userId'] is! String ||
        (credentials.desktopUserId != null &&
            value['userId'] != credentials.desktopUserId) ||
        value['proof'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['proof'] as String)) {
      return false;
    }
    final expected =
        Hmac(sha256, sha256.convert(utf8.encode(credentials.remoteToken)).bytes)
            .convert(
              utf8.encode(
                jsonEncode([
                  'lokal-link-identity-v1',
                  challenge,
                  credentials.desktopId,
                  deviceId,
                  value['userId'],
                ]),
              ),
            )
            .toString();
    final proof = value['proof'] as String;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ proof.codeUnitAt(i);
    }
    return difference == 0;
  } finally {
    deadline.cancel();
    if (!abort.isCompleted) abort.complete();
  }
}

Future<List<int>?> _readProofBody(Stream<List<int>> stream) async {
  final result = Completer<List<int>?>();
  final bytes = <int>[];
  final timer = Timer(const Duration(seconds: 3), () {
    if (!result.isCompleted) result.complete(null);
  });
  final subscription = stream.listen(
    (chunk) {
      if (result.isCompleted) return;
      if (bytes.length + chunk.length > 4096) {
        result.complete(null);
      } else {
        bytes.addAll(chunk);
      }
    },
    onDone: () {
      if (!result.isCompleted) result.complete(bytes);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
    cancelOnError: true,
  );
  try {
    return await result.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}
