import 'dart:convert';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _SequenceClient extends http.BaseClient {
  _SequenceClient(this.responses);

  final List<http.StreamedResponse> responses;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return responses.removeAt(0);
  }
}

http.StreamedResponse _reply(
  String body, {
  int? contentLength,
  int status = 200,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    status,
    contentLength: contentLength ?? utf8.encode(body).length,
  );
}

void main() {
  final manifestUrl =
      Uri.parse('https://addons.example/a/fixture-token/manifest.json');
  const manifest = '{"id":"fixture","resources":["search","stream"]}';

  test('valid manifest survives decompressed Content-Length disagreement',
      () async {
    final client = _SequenceClient([_reply(manifest, contentLength: 8)]);
    addTearDown(client.close);

    final data = await DiscoveryHttp(client).json(manifestUrl);
    expect(data['id'], 'fixture');
    expect(client.requests, hasLength(1));
  });

  test('empty 200 manifest retries once without caching or compression',
      () async {
    final client = _SequenceClient([_reply(''), _reply(manifest)]);
    addTearDown(client.close);

    final data = await DiscoveryHttp(client).json(
      manifestUrl,
      headers: const {
        'X-LW-TS': '1700000000',
        'X-LW-Sign': 'fixture-signature',
      },
    );
    expect(data['id'], 'fixture');
    expect(client.requests, hasLength(2));
    expect(client.requests[0].url, manifestUrl);
    expect(client.requests[1].url, manifestUrl);
    expect(client.requests[1].headers['X-LW-Sign'], 'fixture-signature');
    expect(client.requests[1].headers['X-LW-TS'], '1700000000');
    expect(client.requests[1].headers['Accept-Encoding'], 'identity');
    expect(client.requests[1].headers['Cache-Control'], 'no-cache');
    expect(client.requests[1].headers['Connection'], 'close');
  });

  test('persistently empty 200 manifest fails after one retry', () async {
    final client = _SequenceClient([_reply(''), _reply('')]);
    addTearDown(client.close);

    await expectLater(
      DiscoveryHttp(client).json(manifestUrl),
      throwsA(
        isA<DiscoveryException>().having(
          (error) => error.message,
          'message',
          'The source returned an empty or incomplete response.',
        ),
      ),
    );
    expect(client.requests, hasLength(2));
  });

  test('truncated JSON still fails rather than accepting partial metadata',
      () async {
    final client = _SequenceClient([
      _reply('{"id":"fixture"', contentLength: 200),
    ]);
    addTearDown(client.close);

    await expectLater(
      DiscoveryHttp(client).json(manifestUrl),
      throwsA(
        isA<DiscoveryException>().having(
          (error) => error.message,
          'message',
          'The source returned invalid JSON.',
        ),
      ),
    );
    expect(client.requests, hasLength(1));
  });

  test('audio transfer retains strict Content-Length validation', () async {
    final client = _SequenceClient([_reply('audio', contentLength: 40)]);
    addTearDown(client.close);

    await expectLater(
      DiscoveryHttp(client).transfer(
        Uri.parse('https://cdn.example/track.flac'),
        maxBytes: 128,
        deadline: const Duration(seconds: 2),
        onChunk: (_) {},
      ),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('HTTP access denials are not retried as empty metadata', () async {
    final client = _SequenceClient([_reply('', status: 403)]);
    addTearDown(client.close);

    await expectLater(
      DiscoveryHttp(client).json(manifestUrl),
      throwsA(
        isA<DiscoveryException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 403'),
        ),
      ),
    );
    expect(client.requests, hasLength(1));
  });
}
