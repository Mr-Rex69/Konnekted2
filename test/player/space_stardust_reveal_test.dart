import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/space_stardust_reveal.dart';

void main() {
  testWidgets('Space stardust aperture supports forward and reverse', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 500),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              SpaceStardustReveal(
                progress: controller,
                child: const Center(child: Text('Timed lyrics')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Timed lyrics'), findsOneWidget);
    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.value, 1);

    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 245));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.value, 0);
    expect(find.text('Timed lyrics'), findsOneWidget);
  });

  testWidgets('Space stardust paints within compact artwork viewport', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 620),
      value: .45,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 550,
            child: SpaceStardustReveal(
              progress: controller,
              child: const Center(child: Text('Space')),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
