import 'dart:ui' as ui;

import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final canvas in [false, true]) {
    testWidgets(
      '${canvas ? "Canvas" : "Album banner"} paints its one artwork between thumbnail and expanded bounds in both directions',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundaryKey = GlobalKey();
        const source = Rect.fromLTWH(18, 710, 52, 52);
        final target = Rect.fromLTWH(0, 0, 400, canvas ? 800 : 480);
        for (final progress in [.15, .5, .85, 1.0, .85, .5, .15]) {
          final top = (1 - progress) * 700;
          // The closing J deliberately dips below the real mini artwork
          // and rises into its target, including tall Canvas posters.
          // This no longer clamps the cover bottom to its destination:
          // that clamp was why the user's J-shaped reference never rendered.
          final inFlight = LokalArtworkFlight.rect(
            source, target, progress, sheetTravel: 700,
          );
          if (progress == .15) {
            expect(inFlight.center.dy, greaterThan(source.center.dy + 20));
            expect(inFlight.bottom, greaterThan(source.bottom));
          }
          expect(
            inFlight.size,
            Rect.lerp(source, target, progress)!.size,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: boundaryKey,
                child: ColoredBox(
                  color: Colors.black,
                  child: LokalPlayerMorph(
                    progress: progress,
                    sheetOffset: top,
                    sourceArtwork: () => source,
                    child: Transform.translate(
                      offset: Offset(0, top),
                      child: FullBleedArtworkFrame(
                        canvas: canvas,
                        bannerBottom: 480,
                        child: const ColoredBox(
                          key: ValueKey('single-art'),
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byKey(const ValueKey('single-art')), findsOneWidget);
          await tester.runAsync(() async {
            final image =
                await (boundaryKey.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final center = LokalArtworkFlight.rect(
              source, target, progress, sheetTravel: 700,
            ).center;
            final offset =
                (center.dy.round() * image.width + center.dx.round()) * 4;
            // The source image remains painted at the interpolated screen rect,
            // including the first opening frames and last closing frames.
            expect(
              bytes!.getUint8(offset + 2),
              greaterThan(bytes.getUint8(offset) + 15),
              reason: 'progress=$progress',
            );
            if (progress < 1) {
              final outside =
                  ((top + 30).round().clamp(0, 799) * image.width + 399) * 4;
              expect(
                bytes.getUint8(outside + 2) - bytes.getUint8(outside),
                lessThan(10),
                reason:
                    'No un-morphed poster should remain outside the traveling artwork at $progress',
              );
            }
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
