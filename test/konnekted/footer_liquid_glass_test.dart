import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all three dock surfaces retain the same live glass optics',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget dock({required bool collapsed}) => ProviderScope(
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: KonnektedDock(
                    selected: KonnektedTab.listen,
                    onSelect: (_) {},
                    miniPlayer: const SizedBox.expand(),
                    hasMiniPlayer: true,
                    collapsed: collapsed,
                  ),
                ),
              ),
            ),
          ),
        );

    void checkGlass(double expectedOpacity, double fallbackOpacity) {
      final glasses = tester.widgetList<LokalGlass>(
        find.byType(LokalGlass),
      ).toList();
      // Mini player, navigation capsule and separate Search button.
      expect(glasses, hasLength(3));
      for (final glass in glasses) {
        expect(glass.pronouncedRim, isFalse);
        expect(glass.lens?.profile, LokalLensProfile.squircle);
        expect(glass.liquidBlurRadius, .8);
        expect(glass.fallbackBlurSigma, 2);
        expect(glass.fallbackTintOpacity, closeTo(fallbackOpacity, .001));
        expect(glass.lens?.magnification, closeTo(.065, .001));
        expect(glass.liquidTintOpacity, closeTo(expectedOpacity, .001));
      }
    }

    await tester.pumpWidget(dock(collapsed: false));
    await tester.pump();
    checkGlass(.09, .16);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(dock(collapsed: true));
    await tester.pump();
    checkGlass(.13, .20);
    expect(tester.takeException(), isNull);
  });

  test('Home bubble flexes and settles only during the last stage of collapse', () {
    expect(dockHomeBubbleScale(0), 1);
    expect(dockHomeBubbleScale(.64), 1);
    expect(dockHomeBubbleScale(1), 1);
    expect(dockHomeBubbleScale(.72), greaterThan(1));
    expect(dockHomeBubbleScale(.92), lessThan(1));
    expect(dockHomeBubbleScale(.82), inInclusiveRange(.94, 1.06));
  });

  testWidgets('mini-player controls fade continuously into inline layout',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const song = Song(
      id: 'glass-transition',
      title: 'Transition test song',
      artist: 'Transition artist',
      duration: Duration(minutes: 3),
      fileType: 'FLAC',
    );

    Widget atProgress(double progress) => ProviderScope(
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 340,
                  height: 58,
                  child: KonnektedMiniPlayerScope(
                    collapsed: progress >= 1,
                    progress: progress,
                    child: KonnektedMiniPlayerContent(
                      song: song,
                      isPlaying: true,
                      onOpen: () {},
                      onPlayPause: () {},
                      onPrevious: () {},
                      onNext: () {},
                      onQueue: () {},
                      progress: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(atProgress(0));
    await tester.pump();
    expect(find.byTooltip('Open queue'), findsOneWidget);
    expect(find.text('Transition artist'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(atProgress(.45));
    await tester.pump();
    expect(find.byTooltip('Open queue'), findsOneWidget);
    expect(find.text('Transition artist'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    final middleScope = tester.widget<KonnektedMiniPlayerScope>(
      find.byType(KonnektedMiniPlayerScope),
    );
    expect(middleScope.progress, closeTo(.45, .001));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(atProgress(1));
    await tester.pump();
    expect(find.byTooltip('Open queue'), findsNothing);
    expect(find.text('Transition artist'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('dock accessory collapse is reversible before settling',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var collapsed = false;
    late StateSetter change;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                change = setState;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: KonnektedDock(
                    selected: KonnektedTab.listen,
                    onSelect: (_) {},
                    collapsed: collapsed,
                    miniPlayer: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    change(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    final progress = tester.widget<KonnektedMiniPlayerScope>(
      find.byType(KonnektedMiniPlayerScope),
    ).progress!;
    expect(progress, greaterThan(0));
    expect(progress, lessThan(1));

    // Reverse the same spring mid-flight instead of swapping the layout.
    change(() => collapsed = false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester.widget<KonnektedMiniPlayerScope>(
        find.byType(KonnektedMiniPlayerScope),
      ).progress,
      closeTo(0, .001),
    );
    expect(tester.takeException(), isNull);
  });

}
