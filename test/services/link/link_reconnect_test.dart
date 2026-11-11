import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/link/link_protocol.dart';
import 'package:flick/services/link/lokal_link_service.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:http/io_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttpOverrides extends HttpOverrides {}

const token = 'synthetic-persisted-token';
const desktopId = 'desktop-fixture', deviceId = 'phone-fixture';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'lokal.link.device_id': deviceId,
    }),
  );
  tearDown(
    () => messenger.setMockMethodCallHandler(LokalLinkService.channel, null),
  );

  for (final validProof in [true, false]) {
    test(
      validProof
          ? 'a changed LAN address recovers using the original token after identity proof'
          : 'an unverified discovered address never receives the saved bearer',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[];
        addTearDown(() async {
          for (final socket in sockets) {
            await socket.close();
          }
          await server.close(force: true);
        });
        final origin = Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
        );
        final calls = <String>[];
        server.listen((request) async {
          calls.add(request.uri.path);
          if (request.uri.path == '/api/remote/identity') {
            expect(request.headers.value('x-remote-token'), isNull);
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            final proof =
                Hmac(
                      sha256,
                      sha256
                          .convert(
                            utf8.encode(validProof ? token : 'wrong-pairing'),
                          )
                          .bytes,
                    )
                    .convert(
                      utf8.encode(
                        jsonEncode([
                          'lokal-link-identity-v1',
                          body['challenge'],
                          desktopId,
                          deviceId,
                          'owner',
                        ]),
                      ),
                    )
                    .toString();
            request.response.write(
              jsonEncode({
                'desktopId': desktopId,
                'userId': 'owner',
                'proof': proof,
              }),
            );
            await request.response.close();
          } else {
            expect(request.headers.value('x-remote-token'), token);
            final socket = await WebSocketTransformer.upgrade(request);
            sockets.add(socket);
            socket.listen((raw) {
              final message = LinkMessage.decode(raw as String);
              socket.add(
                LinkMessage.create('ack', {
                  'ok': true,
                }, id: message.id).encode(),
              );
            });
          }
        });
        messenger.setMockMethodCallHandler(
          LokalLinkService.channel,
          (call) async => call.method == 'discover'
              ? [
                  {
                    'id': 'another-desktop',
                    'host': origin.host,
                    'port': origin.port,
                  },
                  {'id': desktopId, 'host': origin.host, 'port': origin.port},
                ]
              : true,
        );
        final service = LokalLinkService(
          identityClient: IOClient(_RealHttpOverrides().createHttpClient(null)),
        );
        addTearDown(service.close);
        // Port zero refuses immediately; no external host or fixed port required.
        final credentials = LokalRemoteCredentials(
          origin: Uri.parse('http://127.0.0.1:0'),
          remoteToken: token,
          desktopId: desktopId,
          desktopUserId: 'owner',
        );
        if (!validProof) {
          await expectLater(
            service.connect(credentials),
            throwsA(isA<SocketException>()),
          );
          expect(service.connected, isFalse);
          expect(calls, ['/api/remote/identity']);
          return;
        }
        expect(await service.connect(credentials), origin);
        expect(service.connected, isTrue);
        expect(calls, ['/api/remote/identity', '/api/remote/ws']);
        expect(
          (await service.request('command', {'action': 'pause'})).body['ok'],
          isTrue,
        );
      },
    );
  }

  for (final disconnect in [false, true]) {
    test(
      disconnect
          ? 'Disconnect retires a pending handshake'
          : 'late older handshake cannot replace the newer socket',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final firstRequest = Completer<HttpRequest>();
        final sockets = <WebSocket>[];
        addTearDown(() async {
          for (final socket in sockets) {
            await socket.close();
          }
          await server.close(force: true);
        });
        var count = 0;
        server.listen((request) async {
          if (++count == 1) {
            firstRequest.complete(request);
            return;
          }
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((_) {});
        });
        messenger.setMockMethodCallHandler(
          LokalLinkService.channel,
          (_) async => true,
        );
        final service = LokalLinkService();
        addTearDown(service.close);
        final credentials = LokalRemoteCredentials(
          origin: Uri.parse('http://127.0.0.1:${server.port}'),
          remoteToken: token,
        );
        final first = service.connect(credentials);
        final rejected = expectLater(
          first,
          throwsA(isA<LokalRemoteNetworkException>()),
        );
        final request = await firstRequest.future;
        if (disconnect) {
          await service.disconnect();
        } else {
          await service.connect(credentials);
        }
        final old = await WebSocketTransformer.upgrade(request);
        sockets.add(old);
        final oldClosed = Completer<void>();
        old.listen((_) {}, onDone: oldClosed.complete);
        await rejected;
        await oldClosed.future.timeout(const Duration(seconds: 2));
        expect(service.connected, !disconnect);
      },
    );
  }
}
