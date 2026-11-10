import 'dart:io';
import 'dart:ui' as ui;

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/utils/lokal_layout.dart';
import 'package:flick/core/utils/responsive.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_destination.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/konnekted/konnekted_tablet_workspace.dart';
import 'package:flick/features/konnekted/library/lokal_detail_header.dart';
import 'package:flick/features/konnekted/lokal_home_greeting.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_cover_flow.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _track = Song(
  id: 'one',
  title: 'A long and winding song title',
  artist: 'An artist with a long name',
  album: 'An album',
  duration: Duration(minutes: 4),
  fileType: 'FLAC',
);

Widget _app(
  Widget child, {
  double scale = 1,
  bool light = false,
  TargetPlatform? platform,
}) => ProviderScope(
  child: MaterialApp(
    theme: LokalTheme.build(
      LokalTokens.resolve(light ? LokalThemeId.light : LokalThemeId.dark),
    ).copyWith(platform: platform),
    home: MediaQuery(
      data: MediaQueryData.fromView(
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: Scaffold(body: child),
    ),
  ),
);

Widget _workspace({
  required Widget child,
  bool queueOpen = false,
  bool leftOpen = true,
  VoidCallback? toggleLeft,
  bool hasPlayer = true,
  Widget? mobileDock,
  VoidCallback? toggleQueue,
  ValueChanged<KonnektedDestination>? navigate,
}) => KonnektedTabletWorkspace(
  selected: KonnektedTab.listen,
  route: null,
  onSelect: (_) {},
  onNavigate: navigate ?? (_) {},
  hasPlayer: hasPlayer,
  player: KonnektedMiniPlayerContent(
    song: _track,
    isPlaying: false,
    onOpen: () {},
    onPlayPause: () {},
    onNext: () {},
    onPrevious: () {},
    onQueue: () {},
    progress: const LinearProgressIndicator(value: .4),
  ),
  mobileDock:
      mobileDock ?? const SizedBox(key: ValueKey('phone-dock'), height: 120),
  playerSidebar: const Center(child: Text('Player sidebar slot')),
  leftOpen: leftOpen,
  rightOpen: queueOpen,
  onToggleLeft: toggleLeft ?? () {},
  onToggleRight: toggleQueue ?? () {},
  child: child,
);

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      (LokalTheme.sans, 'assets/fonts/DMSans-Regular.ttf'),
      (LokalTheme.sans, 'assets/fonts/DMSans-SemiBold.ttf'),
      (LokalTheme.mono, 'assets/fonts/DMMono-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'navigation, controls and local pane geometry adapt without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final light in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          for (final size in [
            const Size(390, 844),
            const Size(540, 900),
            const Size(600, 960),
            const Size(768, 1024),
            const Size(1024, 768),
            const Size(1180, 820),
            const Size(1366, 1024),
            const Size(1440, 900),
            const Size(900, 500),
          ]) {
            tester.view.physicalSize = size;
            Size? paneSize;
            EdgeInsets? clearance;
            bool? tablet;
            double? typeSize;
            await tester.pumpWidget(
              _app(
                _workspace(
                  child: Builder(
                    builder: (context) {
                      paneSize = MediaQuery.sizeOf(context);
                      clearance = MediaQuery.paddingOf(context);
                      tablet = LokalLayout.isTablet(context);
                      typeSize = Responsive.textSize(context, 20);
                      return const SizedBox.expand(
                        key: ValueKey('content-pane'),
                      );
                    },
                  ),
                ),
                scale: scale,
                light: light,
              ),
            );
            await tester.pumpAndSettle();
            final wide = LokalLayout.usesSidebar(size);
            expect(tablet, wide);
            expect(
              paneSize,
              tester.getSize(find.byKey(const ValueKey('content-pane'))),
            );
            expect(
              find.byKey(const ValueKey('phone-dock')),
              wide ? findsNothing : findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('tablet-player-bar')),
              wide ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('tablet-player-sidebar')),
              findsNothing,
            );
            expect(clearance!.bottom, wide ? 0 : greaterThan(0));
            if (wide) expect(typeSize, closeTo(22, .01));
            expect(
              tester.takeException(),
              isNull,
              reason: '$size text=$scale light=$light',
            );
          }
        }
      }
    },
  );

  testWidgets('phone dock uses system insets once on Android and iOS', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final (height, bottom, keyboard) in [
        (844.0, 0.0, 0.0),
        (844.0, 24.0, 0.0),
        (932.0, 34.0, 0.0),
        (844.0, 0.0, 300.0),
      ]) {
        tester.view
          ..physicalSize = Size(390, height)
          ..padding = FakeViewPadding(top: 44, bottom: bottom)
          ..viewPadding = FakeViewPadding(
            top: 44,
            bottom: keyboard > 0 ? 34 : bottom,
          )
          ..viewInsets = FakeViewPadding(bottom: keyboard);
        for (final hasPlayer in [false, true]) {
          for (final collapsed in [false, true]) {
            EdgeInsets? contentPadding;
            EdgeInsets? dockPadding;
            await tester.pumpWidget(
              _app(
                _workspace(
                  hasPlayer: hasPlayer,
                  mobileDock: Builder(
                    builder: (context) {
                      dockPadding = MediaQuery.paddingOf(context);
                      return KonnektedDock(
                        selected: KonnektedTab.listen,
                        onSelect: (_) {},
                        hasMiniPlayer: hasPlayer,
                        collapsed: collapsed,
                        miniPlayer: const SizedBox.expand(),
                      );
                    },
                  ),
                  child: Builder(
                    builder: (context) {
                      contentPadding = MediaQuery.paddingOf(context);
                      return const SizedBox.expand();
                    },
                  ),
                ),
                platform: platform,
              ),
            );
            await tester.pumpAndSettle();
            final reason =
                '$platform bottom=$bottom keyboard=$keyboard player=$hasPlayer collapsed=$collapsed';
            expect(dockPadding!.bottom, bottom, reason: reason);
            expect(
              contentPadding!.bottom,
              KonnektedDock.reservedHeight(
                hasMiniPlayer: hasPlayer,
                systemInset: bottom,
              ),
              reason: reason,
            );
            expect(
              tester
                  .getBottomLeft(find.byKey(const ValueKey('dock-tab-glass')))
                  .dy,
              closeTo(height - keyboard - (bottom > 8 ? bottom : 8), .01),
              reason: reason,
            );
            expect(tester.takeException(), isNull, reason: reason);
          }
        }
      }
    }
  });

  testWidgets('tablet without playback retains the bottom system inset', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1024, 768)
      ..devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
    EdgeInsets? padding;
    await tester.pumpWidget(
      _app(
        _workspace(
          hasPlayer: false,
          child: Builder(
            builder: (context) {
              padding = MediaQuery.paddingOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(padding!.bottom, 24);
    expect(find.byKey(const ValueKey('tablet-player-bar')), findsNothing);
    expect(find.byKey(const ValueKey('tablet-player-sidebar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard keeps tablet navigation and insets stay inside the window',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1024, 768)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      tester.view.padding = const FakeViewPadding(left: 24, right: 24, top: 24);
      await tester.pumpWidget(
        _app(_workspace(child: const Center(child: Text('Search results')))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-dock')), findsNothing);
      expect(find.byKey(const ValueKey('tablet-player-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rotation policy uses the display instead of a split app window',
    (tester) async {
      final display = tester.view.display;
      addTearDown(display.reset);
      display.size = const Size(1536, 2048);
      display.devicePixelRatio = 2;
      expect(LokalLayout.defaultOrientations(view: tester.view), isEmpty);
      display.size = const Size(1080, 2400);
      display.devicePixelRatio = 3;
      expect(LokalLayout.defaultOrientations(view: tester.view), [
        DeviceOrientation.portraitUp,
      ]);
    },
  );

  testWidgets(
    'rotation and queue toggles retain nested navigation and scroll position',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1366, 1024);
      addTearDown(tester.view.reset);
      final navigator = GlobalKey<NavigatorState>();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var queueOpen = true;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => _workspace(
              queueOpen: queueOpen,
              toggleQueue: () => setState(() => queueOpen = !queueOpen),
              child: Navigator(
                key: navigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Center(
                    child: TextButton(
                      onPressed: () {
                        navigator.currentState!.push(
                          MaterialPageRoute<void>(
                            builder: (_) => ListView.builder(
                              controller: scroll,
                              itemExtent: 60,
                              itemCount: 100,
                              itemBuilder: (_, i) => Text('Song $i'),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open album'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open album'));
      await tester.pumpAndSettle();
      scroll.jumpTo(600);
      await tester.pump();
      final originalNavigator = navigator.currentState;
      await tester.tap(find.byKey(const ValueKey('toggle-right-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tablet-player-sidebar')), findsNothing);
      for (final size in [
        const Size(768, 1024),
        const Size(540, 900),
        const Size(1366, 1024),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(navigator.currentState, same(originalNavigator));
        expect(navigator.currentState!.canPop(), isTrue);
        expect(scroll.offset, 600);
        expect(tester.takeException(), isNull);
      }
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Open album'), findsOneWidget);
    },
  );

  testWidgets('tablet carousel grows and remains selectable', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    final albums = [
      for (var i = 0; i < 9; i++)
        AlbumGroup(
          key: '$i',
          albumName: 'Album $i',
          albumArtist: 'Artist',
          songs: [_track],
        ),
    ];
    final selected = <int>[];
    await tester.pumpWidget(
      _app(
        _workspace(
          child: SingleChildScrollView(
            child: LokalCoverFlow(
              albums: albums,
              initialIndex: 4,
              onPlay: (_, _) {},
              onSelect: selected.add,
              cover: (_) => const ColoredBox(color: Colors.deepPurple),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stage = find.descendant(
      of: find.byType(LokalCoverFlow),
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.child is AnimatedBuilder,
      ),
    );
    expect(tester.getSize(stage).height, greaterThan(340));
    await tester.tap(
      find.descendant(
        of: find.byType(LokalCoverFlow),
        matching: find.byTooltip('Next'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(stage));
    await tester.pumpAndSettle();
    expect(selected, [5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide album header puts artwork next to its identity at large text',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: LokalDetailHeader(
              title: 'An album with a fairly long title',
              artwork: const SizedBox.expand(key: ValueKey('album-cover')),
              isArtist: false,
              fixedArtwork: true,
              controlsInOverlay: true,
              background: Colors.black,
              onBack: () {},
              onArtworkTap: () {},
              onOnline: () {},
              onlineEnabled: false,
              onMore: () {},
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('album-cover'))).right,
        lessThan(
          tester.getRect(find.text('An album with a fairly long title')).left,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide Settings switches categories in place and keeps search working',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1180, 820);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          LokalSettingsPage(
            sectionsBuilder: (group, _, _) => [
              LokalSettingsSection(
                title: '${group.label} controls',
                children: [
                  LokalSettingRow(label: 'Control for ${group.label}'),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Control for Appearance'), findsOneWidget);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Control for Library'), findsOneWidget);
      expect(find.byType(LokalSettingsPage), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Control for Playback');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(LokalSettingRow, 'Control for Playback'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Local home renders in the tablet workspace', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1366, 1024);
    addTearDown(tester.view.reset);
    final songs = [
      for (var i = 0; i < 12; i++)
        Song(
          id: '$i',
          title: ['Late night radio', 'Open water', 'A different light'][i % 3],
          artist: ['The Quiet Hours', 'North Shore', 'Soft Focus'][i % 3],
          album: 'Volume ${i + 1}',
          duration: const Duration(minutes: 4),
          fileType: 'FLAC',
        ),
    ];
    final mixes = [
      for (var i = 0; i < 6; i++)
        LokalMix(
          id: '$i',
          name: [
            'Daily Mix',
            'New Arrivals',
            'Most Played',
            'Discovery Weekly',
            'Ambient',
            'Jazz',
          ][i],
          type: LokalMixType.daily,
          tracks: songs.skip(i).take(4).toList(),
        ),
    ];
    final capture = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          konnektedLibraryProvider.overrideWithValue(AsyncData(songs)),
          konnektedMixesProvider.overrideWith((ref) async => mixes),
          konnektedGreetingProvider.overrideWith(
            (ref) => Stream.value(
              lokalHomeMessages(const [], now: DateTime(2026, 11, 10, 9)),
            ),
          ),
          konnektedRecentSongsProvider.overrideWith(
            (ref) => Stream.value(songs),
          ),
          konnektedFavoritesProvider.overrideWithValue(AsyncData(songs)),
          konnektedMadeForYouProvider.overrideWithValue(
            AsyncData([
              for (final song in songs)
                LokalMadeForYouPick(song: song, mix: mixes.first),
            ]),
          ),
        ],
        child: _app(
          RepaintBoundary(
            key: capture,
            child: _workspace(
              child: KonnektedHome(onNavigate: (_) {}, onPlay: (_, _) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LokalCoverFlow), findsOneWidget);
    expect(find.text('Good morning'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final output = Platform.environment['LOKAL_TABLET_CAPTURE'];
    if (output != null) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
