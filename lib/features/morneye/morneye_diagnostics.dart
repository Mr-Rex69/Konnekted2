import 'dart:io';

import '../../core/utils/app_log.dart';
import '../../core/utils/online_source_log_label.dart';

/// Export only closed diagnostic categories. Add-on errors and results can
/// contain signed URLs, tokens, paths and listener metadata; never log them.
String morneyeFailureKind(Object? error) {
  final message = '$error'.toLowerCase();
  if (RegExp(r'cancelled|canceled|runtime closed').hasMatch(message)) {
    return 'cancelled';
  }
  if (RegExp(
    r'verify_required|verification_required|needs.?verification|verify.*(?:required|access)',
  ).hasMatch(message)) {
    return 'verification_required';
  }
  final status = RegExp(r'(?:http|status(?:code)?)\s*[:=]?\s*(\d{3})\b')
      .firstMatch(message)
      ?.group(1);
  if (status != null) return 'http_$status';
  if (RegExp(
    r'not_found|no .*track match|cannot download this track|unavailable|not available',
  ).hasMatch(message)) {
    return 'recording_unavailable';
  }
  if (RegExp(r'auth|login|sign.?in|expired|credential').hasMatch(message)) {
    return 'authentication';
  }
  if (RegExp(r'timeout|timed out|stalled|stopped delivering')
      .hasMatch(message)) {
    return 'timeout';
  }
  if (RegExp(r'out of memory|allocation|heap limit').hasMatch(message)) {
    return 'runtime_memory';
  }
  if (RegExp(r'typeerror|referenceerror|not a function|undefined|null value')
      .hasMatch(message)) {
    return 'runtime_script';
  }
  if (RegExp(r'json|parse|syntaxerror').hasMatch(message)) {
    return 'invalid_response';
  }
  if (RegExp(r'permission|requires https|private address').hasMatch(message)) {
    return 'permission';
  }
  if (message.contains('decrypt')) return 'decryption';
  if (RegExp(r'spatial|atmos|ac-?4|e-ac-?3').hasMatch(message)) {
    return 'spatial_format';
  }
  if (message.contains('duration')) return 'duration_mismatch';
  if (message.contains('empty file')) return 'empty_media';
  if (RegExp(r'codec|container|can.t play').hasMatch(message)) {
    return 'unsupported_media';
  }
  if (RegExp(r'socket|handshake|connection|network|dns|host lookup')
      .hasMatch(message)) {
    return 'network';
  }
  return 'provider_error';
}

String morneyeDiagnosticProvider(String name) => switch (name.toLowerCase()) {
  'amazon' || 'amazon-new' || 'amazon-web' => 'amazon',
  'deezer' || 'deezer-web' => 'deezer',
  'tidal' || 'tidal-web' => 'tidal',
  'qobuz' || 'qobuz-web' => 'qobuz',
  'soundcloud' => 'soundcloud',
  'ytmusic-spotiflac' => 'youtube',
  _ => 'custom',
};

class MorneyeDiagnostics {
  MorneyeDiagnostics({
    required String name,
    required String key,
    required String version,
    String mode = 'browse',
  }) : provider = morneyeDiagnosticProvider(name),
       source = onlineSourceLogLabel('a-$key'),
       version =
           RegExp(r'^\d+(?:\.\d+){1,3}(?:-[a-zA-Z0-9.]+)?$').hasMatch(version)
           ? version
           : 'unknown',
       mode = {'browse', 'playback', 'download'}.contains(mode)
           ? mode
           : 'browse',
       attempt = '${_run}_${++_serial}';

  static final _run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  static int _serial = 0;
  final String mode;
  final String attempt;
  final String provider;
  final String source;
  final String version;
  final Stopwatch _clock = Stopwatch()..start();

  static const _methods = {
    'initialize',
    'getTrack',
    'searchTracks',
    'customSearch',
    'handleUrl',
    'checkAvailability',
    'enrichTrack',
    'download',
    'postProcessV2',
  };
  static const _hostMethods = {
    'http.get',
    'http.post',
    'http.request',
    'http.fetch',
    'session.signedFetch',
    'session.status',
    'file.download',
    'file.downloadSegments',
    'file.transformPatternedBlocks',
    'ffmpeg.convert',
    'ffmpeg.getInfo',
  };

  void stage(String stage) => _write('stage=$stage');

  void quality(String quality) {
    final value = quality.toLowerCase();
    const known = {
      'best',
      'high',
      'auto',
      'default',
      'flac',
      'flac_24',
      'aac',
      'mp3',
      'mp3_320',
      'opus',
      'ac4',
      'eac3',
      'lossless',
      'hi_res_lossless',
      'dolby_atmos',
    };
    _write('quality=${known.contains(value) ? value : 'custom'}');
  }

  void metadata(Map track) => _write(
    'metadata_present=true '
    'has_title=${'${track['name'] ?? ''}'.trim().isNotEmpty} '
    'has_artist=${'${track['artists'] ?? ''}'.trim().isNotEmpty} '
    'has_isrc=${'${track['isrc'] ?? ''}'.trim().isNotEmpty}',
  );

  void method(String method, {Object? error, bool finished = false}) {
    if (!_methods.contains(method)) return;
    _write(
      'method=$method outcome=${error != null
          ? 'failed'
          : finished
          ? 'complete'
          : 'start'}'
      '${error == null ? '' : ' reason=${morneyeFailureKind(error)}'}',
    );
  }

  void host(String method, Object? result, {Object? error}) {
    if (!_hostMethods.contains(method)) return;
    final status = result is Map
        ? result['statusCode'] ?? result['status']
        : null;
    final failed =
        error != null ||
        (status is num && status >= 400) ||
        (result is Map &&
            (result['success'] == false ||
                result['ok'] == false ||
                result['needsVerification'] == true));
    final reason =
        error ??
        (result is Map ? result['error'] ?? result['error_message'] : null);
    _write(
      'host=$method outcome=${failed ? 'failed' : 'complete'}'
      '${status is num && status >= 100 && status <= 599 ? ' http=${status.toInt()}' : ''}'
      '${failed ? ' reason=${morneyeFailureKind(status is num && status >= 400 ? 'HTTP $status' : reason)}' : ''}',
    );
  }

  void availability(Object? result) {
    final available = result is Map && result['available'] == true;
    _write(
      'availability=${available ? 'available' : 'unavailable'}'
      '${available ? '' : ' reason=${morneyeFailureKind(result is Map ? result['reason'] : 'invalid JSON response')}'}',
    );
  }

  void failure(String stage, Object error) =>
      _write('stage=$stage outcome=failed reason=${morneyeFailureKind(error)}');

  void _write(String detail) {
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
        ? 'android'
        : 'other';
    AppLog.instance.add(
      '[Addon playback] attempt=$attempt provider=$provider '
      'version=$version source=$source platform=$platform mode=$mode $detail elapsedMs=${_clock.elapsedMilliseconds}',
    );
  }
}
