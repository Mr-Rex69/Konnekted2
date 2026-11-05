import 'package:flick/features/konnekted/library/lokal_detail_fixed_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full-resolution hero is sharp with no image-local blur strip',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 440,
            width: 390,
            child: LokalDetailFixedBackdrop(
              artwork: ColoredBox(
                key: ValueKey('fixed-artwork'),
                color: Colors.cyan,
              ),
              background: Colors.white,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('fixed-artwork'))),
        const Size(390, 440));
    final inside = find.descendant(
      of: find.byType(LokalDetailFixedBackdrop),
      matching: find.byType(ShaderMask),
    );
    expect(inside, findsNothing);
    expect(find.descendant(
      of: find.byType(LokalDetailFixedBackdrop),
      matching: find.byType(BackdropFilter),
    ), findsNothing);
    expect(find.descendant(
      of: find.byType(LokalDetailFixedBackdrop),
      matching: find.byType(ImageFiltered),
    ), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero-to-page wash is UI chrome, never an image filter',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 440,
            child: LokalDetailHeroWash(background: Colors.black),
          ),
        ),
      ),
    );
    final wash = find.byType(LokalDetailHeroWash);
    expect(wash, findsOneWidget);
    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: wash, matching: find.byType(DecoratedBox)),
    ).decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient;
    expect(gradient.stops, LokalDetailHeroWash.stops);
    expect(gradient.colors.first.alpha, 0);
    expect(gradient.colors.last, Colors.black);
    expect(find.descendant(of: wash, matching: find.byType(BackdropFilter)),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
