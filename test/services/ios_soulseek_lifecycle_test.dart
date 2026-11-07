import 'dart:async';
import 'dart:convert';

import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/services/soulseek_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'library mutation durably retires the peer queue before deletion',
    () async {
      SharedPreferences.setMockInitialValues({
        'lokal.soulseek.pending.v1': [
          jsonEncode({
            'username': 'peer',
            'filename': 'album/file.wav',
            'size': 123,
            'path': '/private-fixture-staging/file.wav',
          }),
        ],
      });
      final calls = <String>[];
      final service = SoulseekService.testing(
        ios: true,
        nativeCall: (action, args) async {
          calls.add(action);
          return {};
        },
      )..connected = true;
      addTearDown(service.dispose);
      await LokalDesktopSource.instance.withLibraryTransfersDrained(() async {
        expect(service.connected, false);
        expect(service.pendingCount, 0);
        expect(calls, ['logout']);
        expect(
          (await SharedPreferences.getInstance()).getStringList(
            'lokal.soulseek.pending.v1',
          ),
          isEmpty,
        );
      });
    },
  );

  test(
    'suspension retires a held status reply and does not auto reconnect',
    () async {
      final status = Completer<Map<String, dynamic>>();
      final calls = <String>[];
      final service =
          SoulseekService.testing(
              ios: true,
              nativeCall: (action, args) async {
                calls.add(action);
                if (action == 'status') return status.future;
                throw StateError('Unexpected native work: $action');
              },
            )
            ..connected = true
            ..shareEnabled = true
            ..sharedFiles = 2;
      addTearDown(service.dispose);
      final refresh = service.refresh();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.connected, false);
      expect(service.shareEnabled, false);
      expect(service.sharedFiles, 0);
      status.complete({'loggedIn': true});
      await refresh;
      expect(calls, ['status']);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, ['status']);
      expect(service.connected, false);
    },
  );

  test(
    'background refuses new searches before native or secure storage work',
    () async {
      final calls = <String>[];
      final service = SoulseekService.testing(
        ios: true,
        nativeCall: (action, args) async {
          calls.add(action);
          return {};
        },
      );
      addTearDown(service.dispose);
      service.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await expectLater(service.search('artist'), throwsStateError);
      expect(calls, isEmpty);
    },
  );

  test('inactive system overlays leave an active peer session intact', () {
    final service = SoulseekService.testing(ios: true)..connected = true;
    addTearDown(service.dispose);
    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(service.connected, true);
  });
}
