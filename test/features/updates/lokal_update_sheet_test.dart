import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/features/updates/lokal_update_sheet.dart';
import 'package:flick/providers/update_check_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AvailableUpdate extends UpdateCheckNotifier {
  @override
  UpdateCheckState build() => const UpdateCheckState(
    flavor: 'full',
    release: LokalUpdateRelease(
      version: '1.0.0',
      build: 200,
      downloadUrl: 'https://github.com/Lokal-Konnekt/lokal-mobile/releases/download/v1.0.0/Lokal-1.0.0-universal.apk',
      sha256: 'hash',
      pageUrl: lokalUpdateReleasesUrl,
      notes: '',
    ),
  );
}

void main() {
  testWidgets(
    'offer waits for user; download leads to explicit Android install and permission guidance',
    (tester) async {
      const channel = MethodChannel('lokal/app_update');
      final calls = <MethodCall>[];
      var ready = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        switch (call.method) {
          case 'download':
            ready = true;
            return null;
          case 'status':
            return {'status': ready ? 'ready' : 'none', 'build': 200};
          case 'install':
            return 'permission';
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateCheckProvider.overrideWith(_AvailableUpdate.new)],
          child: const MaterialApp(home: Scaffold(body: LokalUpdateSheet())),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'download'), isEmpty);
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      final download = calls.singleWhere((c) => c.method == 'download');
      expect(download.arguments['build'], 200);
      expect(calls.where((c) => c.method == 'install'), isEmpty);
      expect(find.text('Install update'), findsOneWidget);
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow updates from Lokal'), findsOneWidget);
      expect(find.text('Install update'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
