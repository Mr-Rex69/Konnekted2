import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/navigation/lokal_page_motion.dart';

class _AccessibilityFeatures implements ui.AccessibilityFeatures {
  _AccessibilityFeatures({
    this.disableAnimations = false,
    this.reduceMotion = false,
  });

  @override
  final bool disableAnimations;
  @override
  final bool reduceMotion;
  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}

void main() {
  setUp(() => AppConstants.setAnimationsEnabled(true));
  tearDown(() => AppConstants.setAnimationsEnabled(true));

  testWidgets('push and pop animate both foreground and previous page',
      (tester) async {
    final primary = AnimationController(
      vsync: tester,
      duration: LokalPageMotion.duration,
      reverseDuration: LokalPageMotion.reverseDuration,
      value: 0,
    );
    final secondary = AnimationController(vsync: tester, value: 0);
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => const LokalPageMotion().buildTransitions<void>(
          MaterialPageRoute<void>(builder: (_) => const SizedBox()),
          context,
          primary,
          secondary,
          const SizedBox(key: Key('detail')),
        ),
      ),
    ));

    double foreground() => tester
        .widget<FractionalTranslation>(find.byType(FractionalTranslation).last)
        .translation.dx;
    List<double> background() => tester
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .map((transition) => transition.position.value.dx)
        .toList();

    expect(foreground(), closeTo(LokalPageMotion.enterOffset, .001));

    primary.value = .5;
    secondary.value = .5;
    await tester.pump();
    expect(foreground(), greaterThan(.01),
        reason: 'incoming route should move in from the right');
    expect(background().any((value) => value < -.01), isTrue,
        reason: 'previous route should recede toward the left');

    primary.value = 1;
    secondary.value = 1;
    await tester.pump();
    expect(background(), contains(closeTo(LokalPageMotion.behindOffset, .001)));

    primary.reverse(from: 1);
    primary.value = .01;
    secondary.value = .01;
    await tester.pump();
    expect(foreground(), greaterThan(.9),
        reason: 'Back must carry the page to the far right, not 34% across');
  });

  testWidgets('interrupting push with Back preserves position', (tester) async {
    final primary = AnimationController(
      vsync: tester,
      value: 0,
      duration: LokalPageMotion.duration,
      reverseDuration: LokalPageMotion.reverseDuration,
    );
    final secondary = AnimationController(vsync: tester, value: 0);
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => const LokalPageMotion().buildTransitions<void>(
          MaterialPageRoute<void>(builder: (_) => const SizedBox()),
          context, primary, secondary,
          const SizedBox(key: Key('detail-midflight')),
        ),
      ),
    ));
    primary.forward(from: 0);
    primary.value = .45;
    await tester.pump();
    final before = tester.widget<FractionalTranslation>(
      find.byType(FractionalTranslation).last,
    ).translation.dx;
    primary.reverse(from: .45);
    await tester.pump();
    final after = tester.widget<FractionalTranslation>(
      find.byType(FractionalTranslation).last,
    ).translation.dx;
    expect((after - before).abs(), lessThan(.001),
      reason: 'Back cannot jump from short push to full-width exit');
    primary.value = 0;
    await tester.pump();
    final end = tester.widget<FractionalTranslation>(
      find.byType(FractionalTranslation).last,
    ).translation.dx;
    expect(end, closeTo(1.0, .001));
  });

  test('library routes retain Material system-Back and Hero support', () {
    final route = LokalPageRoute<void>(builder: (_) => const SizedBox());
    expect(route, isA<MaterialPageRoute<void>>());
    expect(route.transitionDuration, LokalPageMotion.duration);
    expect(route.reverseTransitionDuration, LokalPageMotion.reverseDuration);
  });

  testWidgets('transitions never add transparent full-screen layers',
      (tester) async {
    final primary = AnimationController(vsync: tester, value: .4);
    final secondary = AnimationController(vsync: tester, value: .4);
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => const LokalPageMotion().buildTransitions<void>(
          MaterialPageRoute<void>(builder: (_) => const SizedBox()),
          context,
          primary,
          secondary,
          const ColoredBox(
            key: Key('opaque-scene'),
            color: Color(0xFF995511),
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('opaque-scene')), findsOneWidget);
    final innerMotion = find.byType(FractionalTranslation).last;
    expect(
      find.descendant(of: innerMotion, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: innerMotion, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(find.byType(RepaintBoundary), findsWidgets);

    // Both pages cover the viewport without a translucent gap. On Back the
    // foreground slides fully off the edge while the previous page is still
    // visible underneath throughout the exit.
    for (var tick = 0; tick <= 100; tick++) {
      final progress = tick / 100;
      final previousRight = 1 +
          LokalPageMotion.behindOffset * progress;
      final incomingLeft = LokalPageMotion.enterOffset * (1 - progress);
      expect(incomingLeft, lessThanOrEqualTo(previousRight),
          reason: 'No uncovered strip at push/pop progress $progress');
      final backLeft = LokalPageMotion.exitOffset * progress;
      final underneathRight = 1 +
          LokalPageMotion.behindOffset * (1 - progress);
      expect(backLeft, lessThanOrEqualTo(underneathRight),
          reason: 'No black gap during full-width Back at $progress');
    }
  });

  testWidgets('respects system reduced motion', (tester) async {
    final primary = AnimationController(vsync: tester, value: .4);
    final secondary = AnimationController(vsync: tester, value: .6);
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          key: const Key('motion-wrapper'),
          builder: (context) => const LokalPageMotion().buildTransitions<void>(
            MaterialPageRoute<void>(builder: (_) => const SizedBox()),
            context,
            primary,
            secondary,
            const Text('Static detail'),
          ),
        ),
      ),
    ));
    expect(find.text('Static detail'), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(const Key('motion-wrapper')),
      matching: find.byType(SlideTransition),
    ), findsNothing);
  });

  testWidgets('system motion gate honors both platform flags', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
    dispatcher.accessibilityFeaturesTestValue = _AccessibilityFeatures();
    expect(systemRequestsReducedMotion(context), isFalse);
    dispatcher.accessibilityFeaturesTestValue = _AccessibilityFeatures(
      reduceMotion: true,
    );
    expect(systemRequestsReducedMotion(context), isTrue);
    dispatcher.accessibilityFeaturesTestValue = _AccessibilityFeatures(
      disableAnimations: true,
    );
    expect(systemRequestsReducedMotion(context), isTrue);
  });
}
