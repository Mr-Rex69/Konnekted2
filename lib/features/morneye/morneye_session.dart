import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/utils/app_log.dart';
import 'morneye_network.dart';
import 'morneye_storage.dart';

/// A signed gateway session, as desktop's electron/morneye/session.js. Most
/// official add-ons (Deezer, Qobuz, Tidal, Amazon) reach their service through
/// a gateway that first asks you to pass a verification page once; after that
/// every request is HMAC-signed with the session it granted.

String _sha256(List<int> value) => sha256.convert(value).toString();

String _hmac(List<int> key, String value) => base64Url
    .encode(Hmac(sha256, key).convert(utf8.encode(value)).bytes)
    .replaceAll('=', '');

String _randomHex(int bytes) =>
    morneyeRandomBytes(bytes)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

String _randomToken(int bytes) =>
    base64Url.encode(morneyeRandomBytes(bytes)).replaceAll('=', '');

/// The signature headers for one request.
Map<String, String> morneyeSignedHeaders(
  Map<String, Object?> config,
  Map<String, Object?> record,
  String method,
  String url,
  String body, {
  DateTime? now,
  String? nonce,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  final prefix = config['headerPrefix'] as String? ?? 'X-Sig-';
  // JavaScript's toISOString: milliseconds only, while Dart may add micros.
  final timestamp = at.toIso8601String().replaceFirstMapped(
    RegExp(r'\.(\d{3})\d*Z$'),
    (match) => '.${match[1]}Z',
  );
  final bodyHash = _sha256(utf8.encode(body));
  final windowSeconds = (config['timeWindowSeconds'] as num?)?.toInt() ?? 300;
  final window = at.millisecondsSinceEpoch ~/ 1000 ~/ windowSeconds;
  final sessionId = '${record['session_id']}';
  final rolling = _hmac(
    utf8.encode('${record['session_secret']}'),
    '$window:$sessionId',
  );
  final appVersion = config['appVersion'] as String? ?? 'ext-1.0';
  final platform = config['platform'] as String? ?? 'extension';
  final usedNonce = nonce ?? _randomHex(16);
  final canonical = [
    config['schemeLabel'] as String? ?? 'SPOTIFLAC-HMAC-V1',
    method.toUpperCase(),
    Uri.parse(url).path,
    '',
    bodyHash,
    timestamp,
    usedNonce,
    sessionId,
    appVersion,
    platform,
  ].join('\n');
  return {
    '${prefix}Session': sessionId,
    '${prefix}Timestamp': timestamp,
    '${prefix}Nonce': usedNonce,
    '${prefix}Body-SHA256': bodyHash,
    '${prefix}Signature': _hmac(utf8.encode(rolling), canonical),
    '${prefix}App-Version': appVersion,
    '${prefix}Platform': platform,
  };
}

class MorneyePending {
  MorneyePending(this.url, this.state, this.createdAt);
  final String url;
  final String state;
  final DateTime createdAt;
}

/// Expose the signed gateway's retry contract under the names consumed by
/// the installed Mornye/Tidal JS extensions. The raw gateway uses snake_case;
/// Tidal's signedJSON reads camelCase. Without these fields a terminal 403
/// ticket rejection looks like a transient failure, and the extension keeps
/// retrying quality tiers without ever opening an audio transfer.
///
/// Do not manufacture an authorization success or a playable URL.
Map<String, Object?> morneyeSignedAddonResponse(
  Map<String, Object?> response,
  Map<String, Object?> contract,
) {
  final status = (response['status'] as num?)?.toInt();
  final code = '${contract['code'] ?? ''}'.toUpperCase();
  final explicitMode = '${contract['retry_mode'] ?? ''}'.trim();
  // A 4xx response other than throttling/timeouts cannot become playable by
  // retrying the exact same signed ticket. A gateway can explicitly override
  // this with its retry contract.
  final terminalClientError =
      status != null &&
      status >= 400 &&
      status < 500 &&
      status != 408 &&
      status != 429;
  final retryMode = explicitMode.isNotEmpty
      ? explicitMode
      : (terminalClientError ? 'none' : '');
  final retrySeconds =
      (contract['retry_after_seconds'] as num?)?.toDouble() ?? 0.0;
  return {
    ...response,
    'code': code,
    'retryable': contract['retryable'] == true && retryMode != 'none',
    'retryMode': retryMode,
    'retryAfterSeconds': retrySeconds,
    'needsVerification': status == 428 || code == 'VERIFY_REQUIRED',
    // Retain backwards-compatible snake_case fields for other clients.
    if (code.isNotEmpty) ...{
      'error_code': code,
      'error_origin': contract['origin'],
      'error_action': contract['action'],
      'retry_after_seconds': retrySeconds,
    },
  };
}

/// A gateway cooldown is recoverable; it is not a missing recording or login.
class MorneyeRateLimitException implements Exception {
  const MorneyeRateLimitException(this.retryAfter);
  final Duration retryAfter;

  @override
  String toString() =>
      'The add-on service is rate limiting requests (HTTP 429). '
      'Try again in ${(retryAfter.inMilliseconds + 999) ~/ 1000} seconds.';
}

class MorneyeSignedSession {
  MorneyeSignedSession(
    this.config,
    this.storage,
    this.network,
    String owner, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       namespace = _sha256(
         utf8.encode(
           [
             config['namespace'] as String? ?? owner,
             config['baseUrl'],
             config['appVersion'] as String? ?? 'ext-1.0',
             config['platform'] as String? ?? 'extension',
           ].join('\n'),
         ),
       );

  final Map<String, Object?> config;
  final MorneyeStorage storage;
  final MorneyeNetwork? network;
  final String namespace;
  final DateTime Function() _now;

  /// Stored separately from credentials so a new runtime or restart cannot
  /// turn a server cooldown into another burst of ticket requests.
  MorneyeRateLimitException? get rateLimitError {
    final until = storage.read(namespace, 'ratelimit')['until'];
    if (until is! int) return null;
    final remaining = until - _now().millisecondsSinceEpoch;
    return remaining > 0
        ? MorneyeRateLimitException(Duration(milliseconds: remaining))
        : null;
  }

  void throwIfRateLimited() {
    final error = rateLimitError;
    if (error != null) throw error;
  }

  void _rememberRateLimit(Map<String, Object?> response) {
    Map contract = const {};
    try {
      final decoded = jsonDecode('${response['body']}');
      if (decoded is Map) contract = decoded;
    } catch (_) {}
    final headers = response['headers'];
    final rawHeader = headers is Map
        ? headers.entries
              .where((e) => '${e.key}'.toLowerCase() == 'retry-after')
              .map((e) => '${e.value}')
              .firstOrNull
        : null;
    final headerSeconds =
        double.tryParse(rawHeader ?? '') ??
        (rawHeader == null ? null : _retryDateSeconds(rawHeader));
    final bodySeconds = num.tryParse(
      '${contract['retry_after_seconds'] ?? ''}',
    );
    final delays = [
      headerSeconds,
      bodySeconds,
    ].whereType<num>().where((n) => n.isFinite && n > 0);
    final seconds = delays.isEmpty
        ? 60
        : delays.reduce((a, b) => a > b ? a : b).ceil();
    final until = _now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
    final previous = storage.read(namespace, 'ratelimit')['until'];
    storage.write(namespace, 'ratelimit', {
      'until': previous is int && previous > until ? previous : until,
    });
    // Closed diagnostic fields only; never include the response body or URL.
    AppLog.instance.add(
      '[Morneye] gateway rate_limited http=429 retryAfterSeconds=$seconds',
    );
  }

  double? _retryDateSeconds(String value) {
    try {
      return HttpDate.parse(value).difference(_now()).inMilliseconds / 1000;
    } catch (_) {
      return null;
    }
  }

  MorneyePending? pending;
  String? pendingGrant;
  bool blocked = false;
  int _generation = 0;
  Future<bool>? _flight;
  Future<Map<String, Object?>>? _exchange;
  Future<void>? _refreshing;

  String get _appVersion => config['appVersion'] as String? ?? 'ext-1.0';
  String get _platform => config['platform'] as String? ?? 'extension';
  Map get _endpoints =>
      config['endpoints'] is Map ? config['endpoints'] as Map : const {};
  String get _callbackUrl =>
      config['callbackUrl'] as String? ?? 'spotiflac://session-grant';

  MorneyeNetwork get _network {
    final value = network;
    if (value == null) throw StateError('Signed session has no network');
    return value;
  }

  Map<String, Object?> record() {
    final record = storage.read(namespace, 'session');
    if (record['install_id'] == null) {
      record['install_id'] = _randomHex(16);
      _save(record);
    }
    return record;
  }

  void _save(Map<String, Object?> record) =>
      storage.write(namespace, 'session', record);

  bool usable(Map<String, Object?> record) {
    final expires = DateTime.tryParse('${record['expires_at'] ?? ''}');
    return record['session_id'] != null &&
        record['session_secret'] != null &&
        expires != null &&
        expires.isAfter(DateTime.now());
  }

  /// [path] under the configured base URL; never outside it.
  String endpoint(String path) {
    final base = Uri.parse(config['baseUrl'] as String);
    final trimmed = base.toString().replaceFirst(RegExp(r'/$'), '');
    final url = Uri.parse('$trimmed/${path.replaceFirst(RegExp(r'^/+'), '')}');
    final basePath = base.path.replaceFirst(RegExp(r'/$'), '');
    if (url.origin != base.origin || !url.path.startsWith('$basePath/')) {
      throw StateError('Signed-session path escaped its base URL');
    }
    return url.toString();
  }

  Map<String, Object?> status() {
    final record = this.record();
    return {
      'authenticated': usable(record) && !blocked,
      'verification_required': pending != null,
      'expires_at': record['expires_at'] ?? '',
      'session_id': record['session_id'] ?? '',
      'install_id': record['install_id'],
      'app_version': _appVersion,
      'platform': _platform,
      'auth_url': pending?.url ?? '',
    };
  }

  Map<String, Object?> clear() {
    final record = this.record();
    _generation++;
    _save({'install_id': record['install_id']});
    pending = null;
    blocked = false;
    return {'success': true};
  }

  Map<String, Object?> verification() => {
    'ok': false,
    'needsVerification': true,
    'error': 'VERIFY_REQUIRED',
    'auth_url': pending?.url ?? '',
    'open_auth_url': pending?.url ?? '',
  };

  /// Asks the gateway for a session; false when a verification page must be
  /// passed first ([pending] then holds its URL).
  Future<bool> bootstrap() =>
      _flight ??= _bootstrap().whenComplete(() => _flight = null);

  Future<bool> _bootstrap() async {
    final generation = _generation;
    final record = this.record();
    final url =
        Uri.parse(endpoint(_endpoints['bootstrap'] as String? ?? '/bootstrap'))
            .replace(
              queryParameters: {
                ...Uri.parse(
                  endpoint(_endpoints['bootstrap'] as String? ?? '/bootstrap'),
                ).queryParameters,
                'app_version': _appVersion,
                'install_id': '${record['install_id']}',
              },
            );
    final response = await _network.jsonResponse(url.toString());
    if (response['ok'] != true) {
      throw StateError(
        'Signed-session bootstrap returned HTTP ${response['status']}',
      );
    }
    final body = jsonDecode(response['body'] as String) as Map<String, Object?>;
    if (generation != _generation) {
      throw StateError('Session changed during authentication');
    }
    if (body['session_id'] != null &&
        body['session_secret'] != null &&
        body['expires_at'] != null) {
      _save({...record, ...body});
      pending = null;
      blocked = false;
      return true;
    }
    var authUrl = (body['auth_url'] ?? body['challenge_url']) as String?;
    var state = _randomToken(24);
    if (authUrl == null && body['challenge_id'] != null) {
      final callback = Uri.parse(_callbackUrl);
      final withState = callback.replace(
        queryParameters: {
          ...callback.queryParameters,
          'cb_version': 'v2grant',
          'state': state,
        },
      );
      final challenge = Uri.parse(
        endpoint(_endpoints['challenge'] as String? ?? '/challenge'),
      );
      authUrl = challenge
          .replace(
            queryParameters: {
              ...challenge.queryParameters,
              'id': '${body['challenge_id']}',
              'cb': withState.toString(),
            },
          )
          .toString();
    }
    if (authUrl == null) {
      throw StateError('Signed-session bootstrap gave no verification page');
    }
    var challenge = morneyeValidateUrl(authUrl, _network.permissions);
    final nested =
        challenge.queryParameters['cb'] ??
        challenge.queryParameters['callback_url'] ??
        challenge.queryParameters['redirect_uri'];
    final nestedState = nested == null
        ? null
        : Uri.tryParse(nested)?.queryParameters['state'];
    state = challenge.queryParameters['state'] ?? nestedState ?? state;
    if (challenge.queryParameters['state'] == null && nestedState == null) {
      challenge = challenge.replace(
        queryParameters: {...challenge.queryParameters, 'state': state},
      );
    }
    pending = MorneyePending(challenge.toString(), state, DateTime.now());
    _authEvent('challenge_ready');
    return false;
  }

  /// Trades the [grant] a verification page returned for a session.
  Future<Map<String, Object?>> completeGrant([String? grant]) {
    final value = grant ?? pendingGrant;
    if (value == null) {
      return Future.error(StateError('No pending verification grant'));
    }
    return _exchange ??= _completeGrant(value)
        .whenComplete(() => _exchange = null);
  }

  Future<Map<String, Object?>> _completeGrant(String grant) async {
    final generation = _generation;
    final record = this.record();
    final response = await _network.jsonResponse(
      endpoint(_endpoints['exchange'] as String? ?? '/session/exchange'),
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'grant': grant,
        'install_id': record['install_id'],
        'app_version': _appVersion,
        'platform': _platform,
      }),
    );
    if (response['ok'] != true) {
      _authEvent('exchange_failed_http_${response['status']}');
      throw StateError('Session exchange returned HTTP ${response['status']}');
    }
    final body = jsonDecode(response['body'] as String) as Map<String, Object?>;
    if (body['session_id'] == null ||
        body['session_secret'] == null ||
        body['expires_at'] == null) {
      throw StateError('Session exchange omitted its session fields');
    }
    if (generation != _generation) {
      throw StateError('Session changed during authentication');
    }
    _save({
      ...record,
      'session_id': body['session_id'],
      'session_secret': body['session_secret'],
      'expires_at': body['expires_at'],
    });
    pending = null;
    pendingGrant = null;
    blocked = false;
    _authEvent('exchange_complete');
    return {'success': true};
  }

  /// Handles the page's redirect to the callback URL (spotiflac://session-grant).
  Future<Map<String, Object?>> callback(String raw) {
    final url = _callbackTarget(raw);
    final expected = Uri.parse(_callbackUrl);
    final pending = this.pending;
    final state = url?.queryParameters['state'];
    if (url == null ||
        url.scheme != expected.scheme ||
        url.authority != expected.authority ||
        url.path != expected.path ||
        pending == null ||
        DateTime.now().difference(pending.createdAt) >
            const Duration(minutes: 3) ||
        state == null ||
        state != pending.state) {
      _authEvent('callback_rejected');
      return Future.error(
        StateError('Invalid or expired verification callback'),
      );
    }
    final grant = _returnedGrant(url);
    if (grant == null) {
      _authEvent('callback_missing_grant');
      return Future.error(
        StateError(
          'The verification page returned no grant. Please try verification again.',
        ),
      );
    }
    _authEvent('callback_received');
    pendingGrant = grant;
    return completeGrant();
  }

  // Never log callback URLs, state, grants or session credentials.
  void _authEvent(String event) =>
      AppLog.instance.add('[Morneye verification] event=$event');

  String? _returnedGrant(Uri url) {
    for (final field in ['grant', 'code']) {
      final value = url.queryParameters[field];
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  Uri? _callbackTarget(String raw) {
    final url = Uri.tryParse(raw);
    if (url == null) return null;
    final expected = Uri.parse(_callbackUrl);
    bool matches(Uri target) =>
        target.scheme == expected.scheme &&
        target.authority == expected.authority &&
        target.path == expected.path;
    if (matches(url)) return url;

    // A challenge page itself contains cb=<callback template>. WKWebView
    // reports that initial navigation too: consuming it closes the page before
    // the user can verify. Only unwrap a callback carrying an issued grant.
    final nested = url.queryParameters['cb'];
    final target = nested == null ? null : Uri.tryParse(nested);
    return target != null && matches(target) && _returnedGrant(target) != null
        ? target
        : null;
  }

  /// Whether [raw] is a direct callback or a wrapped, issued grant.
  bool isCallback(String raw) => _callbackTarget(raw) != null;

  Future<void> _refresh(Map<String, Object?> record) {
    final path = _endpoints['refresh'] as String?;
    final expires = DateTime.tryParse('${record['expires_at'] ?? ''}');
    if (path == null ||
        expires == null ||
        expires.difference(DateTime.now()) > const Duration(hours: 1)) {
      return Future.value();
    }
    return _refreshing ??= () async {
      final generation = _generation;
      final response = await _request(
        record,
        'POST',
        path,
        jsonEncode({'install_id': record['install_id']}),
        const {},
      );
      if (response['ok'] != true) return;
      final next =
          jsonDecode(response['body'] as String) as Map<String, Object?>;
      if (generation == _generation &&
          this.record()['session_id'] == record['session_id']) {
        _save({
          ...record,
          for (final key in const [
            'session_id',
            'session_secret',
            'expires_at',
          ])
            if (next[key] != null) key: next[key],
        });
      }
    }().whenComplete(() => _refreshing = null);
  }

  Future<Map<String, Object?>> _request(
    Map<String, Object?> record,
    String method,
    String path,
    String body,
    Map<String, String> headers,
  ) async {
    throwIfRateLimited();
    final url = endpoint(path);
    final response = await _network.jsonResponse(
      url,
      method: method.toUpperCase(),
      body: body,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
        ...morneyeSignedHeaders(config, record, method, url, body),
      },
    );
    if (response['status'] == 429) {
      _rememberRateLimit(response);
      throw rateLimitError!;
    }
    return response;
  }

  /// A signed request for the add-on; asks for verification when needed.
  Future<Map<String, Object?>> signedFetch(
    String method,
    String path, [
    String body = '',
    Map<String, String> headers = const {},
    Future<void> Function(Duration)? sleep,
  ]) async {
    final wait = sleep ?? (Duration d) => Future<void>.delayed(d);
    try {
      throwIfRateLimited();
      var record = this.record();
      if (!usable(record) || blocked) {
        if (!await bootstrap()) return verification();
        record = this.record();
      }
      await _refresh(record).catchError((_) {});
      record = this.record();
      for (var attempt = 0; attempt < 3; attempt++) {
        final clock = Stopwatch()..start();
        final response = await _request(record, method, path, body, headers);
        clock.stop();
        Map<String, Object?> contract = {};
        try {
          final decoded = jsonDecode(response['body'] as String);
          if (decoded is Map<String, Object?>) contract = decoded;
        } catch (_) {}
        final code = '${contract['code'] ?? ''}'.toUpperCase();
        final status = response['status'];
        if (status == 503 &&
            contract['origin'] == 'provider' &&
            code == 'PROVIDER_UNAVAILABLE' &&
            contract['retryable'] == true &&
            contract['retry_mode'] == 'same_operation' &&
            attempt < 2) {
          final seconds =
              ((contract['retry_after_seconds'] as num?)?.toInt() ?? 1).clamp(
                1,
                120,
              );
          await wait(Duration(seconds: seconds));
          continue;
        }
        final reset =
            status == 401 &&
            contract['origin'] == 'gateway' &&
            code == 'SESSION_INVALID' &&
            contract['action'] == 'bootstrap_session';
        final verify =
            status == 428 &&
            contract['origin'] == 'gateway' &&
            code == 'VERIFY_REQUIRED' &&
            contract['action'] == 'verify';
        if ((reset || verify) && attempt < 1) {
          if (reset) {
            clear();
          } else {
            blocked = true;
          }
          if (!await bootstrap()) return verification();
          record = this.record();
          continue;
        }
        final addonResponse = morneyeSignedAddonResponse(response, contract);
        if (path == '/tickets') {
          // The gateway ticket decision is the dividing line between
          // "Resolving Tidal stream" and an actual media transfer.
          // Never record a ticket, URL, request body or session credentials.
          AppLog.instance.add(
            '[Morneye] ticket request status=$status '
            'retryable=${addonResponse['retryable'] == true} '
            'verification=${addonResponse['needsVerification'] == true} '
            'elapsedMs=${clock.elapsedMilliseconds}',
          );
        }
        return addonResponse;
      }
      return {'ok': false, 'error': 'Signed request failed'};
    } on MorneyeRateLimitException {
      rethrow;
    } catch (error) {
      return {'ok': false, 'error': '$error'};
    }
  }
}
