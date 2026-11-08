import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/features/onboarding/screens/onboarding_screen.dart';

Future<void> _pumpOnboarding(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: OnboardingScreen())),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  tearDown(() => AppConstants.setAnimationsEnabled(true));

  testWidgets(
    'folder picker failure and cancellation leave onboarding retryable without media permission',
    (tester) async {
      const storage = MethodChannel('com.mossapps.flick/storage');
      const permissions = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      var pickerCalls = 0;
      var permissionCalls = 0;
      final channels = tester.binding.defaultBinaryMessenger;
      channels.setMockMethodCallHandler(permissions, (call) async {
        permissionCalls++;
        throw PlatformException(code: 'unexpected_permission');
      });
      channels.setMockMethodCallHandler(storage, (call) async {
        expect(call.method, 'openDocumentTree');
        pickerCalls++;
        if (pickerCalls == 1) {
          throw PlatformException(code: 'PICKER_UNAVAILABLE');
        }
        return null; // User cancels the second picker.
      });
      addTearDown(() {
        channels.setMockMethodCallHandler(storage, null);
        channels.setMockMethodCallHandler(permissions, null);
      });
      await _pumpOnboarding(tester);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Select Your Music Folder'), findsOneWidget);
      await tester.tap(find.text('Choose Folder'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Folder'), findsOneWidget);
      expect(find.textContaining('Couldn’t add the folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Choose Folder'));
      await tester.pumpAndSettle();
      expect(pickerCalls, 2);
      expect(permissionCalls, 0);
      expect(find.text('Choose Folder'), findsOneWidget);
      expect(find.text('Opening…'), findsNothing);
      expect(find.text('Select Your Music Folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('Next advances to the following page', (tester) async {
    AppConstants.setAnimationsEnabled(true);
    await _pumpOnboarding(tester);

    expect(find.text('Welcome to Lokal'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Pick your look'), findsOneWidget);
  });

  testWidgets('Next advances when animations are disabled', (tester) async {
    AppConstants.setAnimationsEnabled(false);
    await _pumpOnboarding(tester);

    expect(find.text('Welcome to Lokal'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pump();

    expect(find.text('Pick your look'), findsOneWidget);
  });
}
