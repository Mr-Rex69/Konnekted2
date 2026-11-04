import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/theme/lokal_performance_scope.dart';
import 'package:flick/features/appearance/lokal_performance_selector.dart';
import 'package:flick/features/player/widgets/motion_art_widget.dart';
import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/widgets/common/animated_album_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ArtService extends Fake implements AnimatedArtworkService {
  var calls = 0;
  @override
  Future<MotionArtLookup> lookupAnimatedArtwork({
    required String songTitle,
    required String artist,
    String? albumName,
    Duration? duration,
    String? storefront,
  }) async {
    calls++;
    return const MotionArtLookup();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('legacy Full/Performance migrate unchanged and Ultra survives theme changes/restart', () async {
    expect(
      LokalAppearance.fromJson({'performanceMode': false}).performanceLevel,
      LokalPerformanceLevel.full,
    );
    expect(
      LokalAppearance.fromJson({'performanceMode': true}).performanceLevel,
      LokalPerformanceLevel.performance,
    );
    final first = ProviderContainer();
    first.read(lokalAppearanceProvider);
    await pumpEventQueue();
    await first
        .read(lokalAppearanceProvider.notifier)
        .setPerformanceLevel(LokalPerformanceLevel.ultra);
    await first
        .read(lokalAppearanceProvider.notifier)
        .selectTheme(LokalThemeId.forest);
    final ultra = first.read(lokalAppearanceProvider);
    expect(ultra.performanceMode, true);
    expect(LokalAppearance.fromJson(ultra.toJson()), ultra);
    first.dispose();
    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(lokalAppearanceProvider);
    await pumpEventQueue();
    expect(
      second.read(lokalAppearanceProvider).performanceLevel,
      LokalPerformanceLevel.ultra,
    );
    await second
        .read(lokalAppearanceProvider.notifier)
        .setPerformanceLevel(LokalPerformanceLevel.full);
    expect(second.read(lokalAppearanceProvider).ultraPerformanceMode, false);
    expect(second.read(lokalAppearanceProvider).performanceMode, false);
  });

  testWidgets(
    'three-way pill updates the saved mode without overflow on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (_, ref, _) => lokalPerformanceSelector(ref),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ultra'));
      await tester.pumpAndSettle();
      expect(
        container.read(lokalAppearanceProvider).performanceLevel,
        LokalPerformanceLevel.ultra,
      );
      await tester.tap(find.text('Off'));
      expect(find.text('Full'), findsNothing);
      await tester.pumpAndSettle();
      expect(
        container.read(lokalAppearanceProvider).performanceLevel,
        LokalPerformanceLevel.full,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ultra avoids motion lookup and restores it when disabled', (
    tester,
  ) async {
    final service = _ArtService();
    final suppression = ValueNotifier(false);
    addTearDown(suppression.dispose);
    Widget app(bool ultra) => MaterialApp(
      home: LokalPerformanceScope(
        enabled: ultra,
        child: MotionArtView(
          title: 'Song',
          artist: 'Artist',
          serviceOverride: service,
          suppressionOverride: suppression,
          fallback: const Text('still'),
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.calls, 0);
    expect(find.text('still'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(service.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('static/Ultra album art has no idle animation ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LokalPerformanceScope(
          enabled: true,
          child: SizedBox.square(dimension: 200, child: AnimatedAlbumArt()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.square(
          dimension: 200,
          child: AnimatedAlbumArt(animate: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
