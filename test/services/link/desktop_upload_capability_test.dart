import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late HttpServer server;
  late LokalRemoteCredentials credentials;
  late StreamSubscription<HttpRequest> requests;
  late void Function(HttpRequest) respond;
  late LokalDesktopSource source;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    credentials = LokalRemoteCredentials(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      remoteToken: 'synthetic-capability-token',
    );
    source = LokalDesktopSource(
      originalClientFactory: http.Client.new,
      iosLibraryMutations: true,
    );
    requests = server.listen((request) => respond(request));
  });
  tearDown(() async {
    await requests.cancel();
    await server.close(force: true);
  });
  void jsonReply(HttpRequest request, String document, {int status = 200}) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(document);
    unawaited(request.response.close());
  }

  test(
    'bounded authenticated capability uses no catalogue or audio request',
    () async {
      var count = 0;
      respond = (request) {
        count++;
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/remote/files/operations');
        expect(
          request.headers.value('x-remote-token'),
          'synthetic-capability-token',
        );
        jsonReply(request, '{"protocolVersion":1,"uploadOperations":1}');
      };
      expect(await source.supportsDurableUploadOperations(credentials), isTrue);
      expect(count, 1);
    },
  );
  for (final document in [
    '{}',
    '{"protocolVersion":1,"uploadOperations":0}',
    '{"protocolVersion":2,"uploadOperations":1}',
    '{"protocolVersion":1,"uploadOperations":true}',
    '{"protocolVersion":1,"uploadOperations":1.0}',
    '{"protocolVersion":1,"uploadOperations":1,"unexpected":1}',
    'not json',
    jsonEncode({
      'protocolVersion': 1,
      'uploadOperations': 1,
      'large': 'x' * 16384,
    }),
  ]) {
    test(
      'unsupported or malformed peer chooses foreground: ${document.length > 100 ? 'oversized' : document}',
      () async {
        respond = (request) => jsonReply(request, document);
        expect(
          await source.supportsDurableUploadOperations(credentials),
          isFalse,
        );
      },
    );
  }
  test('legacy missing endpoint and redirects never send another authenticated request', () async {
    var count = 0;
    respond = (request) {
      count++;
      request.response.statusCode = HttpStatus.temporaryRedirect;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        '/redirect-target',
      );
      unawaited(request.response.close());
    };
    expect(await source.supportsDurableUploadOperations(credentials), isFalse);
    expect(count, 1);
    respond = (request) { count++; jsonReply(request, '{}', status: 404); };
    expect(await source.supportsDurableUploadOperations(credentials), isFalse);
    expect(count, 2);
  });
  test('chunked oversized response cannot evade the body bound', () async {
    respond = (request) {
      request.response.headers.contentType = ContentType.json;
      request.response.bufferOutput = false;
      request.response.write(' ' * 8192);
      unawaited(
        request.response.flush().then((_) async {
          request.response.write(' ' * 8192);
          request.response.write('{"protocolVersion":1,"uploadOperations":1}');
          await request.response.close();
        }),
      );
    };
    expect(await source.supportsDurableUploadOperations(credentials), isFalse);
  });
  test(
    'a held capability connection closes before library mutation completes',
    () async {
      final started = Completer<void>();
      respond = (request) {
        started.complete();
      };
      final pending = source.supportsDurableUploadOperations(credentials);
      await started.future;
      var mutated = false;
      await source
          .withLibraryTransfersDrained(() async {
            mutated = true;
          })
          .timeout(const Duration(seconds: 2));
      expect(await pending, isFalse);
      expect(mutated, isTrue);
    },
  );
}
