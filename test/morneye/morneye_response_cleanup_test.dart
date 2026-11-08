import 'dart:async';
import 'dart:io';

import 'package:flick/features/morneye/morneye_network.dart';
import 'package:flutter_test/flutter_test.dart';

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.stream);
  final Stream<List<int>> stream;
  int detached = 0;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<Socket> detachSocket() async {
    detached++;
    throw StateError('Ordinary HTTP responses must never detach sockets');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MorneyeResponse _wrap(_Response response) => MorneyeResponse(
  Uri.https('media.example', '/audio'),
  200,
  const {},
  response,
);

void main() {
  test(
    'completed media cleanup leaves the connection pool to HttpClient',
    () async {
      final raw = _Response(Stream.value([1, 2, 3]));
      final response = _wrap(raw);
      expect(await response.body.expand((bytes) => bytes).toList(), [1, 2, 3]);
      await response.close();
      await response.close();
      expect(raw.detached, 0);
    },
  );

  test(
    'unread error response is cancelled without detaching its socket',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final raw = _Response(stream.stream);
      await _wrap(raw).close();
      expect(cancelled, isTrue);
      expect(raw.detached, 0);
      await stream.close();
    },
  );

  test('active media cancellation cancels its existing subscription', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final raw = _Response(stream.stream);
    final response = _wrap(raw);
    response.body.listen((_) {});
    stream.add([1, 2]);
    await response.close();
    expect(cancelled, isTrue);
    expect(raw.detached, 0);
    await stream.close();
  });

  test('repeated real HTTP responses can finish and close normally', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    final net = MorneyeNetwork(
      const MorneyePermissions(network: ['127.0.0.1'], allowHttp: true),
    );
    try {
      for (var i = 0; i < 20; i++) {
        final response = await net.request(
          'http://127.0.0.1:${server.port}/audio',
        );
        expect(await response.body.expand((bytes) => bytes).toList(), [
          1,
          2,
          3,
          4,
        ]);
        await response.close();
      }
    } finally {
      net.close();
      await server.close(force: true);
    }
  });
}
