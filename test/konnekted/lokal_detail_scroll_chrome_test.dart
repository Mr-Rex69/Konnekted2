import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_detail_scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('top blur starts after 55% of hero scroll, reaches full at 85%', () {
    expect(detailTopFrostOpacity(0, 400), 0);
    expect(detailTopFrostOpacity(219, 400), 0);
    expect(detailTopFrostOpacity(280, 400), closeTo(.5, .0001));
    expect(detailTopFrostOpacity(340, 400), 1);
    expect(detailTopFrostOpacity(500, 400), 1);
    expect(detailTopFrostOpacity(200, 0), 0);
  });

  testWidgets('top frost is layered over scrolling UI, not the artwork',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: const [
                  SizedBox(height: 400, child: ColoredBox(color: Colors.blue)),
                  SizedBox(height: 1500, child: ColoredBox(color: Colors.white)),
                ],
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: LokalDetailProgressiveTopBlur(
                  scrollController: controller,
                  heroHeight: 400,
                  background: Colors.black,
                ),
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: LokalDetailFloatingControls(
                  title: 'Artist',
                  scrollController: controller,
                  heroHeight: 400,
                  onlineEnabled: false,
                  onBack: () {},
                  onOnline: () {},
                  onMore: () {},
                ),
              ),
            ],
          ),
        ),
      )),
    );
    await tester.pump();
    final frost = find.byType(LokalDetailProgressiveTopBlur);
    final frostFilters = find.descendant(
      of: frost,
      matching: find.byType(BackdropFilter),
    );
    expect(frostFilters, findsNothing);
    expect(find.byType(LokalDetailFloatingControls), findsOneWidget);
    controller.jumpTo(340);
    await tester.pump();
    expect(frostFilters, findsOneWidget);
    expect(find.byType(LokalDetailFloatingControls), findsOneWidget);
    final mask = tester.widget<ShaderMask>(
      find.descendant(
        of: find.byType(LokalDetailProgressiveTopBlur),
        matching: find.byType(ShaderMask),
      ),
    );
    expect(mask.blendMode, BlendMode.dstIn);
    expect(tester.takeException(), isNull);
  });

  testWidgets('performance mode has no dynamic backdrop filter',
      (tester) async {
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        home: Scaffold(
          body: LokalDetailProgressiveTopBlur(
            scrollController: controller,
            heroHeight: 400,
            background: Colors.black,
            dynamicBlur: false,
          ),
        ),
      )),
    );
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}
