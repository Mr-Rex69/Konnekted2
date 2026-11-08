import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/features/updates/ios_store_update_actions.dart';
import 'package:flick/features/updates/lokal_update_sheet.dart';
import 'package:flick/providers/update_check_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _IosUpdate extends UpdateCheckNotifier {
  @override
  UpdateCheckState build() => const UpdateCheckState(
    flavor: 'ios',
    release: LokalUpdateRelease(
      version: '1.0.0',
      build: 163,
      downloadUrl: 'https://github.com/lokal-music/mobile/releases/download/ios/Lokal.ipa',
      sha256: 'hash',
      pageUrl: 'https://github.com/lokal-music/mobile/releases/tag/ios',
      notes: '',
      isIos: true,
    ),
  );
}

void main() {
  testWidgets(
    'iOS prompts open the selected store only after a tap and never invoke the APK installer',
    (tester) async {
      const channel = MethodChannel('lokal/app_update');
      final native = <MethodCall>[];
      final opened = <Uri>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        native.add(call);
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
          overrides: [
            updateCheckProvider.overrideWith(_IosUpdate.new),
            iosStoreUrlLauncherProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: LokalUpdateSheet()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('Download update'), findsNothing);
      await tester.tap(find.text('Open SideStore'));
      await tester.pumpAndSettle();
      expect(opened.single.scheme, 'sidestore');
      await tester.tap(find.text('Open AltStore'));
      await tester.pumpAndSettle();
      expect(opened.last.scheme, 'altstore-classic');
      await tester.tap(find.text('Set up store updates'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add to SideStore'));
      await tester.tap(find.text('Add to SideStore'));
      await tester.pumpAndSettle();
      expect(opened.last.host, 'source');
      expect(opened.last.queryParameters['url'], lokalIosSourceUrl);
      expect(native, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'missing stores show setup guidance and AltStore falls back to its older scheme',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateCheckProvider.overrideWith(_IosUpdate.new),
            iosStoreUrlLauncherProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return false;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: LokalUpdateSheet())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open AltStore'));
      await tester.pumpAndSettle();
      expect(opened.map((uri) => uri.scheme), ['altstore-classic', 'altstore']);
      expect(find.textContaining('could not be opened'), findsOneWidget);
      expect(find.text('Setup guide'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
