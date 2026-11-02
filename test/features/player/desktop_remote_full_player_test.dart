import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/player/screens/desktop_remote_full_player.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
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
    ),
  );
}

void main() {
  test('remote artwork state retains and clears only the current cover', () {
    const initial = LokalRemoteControllerState();
    final cover = initial.copyWith(remoteArtworkPath: '/app/cache/cover.webp');
    expect(cover.remoteArtworkPath, '/app/cache/cover.webp');
    expect(cover.copyWith(status: LokalRemoteConnectionStatus.connected).remoteArtworkPath,
        '/app/cache/cover.webp');
    expect(cover.copyWith(clearRemoteArtwork: true).remoteArtworkPath, isNull);
  });

  test('desktop now-playing conversion uses the cached cover, never a PC path', () {
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
      track, artworkPath: '/data/user/0/lokal/cache/art.webp',
    );
    expect(cached.albumArt, '/data/user/0/lokal/cache/art.webp');
    expect(cached.albumArt, isNot(track.artworkPath));
  });

  test('every desktop queue item keeps its own authenticated artwork marker', () {
    const first = LokalRemoteTrack(
      id: 'recording-a',
      title: 'First', artist: 'Artist', duration: 180,
    );
    const second = LokalRemoteTrack(
      id: 'recording-b',
      title: 'Second', artist: 'Artist', duration: 185,
    );
    final current = songFromDesktopRemoteTrack(
      first, artworkServerId: 42,
      artworkPath: '/data/user/0/lokal/cache/current.webp',
    );
    final queued = songFromDesktopRemoteTrack(
      second, artworkServerId: 42,
    );
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
  });

  test('paired artwork server is invalidated on remote target changes', () {
    const initial = LokalRemoteControllerState();
    final paired = initial.copyWith(artworkServerId: 19);
    expect(paired.artworkServerId, 19);
    expect(paired.copyWith(remoteArtworkPath: '/cache/current.webp').artworkServerId, 19);
    expect(paired.copyWith(clearArtworkServer: true).artworkServerId, isNull);
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerProvider.overrideWith(_RemotePlayer.new),
        lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
      ],
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
        home: DesktopRemoteFullPlayer(onClose: () => closes++),
      ),
    ));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('desktop-cover:desktop:desktop-id-123')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop full player displays remote track rather than the last mobile song',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _RemotePlayer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerProvider.overrideWith(() => player),
        lokalRemoteControllerProvider.overrideWith(_RemoteController.new),
      ],
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.themes[LokalThemeId.dark]!),
        home: DesktopRemoteFullPlayer(onClose: () {}),
      ),
    ));
    await tester.pump();

    expect(find.text('Desktop Recording'), findsOneWidget);
    expect(find.text('Desktop Performer'), findsOneWidget);
    expect(find.text('ExpertBook'), findsOneWidget);
    expect(find.text('Last Mobile Song'), findsNothing);
    expect(find.byType(PlayerTransportControls), findsOneWidget);
    final controls = tester.widget<PlayerTransportControls>(
        find.byType(PlayerTransportControls));
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
  });
}
