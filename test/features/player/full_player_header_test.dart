import 'dart:ui' as ui;

import 'package:flick/core/theme/app_theme.dart';
import 'package:flick/features/player/widgets/full_player_header.dart';
import 'package:flick/features/player/widgets/full_player_visuals.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$platform header stays readable and tappable on bright covers at $scale text',
        (tester) async {
          const name = 'Google Pixel Tablet Living Room';
          final boundary = GlobalKey(), calls = <String>[];
          final cover = ValueNotifier<Color>(Colors.white);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.darkTheme.copyWith(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Center(
                      child: RepaintBoundary(
                        key: boundary,
                        child: SizedBox(
                          width: 320,
                          height: 58,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ValueListenableBuilder<Color>(
                                valueListenable: cover,
                                builder: (_, value, __) =>
                                    ColoredBox(color: value),
                              ),
                              FullPlayerHeader(
                                deviceLabel: name,
                                outputIcon: LucideIcons.speaker,
                                isCasting: true,
                                onClose: () => calls.add('close'),
                                onOutput: () => calls.add('output'),
                                onCast: () => calls.add('cast'),
                                onMore: () => calls.add('more'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final pill = find.ancestor(
            of: find.text(name),
            matching: find.byType(LokalGlass),
          );
          final more = find.ancestor(
            of: find.byIcon(Icons.more_vert),
            matching: find.byType(LokalGlass),
          );
          final pillRect = tester.getRect(pill),
              moreRect = tester.getRect(more);
          expect(
            pillRect.right,
            lessThan(tester.getRect(find.byIcon(LucideIcons.cast)).left),
          );
          for (final color in [Colors.white, Colors.yellow, Colors.cyan]) {
            cover.value = color;
            await tester.pump();
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              for (final rect in [pillRect, moreRect]) {
                final point = render.globalToLocal(
                  Offset(rect.left + 6, rect.center.dy),
                );
                final offset =
                    (point.dy.floor() * image.width + point.dx.floor()) * 4;
                final backing = Color.fromARGB(
                  255,
                  bytes.getUint8(offset),
                  bytes.getUint8(offset + 1),
                  bytes.getUint8(offset + 2),
                );
                final contrast =
                    (FullPlayerVisuals.primaryText.computeLuminance() + .05) /
                    (backing.computeLuminance() + .05);
                expect(
                  contrast,
                  greaterThan(4.5),
                  reason: 'header glass must maintain text/icon contrast on bright frames',
                );
              }
              image.dispose();
            });
          }
          await tester.tap(find.byIcon(LucideIcons.chevronLeft));
          await tester.tap(find.text(name));
          await tester.tap(find.byIcon(LucideIcons.cast));
          await tester.tap(find.byIcon(Icons.more_vert));
          expect(calls, ['close', 'output', 'cast', 'more']);
          expect(find.bySemanticsLabel('More options'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          cover.dispose();
          semantics.dispose();
        },
      );
    }
  }
}
