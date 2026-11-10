import 'dart:io';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/settings/widgets/automatic_backup_settings_tile.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('backup layout on $platform at 320px and ${scale}x text', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final directory = Directory.systemTemp.createTempSync(
          'backup-layout-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
        );
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!)
                .copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: LokalSettingsSection(
                  title: 'Backup',
                  children: [AutomaticBackupSettingsTile()],
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(find.text('Automatic backup'), findsOneWidget);
        expect(find.text('Back up now'), findsOneWidget);
        expect(find.text('Never'), findsOneWidget);
        final actions = find.byType(LokalSettingsActionButton);
        expect(actions, findsNWidgets(3));
        for (var index = 0; index < 3; index++) {
          final size = tester.getSize(actions.at(index));
          expect(size.width, greaterThan(240));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await tester.ensureVisible(actions.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
