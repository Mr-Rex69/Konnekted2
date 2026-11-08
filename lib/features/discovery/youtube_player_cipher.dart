import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../src/rust/api/morneye_api.dart' as native;
import 'discovery_http.dart';
import 'discovery_models.dart';

typedef YoutubeCipherEvaluator = Future<Map<String, dynamic>> Function(
  String code,
  Map<String, Object?> input,
  Future<void>? cancel,
);

/// Decodes YouTube's signature and throttling challenges using the bundled,
/// pinned yt-dlp EJS solver. The existing QuickJS host is available on both
/// phones, has a CPU deadline and heap limit, and grants this guest no host
/// permissions. No WebView, remote solver service or account cookies are used.
class YoutubePlayerCipher {
  YoutubePlayerCipher(this.http, {YoutubeCipherEvaluator? evaluate})
    : _evaluate = evaluate ?? _evaluateNative;

  final DiscoveryHttp http;
  final YoutubeCipherEvaluator _evaluate;
  Uri? _playerUrl;
  Future<String>? _script;
  String? _preprocessed;

  void readPlayerUrl(String html) {
    final text =
        RegExp(r'"(?:jsUrl|PLAYER_JS_URL)"\s*:\s*"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        RegExp(r'''<script[^>]+src=["']([^"']*/s/player/[^"']+)["']''')
            .firstMatch(html)
            ?.group(1);
    if (text == null) return;
    final parsed = Uri.tryParse(text.replaceAll(r'\/', '/'));
    if (parsed == null) return;
    final url = Uri.https('www.youtube.com', '/').resolveUri(parsed);
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.port != 443 ||
        !{'www.youtube.com', 'music.youtube.com'}.contains(url.host) ||
        !url.path.startsWith('/s/player/') ||
        !url.path.endsWith('/base.js')) {
      return;
    }
    if (_playerUrl != null && _playerUrl != url) {
      _script = null;
      _preprocessed = null;
    }
    _playerUrl = url;
  }

  Future<String> _read(Uri url, Future<void>? cancel) async {
    final bytes = BytesBuilder(copy: false);
    await http.transfer(
      url,
      headers: const {'User-Agent': 'Mozilla/5.0'},
      maxBytes: 8 * 1024 * 1024,
      isMetadata: true,
      verifyContentLength: false,
      deadline: const Duration(seconds: 10),
      cancel: cancel,
      onChunk: bytes.add,
    );
    return utf8.decode(bytes.takeBytes());
  }

  Future<String> _loadScript(Future<void>? cancel) => _script ??= () async {
    if (_playerUrl == null) {
      readPlayerUrl(await _read(Uri.https('www.youtube.com', '/'), cancel));
    }
    final url = _playerUrl;
    if (url == null) {
      throw const DiscoveryException('YouTube player script is unavailable.');
    }
    return _read(url, cancel);
  }();

  Future<int?> signatureTimestamp({Future<void>? cancel}) async {
    try {
      final script = await _loadScript(cancel);
      return int.tryParse(
        RegExp(r'(?:signatureTimestamp|sts)\s*:\s*(\d{5,})')
                .firstMatch(script)
                ?.group(1) ??
            '',
      );
    } on DiscoveryException catch (error) {
      if (error.message == 'Request cancelled.') rethrow;
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, dynamic>> decipher(
    Map<String, dynamic> response, {
    Future<void>? cancel,
  }) async {
    final data = response['streamingData'];
    final formats = data is Map ? data['adaptiveFormats'] : null;
    if (formats is! List) return response;
    final candidates =
        <({Map<String, dynamic> format, Uri url, String? sig, String sp})>[];
    final signatures = <String>{};
    final throttles = <String>{};
    for (final format in formats) {
      if (format is! Map || !'${format['mimeType']}'.startsWith('audio/mp4')) {
        continue;
      }
      try {
        final cipher = Uri.splitQueryString(
          '${format['signatureCipher'] ?? format['cipher'] ?? ''}',
        );
        final url = Uri.tryParse('${format['url'] ?? cipher['url'] ?? ''}');
        if (url == null ||
            url.scheme != 'https' ||
            !url.host.endsWith('.googlevideo.com') ||
            url.userInfo.isNotEmpty) {
          continue;
        }
        final sig = cipher['s'];
        final n = url.queryParameters['n'];
        if (sig != null) signatures.add(sig);
        if (n != null) throttles.add(n);
        candidates.add((
          format: Map<String, dynamic>.from(format),
          url: url,
          sig: sig,
          sp: cipher['sp'] ?? 'signature',
        ));
      } on FormatException {
        // A malformed format must not discard other playable AAC renditions.
      }
    }
    if (signatures.isEmpty && throttles.isEmpty) return response;
    try {
      final script = await _loadScript(cancel);
      final modules = await Future.wait([
        rootBundle.loadString('assets/youtube/yt.solver.lib.min.js'),
        rootBundle.loadString('assets/youtube/yt.solver.core.min.js'),
      ]);
      final result = await _evaluate(
        '${modules[0]}\nObject.assign(globalThis, lib);\n${modules[1]}\n'
        'registerExtension({solve: input => jsc(input)});',
        {
          'type': _preprocessed == null ? 'player' : 'preprocessed',
          if (_preprocessed == null)
            'player': script
          else
            'preprocessed_player': _preprocessed,
          'output_preprocessed': true,
          'requests': [
            if (signatures.isNotEmpty)
              {'type': 'sig', 'challenges': signatures.toList()},
            if (throttles.isNotEmpty)
              {'type': 'n', 'challenges': throttles.toList()},
          ],
        },
        cancel,
      );
      final decoded = <String, String>{};
      if (result['type'] == 'result' && result['responses'] is List) {
        for (final item in result['responses'] as List) {
          if (item is! Map ||
              item['type'] != 'result' ||
              item['data'] is! Map) {
            continue;
          }
          for (final entry in (item['data'] as Map).entries) {
            if (entry.key is String &&
                entry.value is String &&
                (entry.value as String).isNotEmpty) {
              decoded[entry.key as String] = entry.value as String;
            }
          }
        }
      }
      if (result['preprocessed_player'] case final String code) {
        _preprocessed = code;
      }
      final playable = <Map<String, dynamic>>[];
      for (final candidate in candidates) {
        final n = candidate.url.queryParameters['n'];
        if ((candidate.sig != null && !decoded.containsKey(candidate.sig)) ||
            (n != null && !decoded.containsKey(n))) {
          continue;
        }
        final url = candidate.url.replace(
          queryParameters: {
            ...candidate.url.queryParameters,
            if (candidate.sig != null) candidate.sp: decoded[candidate.sig]!,
            if (n != null) 'n': decoded[n]!,
          },
        );
        playable.add({...candidate.format, 'url': url.toString()});
      }
      if (playable.isEmpty) throw StateError('No solved formats');
      return {
        ...response,
        'streamingData': {...data as Map, 'adaptiveFormats': playable},
      };
    } catch (error) {
      if (error is DiscoveryException &&
          error.message == 'Request cancelled.') {
        rethrow;
      }
      // Never return a ciphered or still-throttled URL as playable media.
      // Provider script errors can contain URLs, so expose a fixed reason.
      final plain = candidates.where(
        (c) => c.sig == null && !c.url.queryParameters.containsKey('n'),
      );
      if (plain.isNotEmpty) {
        return {
          ...response,
          'streamingData': {
            ...data as Map,
            'adaptiveFormats': plain.map((c) => c.format).toList(),
          },
        };
      }
      throw const DiscoveryException(
        'YouTube player signature decoding failed.',
      );
    }
  }

  static Future<Map<String, dynamic>> _evaluateNative(
    String code,
    Map<String, Object?> input,
    Future<void>? cancel,
  ) async {
    var cancelled = false;
    native.MorneyeEngine? guest;
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          cancelled = true;
          guest?.close();
        }),
      );
    }
    try {
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      final bootstrap = await rootBundle.loadString(
        'assets/youtube/sandbox.js',
      );
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      guest = await native.MorneyeEngine.start(
        code: code,
        bootstrap: bootstrap,
        configJson: '{"heapMb":256}',
        host: (_, _) => '{"failure":"YouTube solver has no host permissions."}',
      );
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      final result = await guest.invoke(
        method: 'solve',
        argsJson: jsonEncode([input]),
        timeoutMs: BigInt.from(10000),
      );
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      return jsonDecode(result) as Map<String, dynamic>;
    } catch (_) {
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      rethrow;
    } finally {
      guest?.close();
    }
  }
}
