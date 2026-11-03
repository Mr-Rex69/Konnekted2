import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
import 'package:flick/features/player/widgets/motion_art_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final canvas in [false, true]) {
    testWidgets(
      '${canvas ? "Canvas" : "Cover"} uses the intended artwork bounds',
      (tester) async {
        tester.view.physicalSize = const Size(430, 930);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: FullBleedArtworkFrame(
              canvas: canvas,
              bannerBottom: 510,
              child: const ColoredBox(key: ValueKey('art'), color: Colors.teal),
            ),
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('art'))),
          Size(430, canvas ? 930 : 510),
        );
        expect(find.byType(ShaderMask), canvas ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('still art stays flush at top and reaches the artist row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: FullBleedArtworkFrame(
          canvas: false,
          bannerBottom: 650,
          child: ColoredBox(
            key: ValueKey('lowered-art'),
            color: Colors.red,
          ),
        ),
      ),
    );
    final art = find.byKey(const ValueKey('lowered-art'));
    expect(tester.getTopLeft(art).dy, 0);
    expect(tester.getSize(art), const Size(430, 650));
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini-player Hero bounds keep the whole thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 52,
            child: FullBleedArtworkFrame(
              canvas: false,
              bannerBottom: 510,
              child: ColoredBox(color: Colors.teal),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('still fallback uses the album banner presentation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? isCanvas;
    await tester.pumpWidget(
      MaterialApp(
        home: MotionArtView(
          title: 'Song',
          artist: 'Artist',
          enabled: false,
          presentationBuilder: (context, art, canvas) {
            isCanvas = canvas;
            return FullBleedArtworkFrame(
              canvas: canvas,
              bannerBottom: 350,
              child: art,
            );
          },
          fallback: const ColoredBox(
            key: ValueKey('still'),
            color: Colors.teal,
          ),
        ),
      ),
    );
    expect(isCanvas, false);
    expect(tester.getSize(find.byKey(const ValueKey('still'))).height, 350);
    expect(tester.takeException(), isNull);
  });
  testWidgets('poster mask fades within banner, not inner image viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: FullBleedArtworkFrame(
        canvas: false,
        bannerBottom: 510,
        child: ColoredBox(color: Colors.purple),
      ),
    ));

    final mask = find.byType(ShaderMask);
    expect(mask, findsOneWidget);
    expect(tester.getSize(mask), const Size(430, 510));
    // On the old build the ShaderMask was *inside* the OverflowBox,
    // allowing the clipped banner to retain a hard partially opaque edge.
    expect(find.ancestor(
      of: find.byType(OverflowBox),
      matching: find.byType(ShaderMask),
    ), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
