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
        expect(glass.pronouncedRim, isTrue);
        expect(glass.rimStrength, closeTo(.82, .001));
        expect(glass.lens?.profile, LokalLensProfile.circular);
        expect(glass.lens?.height, 13);
        expect(glass.lens?.amount, 8);
        expect(glass.lens?.depth, .18);
        expect(glass.lens?.dispersion, .10);
        expect(glass.liquidBlurRadius, 1.2);
        expect(glass.fallbackBlurSigma, 2);
        expect(glass.fallbackTintOpacity, closeTo(fallbackOpacity, .001));
        expect(glass.lens?.magnification, closeTo(.023, .001));
        expect(glass.liquidTintOpacity, closeTo(expectedOpacity, .001));
      }
    }

    void expectGlassHeights(double height) {
      for (final key in [
        const ValueKey('dock-mini-glass'),
        const ValueKey('dock-tab-glass'),
        const ValueKey('dock-search-glass'),
      ]) {
        expect(tester.getSize(find.byKey(key)).height, closeTo(height, .1));
      }
    }

    await tester.pumpWidget(dock(collapsed: false));
    await tester.pump();
    checkGlass(.09, .16);
    expectGlassHeights(58);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(dock(collapsed: true));
    await tester.pump();
    checkGlass(.13, .20);
    expectGlassHeights(KonnektedDock.collapsedHeight);

    // Expanded-to-inline material isn't a cosmetic change: the row is
    // 10dp shorter and all three glass surfaces fit one compact line.
    final compactMini = tester.getRect(
      find.byKey(const ValueKey('dock-mini-glass')),
    );
    final compactTabs = tester.getRect(
      find.byKey(const ValueKey('dock-tab-glass')),
    );
    final compactSearch = tester.getRect(
      find.byKey(const ValueKey('dock-search-glass')),
    );
    expect(compactMini.height, 48);
    expect(compactTabs.height, 48);
    expect(compactSearch.height, 48);
    expect(compactTabs.left, lessThan(compactMini.left));
    expect(compactMini.right, lessThan(compactSearch.left));
    expect(compactMini.left - compactTabs.right, closeTo(14, .1));
    expect(compactSearch.left - compactMini.right, closeTo(14, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling and folding suspend only transient backdrop work',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var collapsed = false;
    var scrolling = false;
    late StateSetter update;

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.bottomCenter,
                child: KonnektedDock(
                  selected: KonnektedTab.listen,
                  onSelect: (_) {},
                  miniPlayer: const SizedBox.expand(),
                  collapsed: collapsed,
                  scrollActive: scrolling,
                ),
              );
            },
          ),
        ),
      ),
    ));

    void allSurfaces(bool suspended) {
      final glass = tester.widgetList<LokalGlass>(
        find.byType(LokalGlass),
      ).toList();
      expect(glass, hasLength(3));
      for (final capsule in glass) {
        expect(capsule.suspendBackdrop, suspended);
        expect(capsule.lens?.magnification, closeTo(.023, .001));
        expect(capsule.pronouncedRim, isTrue);
      }
    }

    allSurfaces(false);
    update(() => scrolling = true);
    await tester.pump();
    allSurfaces(true);
    update(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    allSurfaces(true);
    update(() => scrolling = false);
    await tester.pump();
    allSurfaces(true);
    await tester.pumpAndSettle();
    allSurfaces(false);
    expect(tester.takeException(), isNull);
  });

  test('Home capsule flex follows spring progress with no independent timer', () {
    expect(dockHomeBubbleScale(0), 1);
    expect(dockHomeBubbleScale(1), 1);
    // Lift is visible for multiple frames even at a high refresh rate.
    expect(dockHomeBubbleScale(.125), greaterThan(1.003));
    expect(dockHomeBubbleScale(.375), greaterThan(1.02));
    expect(dockHomeBubbleScale(.625), greaterThan(1.02));
    expect(dockHomeBubbleScale(.875), greaterThan(1));
    expect(dockHomeBubbleScale(.5), lessThan(1.04));
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
    // The hidden queue button remains mounted for a flicker-free reverse,
    // but does not expose semantics or receive pointer events.
    expect(find.bySemanticsLabel('Open queue'), findsNothing);
    expect(find.text('Transition artist'), findsOneWidget,
        reason: 'BitChord keeps the artist even in its inline accessory');
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


  testWidgets('changing tabs lifts a refractive lens above the tab row',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var selected = KonnektedTab.listen;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Align(
                alignment: Alignment.bottomCenter,
                child: KonnektedDock(
                  selected: selected,
                  onSelect: (tab) => update(() => selected = tab),
                  miniPlayer: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(selected, KonnektedTab.library);
    final lifted = tester.widget<LokalClearLens>(
      find.byKey(const ValueKey('dock-travel-lens')),
    );
    expect(lifted.lens.amount, greaterThan(4));
    expect(lifted.lens.dispersion, .12);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    final settled = tester.widget<LokalClearLens>(
      find.byKey(const ValueKey('dock-travel-lens')),
    );
    expect(settled.lens.amount, closeTo(0, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home bounce actually fires when dock collapses; Search does not',
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

    // Capsule deforms *during* the same collapse spring, never afterwards.
    change(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));

    final bubble = tester.widget<Transform>(
      find.byKey(const ValueKey('dock-home-bounce')),
    );
    expect(
      (bubble.transform.getMaxScaleOnAxis() - 1).abs(),
      greaterThan(.01),
    );
    // Search receives no Transform.scale in the dock's layout.
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    final settled = tester.widget<Transform>(
      find.byKey(const ValueKey('dock-home-bounce')),
    );
    expect(settled.transform.getMaxScaleOnAxis(), closeTo(1, .005));
  });


  testWidgets('selected house icon keeps a steady size during dock collapse',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget build(bool collapsed) => ProviderScope(
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: KonnektedDock(
              selected: KonnektedTab.listen,
              onSelect: (_) {},
              miniPlayer: const SizedBox.expand(),
              collapsed: collapsed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(false));
    await tester.pump();
    final expandedIcon = tester.widget<Transform>(
      find.byKey(const ValueKey('dock-shared-selected-icon')),
    );
    expect(expandedIcon.transform.getMaxScaleOnAxis(), closeTo(1.08, .001));
    expect(find.byKey(const ValueKey('dock-mini-press')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-home-press')), findsOneWidget);
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    final compactIcon = tester.widget<Transform>(
      find.byKey(const ValueKey('dock-shared-selected-icon')),
    );
    expect(compactIcon.transform.getMaxScaleOnAxis(), closeTo(1.08, .001));
    // No second transition/crossfade re-renders the house at the same time
    // as the capsule's physical fold.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dock-shared-selected-icon')),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('dock-shared-selected-icon')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });



  testWidgets('selection icon follows a physical spring and Search preserves it',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var selected = KonnektedTab.listen;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Align(
                alignment: Alignment.bottomCenter,
                child: KonnektedDock(
                  selected: selected,
                  onSelect: (tab) => update(() => selected = tab),
                  miniPlayer: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    const iconKey = ValueKey('dock-shared-selected-icon');
    final start = tester.getCenter(find.byKey(iconKey));
    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 85));
    final moving = tester.getCenter(find.byKey(iconKey));
    await tester.pumpAndSettle();
    final finished = tester.getCenter(find.byKey(iconKey));
    expect(moving.dx, greaterThan(start.dx));
    expect(moving.dx, lessThan(finished.dx));
    expect(finished.dx - start.dx, greaterThan(40));

    // Search is a separate bubble. It does not reset the current Home
    // capsule to a different icon as the mini-player docks inline.
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    expect(selected, KonnektedTab.explore);
    final shownIcons = tester.widgetList<Icon>(
      find.descendant(of: find.byKey(iconKey), matching: find.byType(Icon)),
    ).toList();
    expect(shownIcons.single.icon, Icons.library_music_rounded);
    expect(tester.takeException(), isNull);
  });

}
