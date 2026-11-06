import 'dart:math' as math;

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        expect(glass.backdropBlurSigma, 2);
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

  testWidgets('footer uses the same real backdrop blur in both performance modes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var collapsed = false;
    var hasMini = true;
    late StateSetter update;
    await tester.pumpWidget(
      ProviderScope(
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
                    hasMiniPlayer: hasMini,
                    collapsed: collapsed,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    void expectFrost() {
      final keys = <Key>[
        if (hasMini) const ValueKey('dock-mini-glass'),
        const ValueKey('dock-tab-glass'),
        const ValueKey('dock-search-glass'),
      ];
      final glasses = tester.widgetList<LokalGlass>(
        find.byType(LokalGlass),
      ).toList();
      expect(glasses, hasLength(keys.length));
      for (final glass in glasses) {
        expect(glass.backdropBlurSigma, 2);
        expect(glass.performanceTintOpacity, closeTo(.28, .001));
        expect(glass.singlePassLens, isTrue);
      }
      for (final key in keys) {
        // Even in Performance Mode each capsule must keep an ordinary
        // clipped Gaussian backdrop filter rather than a flat fill.
        expect(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );
      }
      expect(find.byType(BackdropGroup), findsOneWidget);
    }

    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KonnektedDock)),
    );
    // Performance Mode is on by default.
    expect(container.read(lokalAppearanceProvider).performanceMode, isTrue);
    expectFrost();
    update(() => collapsed = true);
    await tester.pumpAndSettle();
    expectFrost();

    // Full mode retains the same base frost, without adding extra lenses.
    await container.read(lokalAppearanceProvider.notifier).setPerformanceMode(false);
    await tester.pumpAndSettle();
    expectFrost();
    update(() => collapsed = false);
    await tester.pumpAndSettle();
    expectFrost();

    // The footer also keeps its blur without a playing track (two capsules).
    update(() => hasMini = false);
    await tester.pumpAndSettle();
    expectFrost();
    await container.read(lokalAppearanceProvider.notifier).setPerformanceMode(true);
    await tester.pumpAndSettle();
    expectFrost();
    expect(tester.takeException(), isNull);
  });

  testWidgets('light-mode dock stays translucent with only a slight frost',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.light)),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: KonnektedDock(
                selected: KonnektedTab.listen,
                onSelect: (_) {},
                miniPlayer: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final glass = tester.widgetList<LokalGlass>(
      find.byType(LokalGlass),
    ).toList();
    expect(glass, hasLength(3));
    for (final capsule in glass) {
      expect(capsule.backdropBlurSigma, 2);
      expect(capsule.performanceTintOpacity, closeTo(.40, .001));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer keeps identical one-pass optical rendering throughout collapse',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var collapsed = false;
    late StateSetter change;

    await tester.pumpWidget(ProviderScope(
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
                  miniPlayer: const SizedBox.expand(),
                  collapsed: collapsed,
                ),
              );
            },
          ),
        ),
      ),
    ));

    void assertContinuous() {
      final glass = tester.widgetList<LokalGlass>(
        find.byType(LokalGlass),
      ).toList();
      expect(glass, hasLength(3));
      for (final capsule in glass) {
        expect(capsule.singlePassLens, isTrue);
        expect(capsule.staticSurface, isFalse);
        expect(capsule.suspendBackdrop, isFalse);
        expect(capsule.lens?.magnification, closeTo(.023, .001));
        expect(capsule.pronouncedRim, isTrue);
      }
      // Extra refractive selection layers added CPU/GPU passes and made
      // navigation feel overanimated. Only the parent glass is optical.
      expect(find.byType(LokalClearLens), findsNothing);
    }

    assertContinuous();
    change(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    assertContinuous();
    await tester.pumpAndSettle();
    assertContinuous();
    change(() => collapsed = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    assertContinuous();
    await tester.pumpAndSettle();
    assertContinuous();
    expect(tester.takeException(), isNull);
  });

  test('collapse squash compresses toward left and ends at natural size', () {
    expect(dockSelectedIconLeftSquash(-1), 1);
    expect(dockSelectedIconLeftSquash(0), 1);
    expect(dockSelectedIconLeftSquash(.16), 1);
    expect(dockSelectedIconLeftSquash(.5), closeTo(.76, .002));
    expect(dockSelectedIconLeftSquash(.82), 1);
    expect(dockSelectedIconLeftSquash(1), 1);
    expect(dockSelectedIconLeftSquash(2), 1);
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


  testWidgets('tab selection uses one cheap moving highlight, no second lens',
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

    const indicator = ValueKey('dock-selection-indicator');
    final startX = tester.getCenter(find.byKey(indicator)).dx;
    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(selected, KonnektedTab.library);
    final movingX = tester.getCenter(find.byKey(indicator)).dx;
    expect(movingX, greaterThan(startX));
    expect(find.byType(LokalClearLens), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(indicator)).dx, greaterThan(movingX));
    expect(tester.takeException(), isNull);
  });

  testWidgets('house squashes left on collapse only; expansion stays normal',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var collapsed = false;
    late StateSetter change;
    await tester.pumpWidget(ProviderScope(
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
    ));

    const glyphKey = ValueKey('dock-shared-selected-icon');
    const tabsKey = ValueKey('dock-tab-glass');
    const searchKey = ValueKey('dock-search-glass');
    Transform glyph() => tester.widget<Transform>(find.byKey(glyphKey));

    final openTabs = tester.getRect(find.byKey(tabsKey));
    final openSearch = tester.getRect(find.byKey(searchKey));
    expect(glyph().alignment, Alignment.centerLeft);
    expect(glyph().transform.storage[0], closeTo(1.08, .001));
    expect(glyph().transform.storage[5], closeTo(1.08, .001));

    change(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    final middle = glyph().transform;
    expect(middle.storage[0], lessThan(.88),
        reason: 'The house compresses horizontally toward its left anchor');
    expect(middle.storage[5], closeTo(1.08, .001),
        reason: 'The house never stretches or bounces vertically');
    expect(middle.getTranslation().x, 0);
    expect(find.byKey(const ValueKey('dock-home-press')), findsNothing);
    expect(find.bySemanticsLabel('Search'), findsOneWidget);

    await tester.pumpAndSettle();
    final compactTabs = tester.getRect(find.byKey(tabsKey));
    final compactSearch = tester.getRect(find.byKey(searchKey));
    expect(compactTabs.width, lessThan(openTabs.width));
    expect(compactSearch.width, lessThan(openSearch.width));
    expect(glyph().transform.storage[0], closeTo(1.08, .001));

    // Reopening never triggers the compression: no reverse bounce, spring,
    // directional sway or intermediate stretching of the selected icon.
    change(() => collapsed = false);
    await tester.pump();
    final leftBound = compactTabs.left;
    final rightBound = openTabs.left;
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 22));
      expect(glyph().transform.storage[0], closeTo(1.08, .001));
      expect(glyph().transform.storage[5], closeTo(1.08, .001));
      expect(glyph().transform.getTranslation().x, 0);
      final glass = tester.getRect(find.byKey(tabsKey));
      expect(glass.left,
          inInclusiveRange(math.min(leftBound, rightBound) - .01,
              math.max(leftBound, rightBound) + .01),
          reason: 'The capsule cannot overshoot the natural open position');
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(tabsKey)), openTabs);
    expect(tester.getRect(find.byKey(searchKey)), openSearch);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pressing any player control moves content, never its glass',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = <String>[];

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: KonnektedDock(
              selected: KonnektedTab.listen,
              onSelect: (_) {},
              miniPlayer: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final label in ['Play', 'Next', 'Queue'])
                    IconButton(
                      tooltip: label,
                      onPressed: () => actions.add(label),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    const glassKey = ValueKey('dock-mini-glass');
    const pressKey = ValueKey('dock-mini-press');
    final outerRect = tester.getRect(find.byKey(glassKey));
    // Press feedback is entirely below the optical surface in the tree.
    expect(
      find.descendant(of: find.byKey(glassKey), matching: find.byKey(pressKey)),
      findsOneWidget,
    );
    for (final label in ['Play', 'Next', 'Queue']) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip(label)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      final scale = tester.widget<AnimatedScale>(find.byKey(pressKey));
      expect(scale.scale, greaterThan(1));
      expect(tester.getRect(find.byKey(glassKey)), outerRect);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(glassKey)), outerRect);
    }
    expect(actions, ['Play', 'Next', 'Queue']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab content presses without scaling the glass, selected pill is flat tint',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var selected = KonnektedTab.listen;

    await tester.pumpWidget(ProviderScope(
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
    ));

    const glassKey = ValueKey('dock-tab-glass');
    const indicatorKey = ValueKey('dock-selection-indicator');
    final glassBounds = tester.getRect(find.byKey(glassKey));

    for (final tab in ['Home', 'Library', 'You']) {
      final pointer = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel(tab)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('dock-home-press')), findsNothing,
          reason: 'Tab taps must never trigger a house bounce');
      expect(tester.getRect(find.byKey(glassKey)), glassBounds);
      await pointer.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(glassKey)), glassBounds);
      final indicator = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(indicatorKey),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = indicator.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.gradient, isNull);
      expect(decoration.border, isNull);
      expect(
        find.descendant(
          of: find.byKey(indicatorKey),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(tester.widgetList<LokalGlass>(find.byType(LokalGlass)), hasLength(3));
    }
    expect(selected, KonnektedTab.settings);
    expect(tester.takeException(), isNull);
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
    expect(find.byKey(const ValueKey('dock-home-press')), findsNothing);
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



  testWidgets('selection icon glides without a spring and Search preserves it',
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
