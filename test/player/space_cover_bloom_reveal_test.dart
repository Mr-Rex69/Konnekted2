import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/space_cover_bloom_reveal.dart';

void main() {
  const viewport = Size(430, 930);
  const artwork = Rect.fromLTWH(24, 175, 380, 380);

  test('Space blur rises from the bottom rather than sinking downward', () {
    final start = spaceRisingBlurFront(viewport, 0);
    final quarter = spaceRisingBlurFront(viewport, .25);
    final half = spaceRisingBlurFront(viewport, .5);
    final threeQuarters = spaceRisingBlurFront(viewport, .75);
    final end = spaceRisingBlurFront(viewport, 1);

    expect(start, greaterThan(viewport.height));
    expect(start, greaterThan(quarter));
    expect(quarter, greaterThan(half));
    expect(half, greaterThan(threeQuarters));
    expect(threeQuarters, greaterThan(end));
    expect(end, lessThan(0));
  });

  test('rounded cutout matches the exact 20px normal-cover corners', () {
    final cover = spaceCoverRevealAnchor(viewport, coverRect: artwork);
    expect(cover, artwork);
    final path = spaceRisingFrostClip(
      viewport, cover, 1, cornerRadius: 20,
    );
    // A pixel inside the square corners but *outside* a radius-20 cover
    // must get blurred. The old 20→7px radius exposed this as a sharp wedge.
    expect(path.contains(const Offset(28, 179)), isTrue);
    expect(path.contains(const Offset(44, 176)), isFalse);
    expect(path.contains(cover.center), isFalse);
    expect(path.contains(const Offset(10, 600)), isTrue);
  });

  test('cutout radius is unchanged throughout the expansion', () {
    final p1 = spaceRisingFrostClip(
      viewport, artwork, .85, cornerRadius: 20,
    );
    final p2 = spaceRisingFrostClip(
      viewport, artwork, 1, cornerRadius: 20,
    );
    expect(p1.contains(artwork.center), isFalse);
    expect(p2.contains(artwork.center), isFalse);
    expect(p1.contains(const Offset(28, 179)), isTrue);
    expect(p2.contains(const Offset(28, 179)), isTrue);
  });

  test('Fullcover keeps its square full-width poster edge', () {
    const sleeve = Rect.fromLTWH(0, 0, 430, 570);
    final cover = spaceCoverRevealAnchor(
      viewport, coverRect: sleeve,
    );
    expect(cover.top, 0);
    expect(cover.width, viewport.width);
    final path = spaceRisingFrostClip(
      viewport, cover, 1, cornerRadius: 0,
    );
    expect(path.contains(const Offset(1, 1)), isFalse);
    expect(path.contains(const Offset(10, 650)), isTrue);
  });

  test('Canvas preserves an edge-to-edge upper visual plane', () {
    final canvas = spaceCoverRevealAnchor(viewport, canvasMode: true);
    expect(canvas.left, 0);
    expect(canvas.top, 0);
    expect(canvas.width, viewport.width);
    expect(canvas.height, closeTo(viewport.height * .64, .001));
    final path = spaceRisingFrostClip(
      viewport, canvas, 1, cornerRadius: 0,
    );
    expect(path.contains(const Offset(215, 300)), isFalse);
    expect(path.contains(const Offset(215, 800)), isTrue);
  });

  testWidgets('blur layer and lyrics animate forward and back in place', (
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
          coverCornerRadius: 20,
          child: const Center(child: Text('Synchronized lyrics')),
        ),
      ),
    ));
    expect(find.byType(BackdropFilter), findsOneWidget);
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

  testWidgets('full-screen Canvas stays mounted through a frosted reveal', (
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
            coverCornerRadius: 0,
            child: const Center(child: Text('Canvas lyrics')),
          ),
        ),
      ),
    ));
    expect(find.text('Canvas lyrics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
