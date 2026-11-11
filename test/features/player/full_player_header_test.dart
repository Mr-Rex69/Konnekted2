import 'dart:math' as math;
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
                                builder: (_, value, __) => Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(color: value),
                                    FullPlayerHeader(
                                      deviceLabel: name,
                                      outputIcon: LucideIcons.speaker,
                                      isCasting: true,
                                      brightArtwork:
                                          value.computeLuminance() >= .42,
                                      onClose: () => calls.add('close'),
                                      onOutput: () => calls.add('output'),
                                      onCast: () => calls.add('cast'),
                                      onMore: () => calls.add('more'),
                                    ),
                                  ],
                                ),
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
            matching: find.byType(BackdropFilter),
          );
          final more = find.ancestor(
            of: find.byIcon(Icons.more_vert),
            matching: find.byType(BackdropFilter),
          );
          final pillRect = tester.getRect(pill),
              moreRect = tester.getRect(more);
          expect(
            pillRect.center.dx,
            closeTo(tester.getRect(find.byType(FullPlayerHeader)).center.dx, 1),
            reason: 'the device pill must center on the player, not in an unbalanced Row',
          );
          expect(
            pillRect.right,
            lessThan(tester.getRect(find.byIcon(LucideIcons.cast)).left),
          );
          // Dark artwork stays light-on-dark; bright artwork becomes dark
          // ink over transparent frost rather than opaque black buttons.
          expect(find.byType(LokalGlass), findsNothing);
          expect(find.byType(LokalLensBackdrop), findsNothing);
          expect(find.byType(BackdropFilter), findsNWidgets(4));
          for (final color in [
            Colors.white,
            Colors.yellow,
            Colors.cyan,
            Colors.black,
            const Color(0xFF122A47),
          ]) {
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
                final ink = tester.widget<Icon>(
                  find.byIcon(LucideIcons.cast),
                ).color!;
                final top = math.max(
                  ink.computeLuminance(),
                  backing.computeLuminance(),
                );
                final bottom = math.min(
                  ink.computeLuminance(),
                  backing.computeLuminance(),
                );
                final contrast = (top + .05) / (bottom + .05);
                if (color == Colors.white) {
                  expect(
                    backing.computeLuminance(),
                    greaterThan(.70),
                    reason: 'frost must show bright artwork, not a black scrim',
                  );
                }
                expect(
                  contrast,
                  greaterThan(4.5),
                  reason: 'the frosted header must retain icon/text contrast',
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
