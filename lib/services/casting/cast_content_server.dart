import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../sources/local_network_access.dart';
import 'cast_lan_address.dart';

// ponytail: one-file embedded HTTP server so the renderer can pull bytes from
// the phone. Covers local files and SMB/cached sources that have no LAN URL.
// Token paths on a home LAN are enough auth; add TLS/pins if this ever leaves
// the house.
class CastContentServer {
  CastContentServer._();
  static final instance = CastContentServer._();

  HttpServer? _server;
  int _epoch = 0;
  final Map<String, String> _paths = {};
  final Map<String, ({Uri uri, Map<String, String> headers})> _relays = {};
  final Set<HttpClient> _clients = {};
  final Map<String, ContentType> _types = {};
  final _rand = Random.secure();

  /// Serve [filePath] and return a LAN-reachable URL for it.
  Future<String> serve(
    String filePath, {
    required String filename,
    ContentType? contentType,
    bool Function()? stillCurrent,
  }) => _publish(
    filename: filename,
    filePath: filePath,
    contentType: contentType,
    stillCurrent: stillCurrent,
  );

  /// A receiver gets an opaque LAN URL. PC credentials stay on this phone;
  /// Range requests stream immediately instead of downloading the entire song.
  Future<String> relay(
    String url, {
    required String filename,
    required Map<String, String> headers,
    bool Function()? stillCurrent,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      throw ArgumentError('Cast relay requires an HTTP source.');
    return _publish(
      filename: filename,
      remote: (uri: uri, headers: Map.unmodifiable(headers)),
      stillCurrent: stillCurrent,
    );
  }

  Future<String> _publish({
    required String filename,
    String? filePath,
    ({Uri uri, Map<String, String> headers})? remote,
    ContentType? contentType,
    bool Function()? stillCurrent,
  }) async {
    final epoch = _epoch;
    bool current() => epoch == _epoch && (stillCurrent?.call() ?? true);
    if (!current()) throw StateError('Cast source was cancelled.');
    final ip = await _lanIp();
    if (!current()) throw StateError('Cast source was cancelled.');
    await NetworkLocalAccess.ensure(Uri(scheme: 'http', host: ip));
    if (!current()) throw StateError('Cast session ended.');
    var server = _server;
    if (server == null) {
      final opened = await _bind();
      if (!current()) {
        await opened.close(force: true);
        throw StateError('Cast session ended.');
      }
      if (_server != null) {
        await opened.close(force: true);
        if (!current() || _server == null)
          throw StateError('Cast session ended.');
        server = _server!;
      } else {
        _server = server = opened;
      }
    }
    if (!current()) throw StateError('Cast source was cancelled.');
    final token = _token();
    if (filePath != null) _paths[token] = filePath;
    if (remote != null) _relays[token] = remote;
    if (contentType != null) _types[token] = contentType;
    final safe = Uri.encodeComponent(
      filename.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]'), ''),
    );
    return 'http://$ip:${server.port}/$token/$safe';
  }

  Future<void> stop() async {
    ++_epoch;
    _paths.clear();
    _relays.clear();
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
    _types.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  String _token() {
    final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((req) {
      _handle(req).catchError((_) {
        try {
          req.response.close();
        } catch (_) {}
      });
    }, onError: (_) {});
    return server;
  }

  Future<String> _lanIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final address = castLanAddress({
      for (final network in interfaces)
        network.name: network.addresses.map((address) => address.address),
    });
    if (address == null)
      throw const SocketException(
        'Connect to Wi-Fi or Ethernet to cast local audio.',
      );
    return address;
  }

  Future<void> _handle(HttpRequest req) async {
    final head = req.method == 'HEAD';
    final preflight = req.method == 'OPTIONS';
    // The Cast web receiver fetches this token-scoped LAN URL across origins.
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set(
      'Access-Control-Expose-Headers',
      'Content-Length, Content-Range, Accept-Ranges',
    );
    if (req.method != 'GET' && !head && !preflight) {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      req.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD, OPTIONS');
      req.response.contentLength = 0;
      await req.response.close();
      return;
    }
    final token = req.uri.pathSegments.isNotEmpty
        ? req.uri.pathSegments.first
        : '';
    final path = _paths[token];
    final remote = _relays[token];
    if (path == null && remote == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    if (preflight) {
      req.response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, HEAD, OPTIONS',
      );
      req.response.headers.set(
        'Access-Control-Allow-Headers',
        'Range, Content-Type',
      );
      if (req.headers.value('Access-Control-Request-Private-Network') ==
          'true') {
        req.response.headers.set(
          'Access-Control-Allow-Private-Network',
          'true',
        );
      }
      req.response.statusCode = HttpStatus.noContent;
      await req.response.close();
      return;
    }
    if (remote != null) {
      await _relay(req, remote);
      return;
    }
    final file = File(path!);
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final total = await file.length();
    // Range only applies to GET. Ignore unsupported/malformed/multipart ranges
    // rather than returning a partial body with incorrect framing (RFC 9110).
    final range = head ? null : req.headers.value(HttpHeaders.rangeHeader);

    var start = 0;
    var end = total - 1;
    var status = HttpStatus.ok;
    if (range != null) {
      final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (m != null && (m.group(1)!.isNotEmpty || m.group(2)!.isNotEmpty)) {
        final first = m.group(1)!;
        final last = m.group(2)!;
        final size = BigInt.from(total);
        final requestedStart = first.isEmpty ? null : BigInt.parse(first);
        final requestedEnd = last.isEmpty ? null : BigInt.parse(last);
        final unsatisfiable =
            total == 0 ||
            (requestedStart == null && requestedEnd == BigInt.zero) ||
            (requestedStart != null &&
                (requestedStart >= size ||
                    (requestedEnd != null && requestedEnd < requestedStart)));
        if (unsatisfiable) {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$total',
          );
          req.response.contentLength = 0;
          await req.response.close();
          return;
        }
        if (requestedStart == null) {
          // Suffix range: bytes=-10 is the last ten bytes, including a suffix
          // larger than the file. BigInt prevents oversized headers wrapping.
          start = requestedEnd! >= size ? 0 : (size - requestedEnd).toInt();
        } else {
          start = requestedStart.toInt();
          if (requestedEnd != null && requestedEnd < size) {
            end = requestedEnd.toInt();
          }
        }
        status = HttpStatus.partialContent;
      }
    }

    final length = end - start + 1;
    req.response.statusCode = status;
    req.response.headers.contentType = _types[token] ?? _contentTypeFor(path);
    req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    req.response.headers.set(HttpHeaders.contentLengthHeader, '$length');
    if (status == HttpStatus.partialContent) {
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }

    if (head || length == 0) {
      await req.response.close();
      return;
    }

    // ponytail: chunked manual copy; StreamedResponse plumbing adds nothing
    // for a LAN-local single consumer.
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      var remaining = length;
      const chunk = 64 * 1024;
      while (remaining > 0) {
        final read = await raf.read(min(chunk, remaining));
        if (read.isEmpty) break;
        req.response.add(read);
        remaining -= read.length;
        await req.response.flush();
      }
    } finally {
      await raf.close();
      await req.response.close();
    }
  }

  Future<void> _relay(
    HttpRequest request,
    ({Uri uri, Map<String, String> headers}) remote,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _clients.add(client);
    var finished = false;
    request.response.done.then<void>(
      (_) {
        if (!finished) client.close(force: true);
      },
      onError: (Object _, StackTrace _) {
        client.close(force: true);
      },
    );
    try {
      final upstreamRequest = await client
          .openUrl(request.method, remote.uri)
          .timeout(const Duration(seconds: 15));
      // Credentials must never follow a desktop redirect to another origin.
      upstreamRequest.followRedirects = false;
      remote.headers.forEach(upstreamRequest.headers.set);
      upstreamRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (request.method == 'GET' &&
          range != null &&
          RegExp(r'^bytes=\d*-\d*$').hasMatch(range))
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
      final upstream = await upstreamRequest.close().timeout(
        const Duration(seconds: 15),
      );
      final allowed = {200, 206, 404, 416};
      if (!allowed.contains(upstream.statusCode)) {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.contentLength = 0;
        return;
      }
      request.response.statusCode = upstream.statusCode;
      if (upstream.statusCode == 404 || upstream.statusCode == 416) {
        final range = upstream.headers.value(HttpHeaders.contentRangeHeader);
        if (upstream.statusCode == 416 && range != null)
          request.response.headers.set(HttpHeaders.contentRangeHeader, range);
        request.response.contentLength = 0;
        return;
      }
      for (final header in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upstream.headers.value(header);
        if (value != null) request.response.headers.set(header, value);
      }
      if (request.method != 'HEAD') {
        request.response.bufferOutput = false;
        await request.response.flush();
        await request.response.addStream(
          upstream.timeout(const Duration(seconds: 20)),
        );
      }
    } catch (_) {
      // No upstream URLs, account headers or provider error bodies reach the TV.
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      finished = true;
      client.close(force: true);
      _clients.remove(client);
      await request.response.close();
    }
  }
}

ContentType _contentTypeFor(String path) {
  final ext = path.lastIndexOf('.') == -1
      ? ''
      : path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => ContentType.parse('image/jpeg'),
    'png' => ContentType.parse('image/png'),
    'webp' => ContentType.parse('image/webp'),
    'gif' => ContentType.parse('image/gif'),
    'mp3' => ContentType.parse('audio/mpeg'),
    'flac' => ContentType.parse('audio/flac'),
    'wav' => ContentType.parse('audio/wav'),
    'ogg' || 'oga' || 'opus' => ContentType.parse('audio/ogg'),
    'm4a' || 'mp4' => ContentType.parse('audio/mp4'),
    'aac' => ContentType.parse('audio/aac'),
    'aiff' || 'aif' => ContentType.parse('audio/aiff'),
    'wv' => ContentType.parse('audio/x-wavpack'),
    'dsf' || 'dff' => ContentType.parse('audio/dsd'),
    _ => ContentType.binary,
  };
}
