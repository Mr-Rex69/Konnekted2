import 'package:flick/widgets/common/web_sign_in_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'iOS login footer stays above the keyboard and content can scroll',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: WebSignInFrame(
            fullscreen: true,
            child: Column(
              children: [
                const SizedBox(height: 80, child: Text('Sign in')),
                Expanded(
                  child: ListView(
                    children: [
                      const SizedBox(height: 400),
                      const TextField(key: Key('password')),
                      const SizedBox(height: 250),
                      TextButton(
                        key: const Key('submit'),
                        onPressed: () => submitted = true,
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 64,
                  key: Key('account-confirm'),
                  child: Text('Use this account'),
                ),
              ],
            ),
          ),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      expect(
        tester.getBottomLeft(find.byKey(const Key('account-confirm'))).dy,
        lessThanOrEqualTo(524),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit')));
      expect(submitted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact keyboard layout does not overflow the page frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: WebSignInFrame(
          fullscreen: true,
          child: Column(
            children: [
              SizedBox(height: 80),
              Expanded(child: Placeholder()),
              SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Placeholder)).height, 223);
  });
}
