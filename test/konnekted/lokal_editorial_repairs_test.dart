import 'dart:async';
import 'dart:ui' as ui;

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/navigation/lokal_navigation_switcher.dart';
import 'package:flick/core/navigation/root_navigator.dart';
import 'package:flick/core/theme/lokal_interaction.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/features/konnekted/konnekted_shell.dart';
import 'package:flick/features/konnekted/library/lokal_detail_header.dart';
import 'package:flick/features/konnekted/library/lokal_artwork_reveal.dart';
import 'package:flick/features/library_jobs/artist_metadata.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/features/konnekted/library/lokal_detail_fixed_backdrop.dart';
import 'package:flick/features/konnekted/library/lokal_detail_scroll_chrome.dart';
import 'package:flick/features/konnekted/library/lokal_genres.dart';
import 'package:flick/features/konnekted/library/lokal_music_detail_page.dart';
import 'package:flick/features/konnekted/library/lokal_online_catalogue.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestArtistMetadata extends ArtistMetadata {
  void publish(Map<String, String> portraits) => state = portraits;
  _TestArtistMetadata(this.portraits);
  final Map<String, String> portraits;

  @override
  Map<String, String> build() => portraits;
}

class _ReducedMotion implements ui.AccessibilityFeatures {
  @override
  bool get disableAnimations => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize <= 1 ? fontSize : fontSize * 2;
  @override
  double get textScaleFactor => 1;
}

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

class _PendingPlayPlayer extends _Player {
  static Completer<void>? pending;
  static int calls = 0;

  @override
  Future<void> play(
    Song song, {
    List<Song>? playlist,
    int? playlistIndex,
    PlaybackContext? context,
  }) {
    calls++;
    return pending!.future;
  }
}

class _PlayerService extends Fake implements PlayerService {
  @override
  final isPlayingNotifier = ValueNotifier(false);
  @override
  final isNetworkLoadingNotifier = ValueNotifier(false);
  @override
  final currentSongNotifier = ValueNotifier<Song?>(null);
  @override
  final onlinePreparationTitleNotifier = ValueNotifier<String?>(null);
  @override
  final bufferedPositionNotifier = ValueNotifier(Duration.zero);
  @override
  final durationNotifier = ValueNotifier(Duration.zero);
  @override
  final playbackDesyncedNotifier = ValueNotifier(false);
  @override
  final onlinePlaybackError = ValueNotifier<String?>(null);
}

const _song = Song(
  id: '1',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
);
const _duplicate = Song(
  id: '2',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  year: 1999,
  duration: Duration(minutes: 7),
  fileType: 'FLAC',
);

Widget _app(
  Widget child, {
  List<Song> library = const [],
  PlayerNotifier Function()? playerFactory,
  Map<String, String> artistPortraits = const {},
}) => ProviderScope(
  overrides: [
    artistMetadataProvider.overrideWith(
      () => _TestArtistMetadata(artistPortraits),
    ),
    konnektedLibraryProvider.overrideWithValue(AsyncData(library)),
    playerProvider.overrideWith(playerFactory ?? _Player.new),
    playerServiceProvider.overrideWithValue(_PlayerService()),
  ],
  child: MaterialApp(
    theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
    home: child,
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConstants.setAnimationsEnabled(true);
  });
  tearDown(() => AppConstants.setAnimationsEnabled(true));

  test('album duration requires every displayed row to be owned', () {
    expect(lokalAlbumRunningTime([]), isNull);
    expect(lokalAlbumRunningTime([_song, null]), isNull);
    expect(lokalAlbumRunningTime([_song, _duplicate]), '10 min');
  });

  testWidgets(
    'platform reduced motion and preference select clamping physics',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      const behavior = LokalScrollBehavior();
      expect(behavior.getScrollPhysics(context), isA<BouncingScrollPhysics>());
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          _ReducedMotion();
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      expect(behavior.getScrollPhysics(context), isA<ClampingScrollPhysics>());
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
      AppConstants.setAnimationsEnabled(false);
      expect(behavior.getScrollPhysics(context), isA<ClampingScrollPhysics>());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('genre cards grow at double text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: _NonlinearScaler(),
          ),
          child: const Scaffold(
            body: CustomScrollView(
              slivers: [
                LokalGenreGrid(
                  genres: [
                    LokalGenre('Long genre name for accessibility', [_song]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisExtent, greaterThan(250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('album year fallback and row-owned duration', (tester) async {
    const release = LokalCatalogueAlbum(
      title: 'Album',
      artist: 'Artist',
      date: '2020-01-01',
    );
    Future<String?> metadata(List<Song> songs) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            konnektedLibraryProvider.overrideWithValue(AsyncData(songs)),
          ],
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: LokalMusicDetailPage.album(
              title: 'Album',
              artist: 'Artist',
              localSongs: songs,
              release: release,
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .widget<LokalDetailHeader>(find.byType(LokalDetailHeader))
          .metadata;
    }

    expect(await metadata([]), '2020  ·  0 songs');
    expect(await metadata([_song]), '2020  ·  1 song  ·  3 min');
    expect(await metadata([_song, _duplicate]), '1999  ·  1 song  ·  3 min');
  });

  testWidgets(
    'top song tap does not flash or disable the header Play button',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _PendingPlayPlayer.pending = Completer<void>();
      _PendingPlayPlayer.calls = 0;
      addTearDown(() {
        if (_PendingPlayPlayer.pending?.isCompleted == false) {
          _PendingPlayPlayer.pending!.complete();
        }
        _PendingPlayPlayer.pending = null;
      });
      final songs = [
        const Song(
          id: 'top-1',
          title: 'Top Song 1',
          artist: 'Artist',
          album: 'Album',
          duration: Duration(minutes: 3),
          fileType: 'FLAC',
        ),
        const Song(
          id: 'top-2',
          title: 'Top Song 2',
          artist: 'Artist',
          album: 'Album',
          duration: Duration(minutes: 4),
          fileType: 'FLAC',
        ),
      ];
      await tester.pumpWidget(
        _app(
          LokalMusicDetailPage.artist(name: 'Artist', localSongs: songs),
          library: songs,
          playerFactory: _PendingPlayPlayer.new,
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Top Song 1').first);
      await tester.pump();
      await tester.tap(find.text('Top Song 1').first);
      await tester.pump();

      expect(_PendingPlayPlayer.calls, 1);
      final play = find.byType(FilledButton).first;
      expect(tester.widget<FilledButton>(play).onPressed, isNotNull);
      expect(find.descendant(
        of: play,
        matching: find.byIcon(Icons.play_arrow_rounded),
      ), findsOneWidget);
      expect(find.descendant(
        of: play,
        matching: find.byType(CircularProgressIndicator),
      ), findsNothing);

      // Repeated taps during an outstanding playback request are ignored
      // without toggling the header button into a disabled/loading state.
      await tester.tap(find.text('Top Song 1').first);
      await tester.pump();
      expect(_PendingPlayPlayer.calls, 1);
      expect(tester.widget<FilledButton>(play).onPressed, isNotNull);
      _PendingPlayPlayer.pending!.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'artist hero never briefly shows a featured album cover',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const song = Song(
        id: 'artist-local-song',
        title: 'Top Song',
        artist: 'Artist',
        album: 'Featured album',
        albumArt: '/tmp/featured_album_cover_not_a_portrait.jpg',
        duration: Duration(minutes: 3),
        fileType: 'FLAC',
      );
      final artistPage = LokalMusicDetailPage.artist(
        name: 'Artist',
        localSongs: const [song],
      );

      // Before metadata is available, the hero must be neutral. Even when
      // the artist has a known album cover, it may never fill the hero.
      await tester.pumpWidget(_app(artistPage, library: const [song]));
      await tester.pump();
      final hero = find.byType(LokalArtworkReveal);
      expect(hero, findsOneWidget);
      final initialImages = tester.widgetList<CachedImageWidget>(
        find.descendant(of: hero, matching: find.byType(CachedImageWidget)),
      );
      expect(initialImages, isEmpty);
      expect(
        tester.widget<LokalArtworkReveal>(hero).identity,
        'artist:artist:',
      );
      expect(tester.takeException(), isNull);

      // Once an actual artist portrait is provided, it is the only source
      // allowed in the hero and the featured album remains excluded.
      const portrait = '/tmp/verified_artist_portrait.png';
      final container = ProviderScope.containerOf(tester.element(find.byType(LokalMusicDetailPage)));
      (container.read(artistMetadataProvider.notifier) as _TestArtistMetadata).publish({'artist': portrait});
      await tester.pump();
      final updatedHero = find.byType(LokalArtworkReveal);
      final images = tester.widgetList<CachedImageWidget>(
        find.descendant(of: updatedHero, matching: find.byType(CachedImageWidget)),
      ).toList();
      expect(images, hasLength(1));
      expect(images.single.imagePath, portrait);
      expect(images.single.audioSourcePath, isNull);
      expect(
        tester.widget<LokalArtworkReveal>(updatedHero).identity,
        'artist:artist:$portrait',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('album hero retains album-cover fallback', (tester) async {
    const song = Song(
      id: 'album-song',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      albumArt: '/tmp/local_album_cover.jpg',
      duration: Duration(minutes: 4),
      fileType: 'FLAC',
    );
    await tester.pumpWidget(_app(
      LokalMusicDetailPage.album(
        title: 'Album',
        artist: 'Artist',
        localSongs: const [song],
      ),
      library: const [song],
    ));
    await tester.pump();
    final hero = find.byType(LokalArtworkReveal);
    final images = tester.widgetList<CachedImageWidget>(
      find.descendant(of: hero, matching: find.byType(CachedImageWidget)),
    );
    expect(images.map((image) => image.imagePath),
        contains('/tmp/local_album_cover.jpg'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('artist content keeps the theme background when scrolled',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final songs = List.generate(
      12,
      (index) => Song(
        id: '$index',
        title: 'Song $index',
        artist: 'Artist',
        album: 'Album $index',
        duration: const Duration(minutes: 3),
        fileType: 'FLAC',
      ),
    );
    await tester.pumpWidget(_app(LokalMusicDetailPage.artist(
      name: 'Artist',
      localSongs: songs,
    )));
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, LokalTokens.resolve(LokalThemeId.dark).bg);
    // Artwork is fixed behind the scroll view; song/release slivers remain
    // opaque so the image doesn't bleed through rows during scrolling.
    expect(scaffold.body, isA<Stack>());
    expect(find.byType(LokalDetailFixedBackdrop), findsOneWidget);
    expect(find.byType(LokalDetailHeroWash), findsOneWidget);
    expect(find.byType(LokalDetailProgressiveTopBlur), findsOneWidget);
    expect(find.byType(LokalDetailFloatingControls), findsOneWidget);
    expect(
      tester.widget<LokalDetailHeader>(find.byType(LokalDetailHeader))
          .controlsInOverlay,
      isTrue,
    );
    expect(
      find.byType(DecoratedSliver),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('main glass shell retains animated root tab navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(KonnektedShell(runtimeBuilder: (child) => child)),
    );
    await tester.pump();

    final switcher = tester.widget<LokalNavigationSwitcher>(
      find.byType(LokalNavigationSwitcher),
    );
    expect(switcher.retainVisitedTabs, isTrue);
    expect(switcher.instantNavigation, isFalse,
        reason: 'Glass footer optimizations must not remove the page slide');
    expect(switcher.efficientMotion, isFalse,
        reason: 'Root tabs use the original full-width adjacent-page push');
  });

  testWidgets(
    'shell slides Library to Search right and Search to Library left',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(KonnektedShell(runtimeBuilder: (child) => child)),
      );
      await tester.pump();

      // Search sits beyond the capsule's right edge, even though its enum
      // index precedes Library. The shell must follow the real dock layout.
      expect(KonnektedTab.dockOrder, [
        KonnektedTab.listen,
        KonnektedTab.library,
        KonnektedTab.settings,
        KonnektedTab.explore,
      ]);
      final dock = find.byType(KonnektedDock);
      final switcherFinder = find.byType(LokalNavigationSwitcher);
      final library = find.byKey(const ValueKey(KonnektedTab.library));
      final search = find.byKey(const ValueKey(KonnektedTab.explore));

      await tester.tap(find.descendant(
        of: dock,
        matching: find.bySemanticsLabel('Library'),
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.widget<KonnektedDock>(dock).selected,
          KonnektedTab.library);
      final origin = tester.getCenter(library).dx;
      final width = tester.getSize(switcherFinder).width;

      await tester.tap(find.descendant(
        of: dock,
        matching: find.bySemanticsLabel('Search'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 55));
      expect(tester.widget<KonnektedDock>(dock).selected,
          KonnektedTab.explore);
      expect(tester.widget<LokalNavigationSwitcher>(switcherFinder).direction,
          1);
      final outgoingLibrary = tester.getCenter(library).dx;
      final incomingSearch = tester.getCenter(search).dx;
      expect(outgoingLibrary, lessThan(origin));
      expect(incomingSearch, greaterThan(origin));
      expect(incomingSearch - outgoingLibrary, closeTo(width, .1));

      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.descendant(
        of: dock,
        matching: find.bySemanticsLabel('Library'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 55));
      expect(tester.widget<KonnektedDock>(dock).selected,
          KonnektedTab.library);
      expect(tester.widget<LokalNavigationSwitcher>(switcherFinder).direction,
          -1);
      final outgoingSearch = tester.getCenter(search).dx;
      final incomingLibrary = tester.getCenter(library).dx;
      expect(outgoingSearch, greaterThan(origin));
      expect(incomingLibrary, lessThan(origin));
      expect(outgoingSearch - incomingLibrary, closeTo(width, .1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system back at tab root keeps nested route and returns home once',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(KonnektedShell(runtimeBuilder: (child) => child)),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<KonnektedDock>(find.byType(KonnektedDock)).selected,
        KonnektedTab.library,
      );
      final navigator = nestedNavigatorKey.currentState!;
      expect(navigator.canPop(), isFalse);
      // A stale nested pop callback must not consume the root back action.
      tester
          .widget<NavigatorPopHandler<void>>(
            find.byType(NavigatorPopHandler<void>),
          )
          .onPopWithResult!(null);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(nestedNavigatorKey.currentState, same(navigator));
      expect(navigator.canPop(), isFalse);
      expect(
        tester.widget<KonnektedDock>(find.byType(KonnektedDock)).selected,
        KonnektedTab.listen,
      );
      expect(find.text('Press back again to exit'), findsNothing);
    },
  );

  testWidgets('system back pops a child without changing tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(KonnektedShell(runtimeBuilder: (child) => child)),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pump(const Duration(milliseconds: 500));
    nestedNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Child route')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Child route'), findsNothing);
    expect(nestedNavigatorKey.currentState!.canPop(), isFalse);
    expect(
      tester.widget<KonnektedDock>(find.byType(KonnektedDock)).selected,
      KonnektedTab.library,
    );
  });
}
