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
