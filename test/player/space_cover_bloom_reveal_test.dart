import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/space_cover_bloom_reveal.dart';

void main() {
  const viewport = Size(430, 930);
  const artwork = Rect.fromLTWH(24, 175, 380, 380);

  test('Space expands from the artwork perimeter to the entire viewport', () {
    final anchor = spaceCoverRevealAnchor(
      viewport,
      coverRect: artwork,
    );
    expect(anchor, artwork);
    final start = spaceCoverBloomBounds(viewport, anchor, 0);
    final middle = spaceCoverBloomBounds(viewport, anchor, .5);
    final end = spaceCoverBloomBounds(viewport, anchor, 1);

    expect(start.contains(artwork.center), isTrue);
    expect(start.width, lessThan(middle.width));
    expect(start.height, lessThan(middle.height));
    expect(middle.width, lessThan(end.width));
    expect(middle.height, lessThan(end.height));
    expect(end.left, lessThan(0));
    expect(end.top, lessThan(0));
    expect(end.right, greaterThan(viewport.width));
    expect(end.bottom, greaterThan(viewport.height));
  });

  test('Fullcover uses the real top banner instead of a centred square', () {
    const sleeve = Rect.fromLTWH(0, 0, 430, 570);
    final anchor = spaceCoverRevealAnchor(
      viewport,
      coverRect: sleeve,
    );
    expect(anchor.top, 0);
    expect(anchor.width, viewport.width);
    expect(anchor.height, sleeve.height);
  });

  test('Canvas stays visible through an inset centre', () {
    final canvas = spaceCoverRevealAnchor(viewport, canvasMode: true);
    expect(canvas.width, lessThan(viewport.width));
    expect(canvas.height, lessThan(viewport.height));
    expect(canvas.center.dx, closeTo(viewport.width / 2, .001));
  });

  testWidgets('the reveal reverses smoothly without replacing the lyrics', (
    tester,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 500),
    );
    addTearDown(animation.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpaceCoverBloomReveal(
          progress: animation,
          coverRect: artwork,
          child: const Center(child: Text('Synchronized lyrics')),
        ),
      ),
    ));
    expect(find.byType(SpaceCoverBloomPainter), findsNothing);
    expect(find.text('Synchronized lyrics'), findsOneWidget);
    animation.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 310));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 310));
    expect(animation.value, 1);
    expect(find.text('Synchronized lyrics'), findsOneWidget);

    animation.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 250));
    expect(animation.value, 0);
  });

  testWidgets('Canvas reveal accepts a full screen visual plane', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: tester,
      value: .72,
      duration: const Duration(milliseconds: 620),
    );
    addTearDown(animation.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 560,
          child: SpaceCoverBloomReveal(
            progress: animation,
            canvasMode: true,
            child: const Center(child: Text('Canvas lyrics')),
          ),
        ),
      ),
    ));
    expect(find.text('Canvas lyrics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
