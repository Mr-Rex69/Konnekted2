import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Phone extends Fake implements PlayerService {
  @override
  Future<bool> Function(Song)? linkedDesktopAvailable;
  @override
  bool get isCasting => false;
  @override
  final currentSongNotifier = ValueNotifier<Song?>(null);
  @override
  final isPlayingNotifier = ValueNotifier(false);
  @override
  final isBufferingNotifier = ValueNotifier(false);
  @override
  final positionNotifier = ValueNotifier(Duration.zero);
  @override
  final durationNotifier = ValueNotifier(Duration.zero);
  @override
  final bufferedPositionNotifier = ValueNotifier(Duration.zero);
  @override
  final isShuffleNotifier = ValueNotifier(true);
  @override
  final shuffleModeNotifier = ValueNotifier(ShuffleMode.categories);
  @override
  final loopModeNotifier = ValueNotifier(LoopMode.one);
  @override
  final playbackSpeedNotifier = ValueNotifier(1.0);
  @override
  final sleepTimerRemainingNotifier = ValueNotifier<Duration?>(null);
  @override
  final queueNotifier = ValueNotifier(<Song>[]);
  @override
  final upNextNotifier = ValueNotifier(<Song>[]);
  @override
  final autoplayQueueNotifier = ValueNotifier(<Song>[]);
  @override
  final currentIndexNotifier = ValueNotifier(-1);
  @override
  List<Song> get playlist => const [];
}

LokalRemoteSnapshot _snapshot(bool shuffle, String repeat) =>
    LokalRemoteSnapshot(
      connected: true,
      isPlaying: false,
      progress: 0,
      duration: 0,
      volume: .5,
      repeat: repeat,
      shuffle: shuffle,
      currentTrack: null,
      updatedAt: 1,
    );

class _Remote extends LokalRemoteController {
  final commands = <(String, Object?)>[];
  @override
  LokalRemoteControllerState build() => LokalRemoteControllerState(
    controlsDesktop: true,
    status: LokalRemoteConnectionStatus.connected,
    snapshot: _snapshot(false, 'none'),
  );

  void publish({
    bool shuffle = false,
    String repeat = 'none',
    bool phone = false,
  }) {
    state = state.copyWith(
      controlsDesktop: !phone,
      snapshot: _snapshot(shuffle, repeat),
    );
  }

  void clearSnapshot() => state = state.copyWith(clearSnapshot: true);

  @override
  Future<void> sendRawCommand(String action, [Object? value]) async {
    commands.add((action, value));
  }
}

void main() {
  test('remote modes initialize immediately, track snapshots and restore phone state', () async {
    final phone = _Phone();
    final remote = _Remote();
    final container = ProviderContainer(
      overrides: [
        playerServiceProvider.overrideWithValue(phone),
        lokalRemoteControllerProvider.overrideWith(() => remote),
      ],
    );
    addTearDown(container.dispose);
    // The desktop is already selected before the player provider is created.
    final initial = container.read(playerProvider);
    expect(initial.isShuffle, isFalse);
    expect(initial.shuffleMode, ShuffleMode.off);
    expect(initial.loopMode, LoopMode.off);
    final player = container.read(playerProvider.notifier);
    await player.toggleShuffle();
    player.toggleLoopMode();
    await Future<void>.value();
    expect(remote.commands, [('setShuffle', true), ('setRepeat', 'all')]);

    for (final (repeat, mode) in [
      ('all', LoopMode.all),
      ('one', LoopMode.one),
      ('none', LoopMode.off),
    ]) {
      remote.publish(shuffle: true, repeat: repeat);
      expect(container.read(playerProvider).isShuffle, isTrue);
      expect(container.read(playerProvider).shuffleMode, ShuffleMode.songs);
      expect(container.read(playerProvider).loopMode, mode);
    }
    phone.isShuffleNotifier.value = false;
    phone.loopModeNotifier.value = LoopMode.all;
    expect(container.read(playerProvider).isShuffle, isTrue);
    expect(container.read(playerProvider).loopMode, LoopMode.off);

    remote.clearSnapshot();
    expect(container.read(playerProvider).isShuffle, isFalse);
    expect(container.read(playerProvider).loopMode, LoopMode.off);
    remote.publish(phone: true);
    expect(container.read(playerProvider).isShuffle, isFalse);
    expect(container.read(playerProvider).loopMode, LoopMode.all);
  });
}
