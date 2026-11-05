import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Optional HMAC signing for token-bearing add-on API endpoints.
/// A signing key is never bundled with Lokal; unsigned add-ons are unaffected.
const defaultAddonSigningKey = '';

Map<String, String> signedAddonHeaders(
  Uri url, {
  String? intent,
  int? epochSeconds,
  String signingKey = defaultAddonSigningKey,
}) {
  if (url.scheme != 'https' || signingKey.isEmpty) return const {};
  final parts = url.pathSegments;
  final index = parts.indexOf('a');
  if (index < 0 || index + 1 >= parts.length) return const {};
  final token = parts[index + 1];
  if (token.isEmpty) return const {};

  final seconds =
      epochSeconds ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  // The protocol signs the decoded URI path, not the query string or host.
  final message = seconds.toString() + '\nGET\n' + url.path + '\n' + token;
  final signature = Hmac(sha256, utf8.encode(signingKey))
      .convert(utf8.encode(message))
      .toString();
  return {
    'X-LW-TS': seconds.toString(),
    'X-LW-Sign': signature,
    if (intent == 'stream' || intent == 'download') 'X-LW-Intent': intent!,
  };
}
