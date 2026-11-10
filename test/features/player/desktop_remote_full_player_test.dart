import 'package:flick/features/player/widgets/lokal_player_columns.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/player/screens/desktop_remote_full_player.dart';
import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
import 'package:flick/features/player/widgets/artwork_gradient_backdrop.dart';
import 'package:flick/features/player/widgets/artwork_mesh_blur_backdrop.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
import 'package:flick/features/player/widgets/song_stage_carousel.dart';
import 'package:flick/features/player/screens/desktop_remote_lyrics_panel.dart';
import 'package:flick/features/queue/screens/queue_screen.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const desktopSong = Song(
  id: 'desktop:desktop-id-123',
  title: 'Desktop Recording',
  artist: 'Desktop Performer',
  album: 'Desktop Album',
  duration: Duration(minutes: 4),
  fileType: 'FLAC',
  sourceType: 'lokal',
  remoteId: 'desktop-id-123',
);

class _RemotePlayer extends PlayerNotifier {
  final actions = <String>[];

  @override
  PlayerState build() => const PlayerState(
    currentSong: desktopSong,
    duration: Duration(minutes: 4),
    position: Duration(seconds: 45),
    isPlaying: true,
  );

  @override
  Future<void> next() async => actions.add('next');

  @override
  Future<void> previous({bool allowRestart = true}) async =>
      actions.add('previous');

  @override
  Future<void> previousBySwipe() async => actions.add('previous-swipe');

  @override
  Future<void> togglePlayPause() async => actions.add('toggle');

  @override
  Future<void> seek(Duration position) async =>
      actions.add('seek:${position.inSeconds}');

  @override
  Future<void> setVolume(double volume) async =>
      actions.add('volume:${volume.toStringAsFixed(2)}');
}

class _RemoteController extends LokalRemoteController {
  @override
  LokalRemoteControllerState build() => LokalRemoteControllerState(
    controlsDesktop: true,
    status: LokalRemoteConnectionStatus.connected,
    desktopName: 'ExpertBook',
    snapshot: LokalRemoteSnapshot(
      connected: true,
      isPlaying: true,
      progress: 45,
      duration: 240,
      volume: .5,
      repeat: 'none',
      shuffle: false,
      currentTrack: const LokalRemoteTrack(
        id: 'desktop-id-123',
        title: 'Desktop Recording',
        artist: 'Desktop Performer',
        album: 'Desktop Album',
      ),
      updatedAt: 123,
      currentIndex: 1,
      queue: const [
        LokalRemoteTrack(
          id: 'desktop-previous',
          title: 'Previous',
          artist: 'Performer',
        ),
        LokalRemoteTrack(
          id: 'desktop-id-123',
          title: 'Desktop Recording',
          artist: 'Desktop Performer',
          album: 'Desktop Album',
        ),
        LokalRemoteTrack(
          id: 'desktop-next',
          title: 'Next',
          artist: 'Performer',
        ),
      ],
    ),
  );
}

/// A paired desktop can expose transport controls before its queue snapshot
/// arrives. Swipes must still issue next/previous commands in that case.
class _RemoteWithoutQueue extends _RemoteController {
  @override
  LokalRemoteControllerState build() => LokalRemoteControllerState(
    controlsDesktop: true,
    status: LokalRemoteConnectionStatus.connected,
    desktopName: 'ExpertBook',
    snapshot: const LokalRemoteSnapshot(
      connected: true,
      isPlaying: true,
      progress: 45,
      duration: 240,
      volume: .5,
      repeat: 'none',
      shuffle: false,
      currentTrack: LokalRemoteTrack(
        id: 'desktop-id-123',
        title: 'Desktop Recording',
        artist: 'Desktop Performer',
        album: 'Desktop Album',
      ),
      updatedAt: 123,
      queue: [],
      currentIndex: -1,
    ),
  );
}

void main() {
  test('remote artwork state retains and clears only the current cover', () {
    const initial = LokalRemoteControllerState();
    final cover = initial.copyWith(remoteArtworkPath: '/app/cache/cover.webp');
    expect(cover.remoteArtworkPath, '/app/cache/cover.webp');
    expect(
      cover
          .copyWith(status: LokalRemoteConnectionStatus.connected)
          .remoteArtworkPath,
      '/app/cache/cover.webp',
    );
    expect(cover.copyWith(clearRemoteArtwork: true).remoteArtworkPath, isNull);
  });

  test(
    'desktop now-playing conversion uses the cached cover, never a PC path',
    () {
      const track = LokalRemoteTrack(
        id: 'recording-123',
        title: 'From PC',
        artist: 'Producer',
        album: 'Album',
        artworkPath: r'C:\\Users\\Desktop\\cover.jpg',
        duration: 201,
      );
      final noCover = songFromDesktopRemoteTrack(track);
      expect(noCover.albumArt, isNull);
      expect(noCover.id, 'desktop:recording-123');
      expect(noCover.remoteId, 'recording-123');
      expect(noCover.duration, const Duration(seconds: 201));
      final cached = songFromDesktopRemoteTrack(
        track,
        artworkPath: '/data/user/0/lokal/cache/art.webp',
      );
      expect(cached.albumArt, '/data/user/0/lokal/cache/art.webp');
      expect(cached.albumArt, isNot(track.artworkPath));
    },
  );

  test(
    'every desktop queue item keeps its own authenticated artwork marker',
    () {
      const first = LokalRemoteTrack(
        id: 'recording-a',
        title: 'First',
        artist: 'Artist',
        duration: 180,
      );
      const second = LokalRemoteTrack(
        id: 'recording-b',
        title: 'Second',
        artist: 'Artist',
        duration: 185,
      );
      final current = songFromDesktopRemoteTrack(
        first,
        artworkServerId: 42,
        artworkPath: '/data/user/0/lokal/cache/current.webp',
      );
      final queued = songFromDesktopRemoteTrack(second, artworkServerId: 42);
      expect(current.albumArt, '/data/user/0/lokal/cache/current.webp');
      expect(current.filePath, 'lokal://42/recording-a');
      expect(queued.albumArt, 'lokal-cover://recording-b');
      expect(queued.filePath, 'lokal://42/recording-b');
      expect(queued.remoteServerId, 42);
      expect(queued.remoteId, 'recording-b');
      expect(queued.albumArt, isNot(current.albumArt));
      final beforePairing = songFromDesktopRemoteTrack(second);
      expect(beforePairing.albumArt, isNull);
      expect(beforePairing.filePath, isNull);
    },
  );

  test('paired artwork server is invalidated on remote target changes', () {
    const initial = LokalRemoteControllerState();
    final paired = initial.copyWith(artworkServerId: 19);
    expect(paired.artworkServerId, 19);
    expect(
      paired.copyWith(remoteArtworkPath: '/cache/current.webp').artworkServerId,
      19,
    );
    expect(paired.copyWith(clearArtworkServer: true).artworkServerId, isNull);
  });

  testWidgets(
    'remote tablet keeps controls beside the cover and scrolls large text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [const Size(1024, 768), const Size(1366, 1024)]) {
        tester.view.physicalSize = size;
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                playerProvider.overrideWith(_RemotePlayer.new),
                lokalInitialAppearanceProvider.overrideWithValue(
                  const LokalAppearance(fullscreenCover: true),
                ),
                lokalRemoteControllerProvider.overrideWith(
                  _RemoteController.new,
                ),
              ],
              child: MaterialApp(
                theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: DesktopRemoteFullPlayer(onClose: () {}),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final columns = tester.widget<LokalPlayerColumns>(
            find.byType(LokalPlayerColumns),
          );
          expect(
            tester.getRect(find.byWidget(columns.stage)).right,
            lessThan(tester.getRect(find.byWidget(columns.controls)).left),
          );
          expect(find.byType(PlayerTransportControls), findsOneWidget);
          expect(find.byType(FullBleedArtworkFrame), findsNothing);
          expect(
            find.byKey(const ValueKey('tablet-square-cover-player')),
            findsOneWidget,
          );
          final square = tester.getSize(
            find.byKey(const ValueKey('desktop-cover:desktop:desktop-id-123')),
          );
          expect(square.width, closeTo(square.height, .01));
          expect(square.width, greaterThan(size.width * .4));
          expect(tester.takeException(), isNull, reason: '$size text=$scale');
        }
      }
    },
  );

  testWidgets('scrolling follows rendered overflow and text scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A normal-size viewport can fit the full player at normal text size
    // but overflow at accessibility scale; height alone is not sufficient.
    tester.view
      ..physicalSize = const Size(530, 840)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget app(double scale) => ProviderScope(
      overrides: [
        playerProvider.overrideWith(_RemotePlayer.new),
        lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
      ],
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: DesktopRemoteFullPlayer(onClose: () {}),
          ),
        ),
      ),
    );

    SingleChildScrollView scrollView() => tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );

    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    final normalExtent = scrollView().controller!.position.maxScrollExtent;
    expect(normalExtent, greaterThanOrEqualTo(0));

    await tester.pumpWidget(app(2.8));
    await tester.pumpAndSettle();
    expect(
      scrollView().controller!.position.maxScrollExtent,
      greaterThan(normalExtent),
    );
    expect(scrollView().physics, isA<ClampingScrollPhysics>());

    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(
      scrollView().controller!.position.maxScrollExtent,
      closeTo(normalExtent, 1),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up_rounded).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal cover swipes issue remote next, not phone playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _RemotePlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(() => player),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SongStageCarousel), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('desktop-cover:desktop:desktop-id-123')),
      const Offset(-300, 0),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(player.actions, contains('next'));
  });

  testWidgets('desktop queue enters with an in-place animated reveal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_RemotePlayer.new),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump();
    expect(find.byType(QueueScreen), findsNothing);
    expect(find.byType(QueueList), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    final opacity = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((w) => w.opacity);
    expect(opacity.any((v) => v > 0 && v < 1), isTrue);
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('UP NEXT'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to player').first);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(QueueList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote lyrics opens for current desktop song', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_RemotePlayer.new),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Lyrics'));
    await tester.pump();
    expect(find.byType(DesktopRemoteLyricsPanel), findsOneWidget);
    await tester.tap(find.byTooltip('Back to player').first);
    await tester.pump();
    expect(find.byType(DesktopRemoteLyricsPanel), findsNothing);
  });

  testWidgets('remote sleeve fills the regular full-player artwork width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_RemotePlayer.new),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cover = find.byKey(
      const ValueKey('desktop-cover:desktop:desktop-id-123'),
    );
    expect(cover, findsOneWidget);
    // Regular mode reserves 23 px horizontally per edge for the artwork
    // stage. A height percentage must never shrink it on a tall phone.
    expect(tester.getSize(cover).width, closeTo(342, 1));
    expect(tester.getSize(cover).height, closeTo(342, 1));
    expect(find.byType(FullBleedArtworkFrame), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote mode honors the shared fullscreen-cover preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_RemotePlayer.new),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
          lokalInitialAppearanceProvider.overrideWithValue(
            const LokalAppearance(fullscreenCover: true),
          ),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FullBleedArtworkFrame), findsWidgets);
    final coverFrame = tester.widget<FullBleedArtworkFrame>(
      find.byType(FullBleedArtworkFrame).first,
    );
    expect(coverFrame.dimOnExpand, isFalse);
    expect(coverFrame.fadeOutCompletely, isTrue);
    expect(find.byType(ArtworkGradientBackdrop), findsOneWidget);
    expect(find.byType(ArtworkMeshBlurBackdrop), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote-full-cover-spacer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-full-cover:desktop:desktop-id-123')),
      findsOneWidget,
    );
    // Fullcover replaces the square sleeve, it doesn't render two covers.
    expect(
      find.byKey(const ValueKey('desktop-cover:desktop:desktop-id-123')),
      findsNothing,
    );
    expect(find.text('Desktop Recording'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen-cover swipe forwards through chrome to desktop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _RemotePlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(() => player),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
          lokalInitialAppearanceProvider.overrideWithValue(
            const LokalAppearance(fullscreenCover: true),
          ),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    final swipeZone = find.byKey(const ValueKey('remote-full-cover-spacer'));
    expect(swipeZone, findsOneWidget);
    expect(
      tester
          .widget<SongStageCarousel>(find.byType(SongStageCarousel).first)
          .allowUnresolvedSwipe,
      isTrue,
    );
    await tester.drag(swipeZone, const Offset(-280, 0));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(player.actions, contains('next'));
    await tester.drag(swipeZone, const Offset(280, 0));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(player.actions, contains('previous-swipe'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-cover swipes work even before desktop queue arrives', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _RemotePlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(() => player),
          lokalRemoteControllerProvider.overrideWith(_RemoteWithoutQueue.new),
          lokalInitialAppearanceProvider.overrideWithValue(
            const LokalAppearance(fullscreenCover: true),
          ),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    final cover = find.byKey(const ValueKey('remote-full-cover-spacer'));
    expect(cover, findsOneWidget);
    await tester.drag(cover, const Offset(-300, 0));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(player.actions, contains('next'));
    await tester.drag(cover, const Offset(300, 0));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(player.actions, contains('previous-swipe'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping down on the remote cover dismisses the full player', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var closes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_RemotePlayer.new),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () => closes++),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('desktop-cover:desktop:desktop-id-123')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact player can dismiss by pulling down at scroll top', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 580)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var closes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith(_RemotePlayer.new),
          lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
          home: DesktopRemoteFullPlayer(onClose: () => closes++),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('desktop-cover:desktop:desktop-id-123')),
      const Offset(0, 270),
    );
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop full player displays remote track rather than the last mobile song',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final player = _RemotePlayer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith(() => player),
            lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
          ],
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
            home: DesktopRemoteFullPlayer(onClose: () {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Desktop Recording'), findsOneWidget);
      expect(find.text('Desktop Performer'), findsOneWidget);
      expect(find.text('ExpertBook'), findsOneWidget);
      expect(find.text('Last Mobile Song'), findsNothing);
      expect(find.byType(PlayerTransportControls), findsOneWidget);
      final controls = tester.widget<PlayerTransportControls>(
        find.byType(PlayerTransportControls),
      );
      controls.onNext();
      await tester.pump();
      controls.onPrevious();
      await tester.pump();
      controls.onPlayPause();
      await tester.pump();
      expect(player.actions, ['next', 'previous', 'toggle']);

      final seek = tester.widgetList<Slider>(find.byType(Slider)).first;
      seek.onChangeStart?.call(.5);
      seek.onChanged?.call(.5);
      seek.onChangeEnd?.call(.5);
      await tester.pump();
      expect(player.actions, contains('seek:120'));
      expect(tester.takeException(), isNull);
    },
  );
}
