import 'package:flick/features/classipod/classipod_browse.dart';
import 'package:flick/features/classipod/classipod_data.dart';
import 'package:flick/features/classipod/classipod_screen.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_library.dart';
import 'package:flick/l10n/generated/app_localizations.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'classipod_fixtures.dart';

void main() {
  late RecordingPlayback playback;
  late ProviderContainer container;
  var retries = 0;

  setUp(() {
    playback = RecordingPlayback();
    retries = 0;
    container = ProviderContainer(
      overrides: [
        konnektedLibraryProvider.overrideWith(
          (ref) => ref.watch(fixtureLibraryProvider),
        ),
        classipodPlayerStateProvider.overrideWith(
          (ref) => ref.watch(fixturePlayerProvider),
        ),
        classipodPlaybackProvider.overrideWithValue(playback),
        classipodReduceMotionProvider.overrideWithValue(false),
        classipodReloadProvider.overrideWithValue(() => retries++),
        classipodArtworkProvider.overrideWithValue(
          (song) => ColoredBox(
            color: Colors.blueGrey,
            child: Center(child: Text('art:${song.id}')),
          ),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpApp(
    WidgetTester tester, {
    bool library = false,
    double scale = 1,
    bool reduced = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              disableAnimations: reduced,
            ),
            child: child!,
          ),
          home: library
              ? Scaffold(
                  body: KonnektedLibrary(
                    onNavigate: (_) =>
                        fail('Classipod must use a pushed route'),
                  ),
                )
              : const ClassipodScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.hitTestable().evaluate().isEmpty) {
      await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
      await tester.pumpAndSettle();
    }
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Library easter egg pushes Classipod, keeps Library mounted, and exits',
    (tester) async {
      await pumpApp(tester, library: true);
      // No visible entry: a long press on Library's title opens it.
      expect(find.text('Classipod'), findsNothing);
      await tester.longPress(find.descendant(of: find.byType(KonnektedLibrary), matching: find.text('Library')).first);
      await tester.pumpAndSettle();
      expect(find.byType(ClassipodScreen), findsOneWidget);
      expect(
        find.byType(KonnektedLibrary, skipOffstage: false),
        findsOneWidget,
      );
      final library = tester.element(
        find.byType(KonnektedLibrary, skipOffstage: false),
      );
      expect(library.mounted, isTrue);
      await tap(tester, find.text('Songs'));
      await tap(tester, find.byKey(const Key('classipod-exit')));
      expect(find.byType(ClassipodScreen), findsNothing);
      expect(library.mounted, isTrue);
      expect(playback.calls, isEmpty);
    },
  );

  testWidgets(
    'touch songs dispatch actual queue, live state refreshes metadata and transport',
    (tester) async {
      await pumpApp(tester);
      await tap(tester, find.text('Songs'));
      await tap(tester, find.text('Beta track'));
      expect(playback.song, same(beta));
      expect(playback.queue, [alpha, beta, gamma]);
      expect(find.textContaining('No song playing.'), findsOneWidget);

      container
          .read(fixturePlayerProvider.notifier)
          .update(
            const PlayerState(
              currentSong: beta,
              isPlaying: true,
              queue: [alpha, beta, gamma],
              currentIndex: 1,
              position: Duration(seconds: 32),
              duration: Duration(minutes: 4),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Beta track'), findsOneWidget);
      expect(find.text('art:beta'), findsOneWidget);
      await tap(tester, find.byTooltip('Pause'));
      await tap(tester, find.byTooltip('Next track'));
      await tap(tester, find.byTooltip('Previous track'));
      expect(playback.calls, ['play:beta', 'toggle', 'next', 'previous']);

      container
          .read(fixturePlayerProvider.notifier)
          .update(
            const PlayerState(
              currentSong: gamma,
              queue: [alpha, beta, gamma],
              currentIndex: 2,
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Gamma track'), findsOneWidget);
      expect(find.text('Beta track'), findsNothing);
      expect(find.text('art:gamma'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      await tap(tester, find.byTooltip('Show queue'));
      await tap(tester, find.text('Alpha track'));
      expect(playback.calls.last, 'queue:0');
    },
  );

  testWidgets(
    'albums, artists and Cover Flow open genuine grouped tracks and artwork',
    (tester) async {
      await pumpApp(tester);
      await tap(tester, find.text('Albums'));
      await tap(tester, find.text('First album'));
      final rows = tester
          .widget<ClassipodList>(find.byType(ClassipodList))
          .rows;
      expect(rows.map((r) => r.title), ['Beta track', 'Alpha track']);
      await tap(tester, find.byTooltip('Back to previous menu'));
      await tap(tester, find.byTooltip('Back to previous menu'));
      await tap(tester, find.text('Artists'));
      await tap(tester, find.text('Artist two'));
      expect(find.text('Gamma track'), findsOneWidget);
      expect(find.text('Alpha track'), findsNothing);
      await tap(tester, find.byTooltip('Back to previous menu'));
      await tap(tester, find.byTooltip('Back to previous menu'));
      await tap(tester, find.text('Cover Flow'));
      expect(find.text('art:alpha'), findsOneWidget);
      expect(find.text('art:gamma'), findsOneWidget);
      expect(
        tester
            .widget<ClassipodCoverFlow>(find.byType(ClassipodCoverFlow))
            .reduceMotion,
        isTrue,
      );
      await tap(tester, find.byTooltip('Next item'));
      expect(find.text('2 of 2 albums'), findsOneWidget);
      await tap(tester, find.text('Open album'));
      await tap(tester, find.text('Gamma track'));
      expect(playback.song, same(gamma));
      expect(playback.queue, [gamma]);
    },
  );

  testWidgets(
    'keyboard, wheel buttons and system back share bounded navigation',
    (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Alpha track'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<ClassipodList>(find.byType(ClassipodList)).selected,
        2,
      );
      await tap(tester, find.byTooltip('Previous item'));
      expect(
        tester.widget<ClassipodList>(find.byType(ClassipodList)).selected,
        1,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Local library'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('First album'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Local library'), findsOneWidget);
      expect(playback.calls, isEmpty);
    },
  );

  testWidgets('rotary gesture advances selection and center selects', (
    tester,
  ) async {
    await pumpApp(tester);
    final wheel = find.byKey(const Key('classipod-wheel'));
    await tester.ensureVisible(wheel);
    final center = tester.getCenter(wheel);
    final gesture = await tester.startGesture(center + const Offset(80, -45));
    await gesture.moveTo(center + const Offset(95, 0));
    await gesture.moveTo(center + const Offset(80, 50));
    await gesture.up();
    await tester.pumpAndSettle();
    final list = tester.widget<ClassipodList>(find.byType(ClassipodList));
    expect(list.selected, inInclusiveRange(1, 5));
    await tap(tester, find.byTooltip('Select item'));
    expect(find.text('Local library'), findsNothing);
    expect(playback.calls, isEmpty);
  });

  testWidgets(
    'loading, failure with retry, empty library, empty queue and no song are distinct',
    (tester) async {
      container
          .read(fixtureLibraryProvider.notifier)
          .update(const AsyncLoading());
      await pumpApp(tester);
      await tester.tap(find.text('Songs'));
      await tester.pump();
      expect(find.text('Loading local library…'), findsOneWidget);
      container
          .read(fixtureLibraryProvider.notifier)
          .update(
            AsyncError(StateError('database unavailable'), StackTrace.empty),
          );
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load your local library.'), findsOneWidget);
      await tap(tester, find.text('Try again'));
      expect(retries, 1);
      container
          .read(fixtureLibraryProvider.notifier)
          .update(const AsyncData([]));
      await tester.pumpAndSettle();
      expect(find.textContaining('No local music here yet.'), findsOneWidget);
      await tap(tester, find.byTooltip('Back to previous menu'));
      await tap(tester, find.text('Queue'));
      expect(find.textContaining('The queue is empty.'), findsOneWidget);
      await tap(tester, find.byTooltip('Back to previous menu'));
      await tap(tester, find.text('Now playing'));
      expect(find.textContaining('No song playing.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
            )
            .onPressed,
        isNull,
      );
      expect(playback.calls, isEmpty);
    },
  );

  testWidgets('playback failure stays on songs and can be retried', (
    tester,
  ) async {
    playback.onPlay = () async => throw StateError('offline');
    await pumpApp(tester);
    await tap(tester, find.text('Songs'));
    await tap(tester, find.text('Alpha track'));
    expect(find.text('Playback couldn’t complete. Try again.'), findsOneWidget);
    expect(find.text('Beta track'), findsOneWidget);
    playback.onPlay = null;
    await tap(tester, find.text('Alpha track'));
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Playback couldn’t complete. Try again.'), findsNothing);
  });

  testWidgets(
    'narrow safe-area and large-text UI exposes accessible selection and exit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      try {
        await pumpApp(tester, scale: 2);
        expect(find.byKey(const Key('classipod-exit')), findsOneWidget);
        await tap(tester, find.text('Songs'));
        expect(
          tester
              .getSemantics(find.text('Alpha track'))
              .getSemanticsData()
              .label,
          contains('Alpha track'),
        );
        await tap(tester, find.byTooltip('Next item'));
        await tap(tester, find.byTooltip('Select item'));
        expect(playback.song, same(beta));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'landscape Cover Flow works and app preference disables animation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(740, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      container.updateOverrides([
        konnektedLibraryProvider.overrideWith(
          (ref) => ref.watch(fixtureLibraryProvider),
        ),
        classipodPlayerStateProvider.overrideWith(
          (ref) => ref.watch(fixturePlayerProvider),
        ),
        classipodPlaybackProvider.overrideWithValue(playback),
        classipodReduceMotionProvider.overrideWithValue(true),
        classipodReloadProvider.overrideWithValue(() => retries++),
        classipodArtworkProvider.overrideWithValue(
          (song) => Text('art:${song.id}'),
        ),
      ]);
      await pumpApp(tester, reduced: false);
      // Wheel can reach offscreen menu rows without pointer scrolling.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ClassipodCoverFlow>(find.byType(ClassipodCoverFlow))
            .reduceMotion,
        isTrue,
      );
      final animations = tester.widgetList<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(
        animations.every((widget) => widget.duration == Duration.zero),
        isTrue,
      );
      await tap(tester, find.byTooltip('Next item'));
      await tap(tester, find.text('Open album'));
      expect(find.text('Gamma track'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
