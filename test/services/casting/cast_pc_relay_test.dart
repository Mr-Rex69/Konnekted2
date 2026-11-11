import 'dart:async';
import 'dart:io';

import 'package:flick/services/casting/cast_content_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final previousHttp = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = previousHttp);
  Future<List<int>> bytes(HttpClientResponse response) =>
      response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));

  test('PC relay is ready before a full download, preserves ranges and keeps credentials private', () async {
    await binding.runAsync(() async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final relay = CastContentServer.instance;
      final client = HttpClient();
      final pending = Completer<void>();
      final requests = <(String, String?)>[];
      final fullOpened = Completer<void>();
      upstream.listen((request) async {
        expect(
          request.headers.value('x-remote-token'),
          'private-pairing-token',
        );
        requests.add((request.method, request.headers.value('range')));
        request.response.headers.set('x-remote-token', 'never-forward');
        request.response.headers.contentType = ContentType('audio', 'flac');
        request.response.headers.set('Accept-Ranges', 'bytes');
        if (request.method == 'HEAD') {
          request.response.contentLength = 100;
        } else if (request.headers.value('range') == 'bytes=10-19') {
          request.response.statusCode = 206;
          request.response.headers.set('Content-Range', 'bytes 10-19/100');
          request.response.contentLength = 10;
          request.response.add(List.generate(10, (i) => i + 10));
        } else {
          request.response.contentLength = 100;
          request.response.add(List.filled(10, 1));
          await request.response.flush();
          fullOpened.complete();
          await pending.future;
          request.response.add(List.filled(90, 2));
        }
        await request.response.close();
      });
      try {
        Future<Uri> publish(String id) async {
          final url = await relay.relay(
            'http://127.0.0.1:${upstream.port}/api/stream/$id',
            filename: 'track.flac',
            headers: {'x-remote-token': 'private-pairing-token'},
          );
          expect(url, isNot(contains('private-pairing-token')));
          expect(url, isNot(contains('/api/stream/')));
          return Uri.parse(url).replace(host: '127.0.0.1');
        }

        final first = await publish('first');
        expect(
          requests,
          isEmpty,
          reason: 'Preparation must not wait for any PC bytes',
        );
        final full = await (await client.getUrl(first))
            .close()
            .timeout(const Duration(seconds: 5));
        expect(full.statusCode, 200);
        final fullBody = bytes(full);
        await fullOpened.future.timeout(const Duration(seconds: 5));
        expect(pending.isCompleted, false);
        // Skip while a preceding source is still streaming: the next URL and
        // ranged read must not wait for that full-song transfer to finish.
        final second = await publish('next');
        final range = await client.getUrl(second);
        range.headers.set('Range', 'bytes=10-19');
        final response = await range.close();
        expect(response.statusCode, 206);
        expect(response.headers.value('Content-Range'), 'bytes 10-19/100');
        expect(response.headers.value('x-remote-token'), isNull);
        expect(response.headers.contentType?.mimeType, 'audio/flac');
        expect(await bytes(response), List.generate(10, (i) => i + 10));
        final head = await (await client.openUrl('HEAD', second)).close();
        expect(head.contentLength, 100);
        expect(await bytes(head), isEmpty);
        pending.complete();
        expect((await fullBody).length, 100);
        expect(requests, contains(('GET', 'bytes=10-19')));
      } finally {
        if (!pending.isCompleted) pending.complete();
        client.close(force: true);
        await relay.stop();
        await upstream.close(force: true);
      }
    });
  });

  test('PC credentials never follow redirects and cancelled preparations cannot publish', () async {
    await binding.runAsync(() async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var otherRequests = 0;
      other.listen((request) {
        otherRequests++;
        request.response.close();
      });
      upstream.listen((request) {
        request.response.statusCode = 302;
        request.response.headers.set(
          'Location',
          'http://127.0.0.1:${other.port}/stolen',
        );
        request.response.close();
      });
      final relay = CastContentServer.instance;
      final client = HttpClient();
      try {
        final source = 'http://127.0.0.1:${upstream.port}/api/stream/song';
        await expectLater(
          relay.relay(
            source,
            filename: 'track.flac',
            headers: {'x-remote-token': 'private'},
            stillCurrent: () => false,
          ),
          throwsStateError,
        );
        var current = true;
        final cancelled = relay.relay(
          source,
          filename: 'track.flac',
          headers: {'x-remote-token': 'private'},
          stillCurrent: () => current,
        );
        current = false;
        await expectLater(cancelled, throwsStateError);
        final url = await relay.relay(
          source,
          filename: 'track.flac',
          headers: {'x-remote-token': 'private'},
        );
        final request = await client.getUrl(
          Uri.parse(url).replace(host: '127.0.0.1'),
        );
        final response = await request.close();
        expect(response.statusCode, 502);
        expect(response.headers.value('Location'), isNull);
        expect(await bytes(response), isEmpty);
        expect(otherRequests, 0);
      } finally {
        client.close(force: true);
        await relay.stop();
        await upstream.close(force: true);
        await other.close(force: true);
      }
    });
  });

  test(
    'encoded upstream bytes cannot corrupt the receiver range framing',
    () async {
      await binding.runAsync(() async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        upstream.listen((request) async {
          request.response.headers.set('Content-Encoding', 'gzip');
          request.response.headers.contentType = ContentType('audio', 'flac');
          request.response.add(gzip.encode(List.filled(100, 1)));
          await request.response.close();
        });
        final relay = CastContentServer.instance;
        final client = HttpClient();
        try {
          final url = await relay.relay(
            'http://127.0.0.1:${upstream.port}/song',
            filename: 'track.flac',
            headers: {},
          );
          final response = await (await client.getUrl(
            Uri.parse(url).replace(host: '127.0.0.1'),
          )).close();
          expect(response.statusCode, 502);
          expect(await bytes(response), isEmpty);
          expect(response.headers.value('Content-Encoding'), isNull);
        } finally {
          client.close(force: true);
          await relay.stop();
          await upstream.close(force: true);
        }
      });
    },
  );
}
