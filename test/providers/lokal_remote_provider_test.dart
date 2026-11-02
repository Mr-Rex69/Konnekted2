import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/services/lokal_remote_credentials_store.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _Store implements LokalRemoteCredentialsStore {
  LokalRemoteCredentials? value;

  @override
  Future<LokalRemoteCredentials?> read() async => value;

  @override
  Future<void> write(LokalRemoteCredentials credentials) async =>
      value = credentials;

  @override
  Future<void> clear() async => value = null;
}

class _Service extends LokalRemoteService {
  _Service(this.responses);

  final List<Object> responses;
  final commands = <(LokalRemoteAction, double?)>[];

  @override
  Future<LokalRemoteSnapshot> fetchState(
    LokalRemoteCredentials credentials,
  ) async {
    final response = responses.removeAt(0);
    if (response is! LokalRemoteSnapshot) throw response;
    return response;
  }

  @override
  Future<void> sendCommand(
    LokalRemoteCredentials credentials,
    LokalRemoteAction action, {
    double? value,
  }) async {
    commands.add((action, value));
  }
}

final _credentials = LokalRemoteCredentials(
  origin: Uri.parse('http://desktop'),
  remoteToken: 'token',
);

LokalRemoteSnapshot _snapshot({
  required int updatedAt,
  String title = 'Track',
}) => LokalRemoteSnapshot(
  connected: true,
  isPlaying: true,
  progress: 2,
  duration: 10,
  volume: .7,
  repeat: 'none',
  shuffle: false,
  currentTrack: LokalRemoteTrack(title: title, artist: 'Artist'),
  updatedAt: updatedAt,
);

ProviderContainer _container(_Store store, _Service service) =>
    ProviderContainer(
      overrides: [
        lokalRemoteCredentialsStoreProvider.overrideWithValue(store),
        lokalRemoteServiceProvider.overrideWithValue(service),
      ],
    );

void main() {
  test('Android notification takes the new desktop recording duration, not stale player duration', () {
    const oldRecording = LokalRemoteTrack(
      id: 'one', title: 'One', artist: 'Artist', duration: 237,
    );
    const newRecording = LokalRemoteTrack(
      id: 'two', title: 'Two', artist: 'Artist', duration: 174,
    );
    LokalRemoteSnapshot state(LokalRemoteTrack track, double duration) =>
        LokalRemoteSnapshot(
          connected: true,
          isPlaying: true,
          progress: 0,
          duration: duration,
          volume: 1,
          repeat: 'none',
          shuffle: false,
          currentTrack: track,
          updatedAt: 20,
        );

    expect(desktopNotificationDuration(state(oldRecording, 237)),
        const Duration(seconds: 237));
    // Mobile next can deliver new title before desktop top-level duration
    // updates. Its currentTrack metadata already knows the recording length.
    expect(desktopNotificationDuration(state(newRecording, 237)),
        const Duration(seconds: 174));
    expect(desktopNotificationDuration(state(newRecording, 174)),
        const Duration(seconds: 174));
    // Older/online desktop tracks may omit metadata duration; later player
    // duration snapshots must still be able to correct the notification.
    const missingDuration = LokalRemoteTrack(
      id: 'three', title: 'Three', artist: 'Artist',
    );
    expect(desktopNotificationDuration(state(missingDuration, 237)),
        const Duration(seconds: 237));
    expect(desktopNotificationDuration(state(missingDuration, 189)),
        const Duration(seconds: 189));
  });

  bool idleLink({
    Duration idleFor = const Duration(minutes: 4),
    bool controlsDesktop = false,
    bool desktopPlaying = false,
    bool phonePlaying = false,
    bool statsSyncBusy = false,
    bool fileCopyBusy = false,
    bool outboxBusy = false,
  }) => shouldSuspendIdleDesktopLink(
    idleFor: idleFor,
    controlsDesktop: controlsDesktop,
    desktopPlaying: desktopPlaying,
    phonePlaying: phonePlaying,
    statsSyncBusy: statsSyncBusy,
    fileCopyBusy: fileCopyBusy,
    outboxBusy: outboxBusy,
  );

  test('desktop remote control stays connected past three minutes of no phone playback', () {
    expect(idleLink(controlsDesktop: true), isFalse);
    expect(idleLink(
      controlsDesktop: true,
      idleFor: const Duration(hours: 2),
    ), isFalse);
    // Remote control remains active even if the desktop is paused.
    expect(idleLink(controlsDesktop: true, desktopPlaying: false), isFalse);
    // A desktop playing music must not be mistaken for an idle phone link.
    expect(idleLink(desktopPlaying: true), isFalse);
  });

  test('passive desktop link still suspends after three minutes', () {
    expect(idleLink(idleFor: const Duration(minutes: 2)), isFalse);
    expect(idleLink(idleFor: const Duration(minutes: 3)), isFalse);
    expect(idleLink(idleFor: const Duration(minutes: 4)), isTrue);
    expect(idleLink(phonePlaying: true), isFalse);
    expect(idleLink(statsSyncBusy: true), isFalse);
    expect(idleLink(fileCopyBusy: true), isFalse);
    expect(idleLink(outboxBusy: true), isFalse);
  });

  test(
    'reconnect keeps the last good state through a transient failure',
    () async {
      final store = _Store()..value = _credentials;
      final service = _Service([
        _snapshot(updatedAt: 1),
        const LokalRemoteNetworkException('fixture offline'),
        _snapshot(updatedAt: 2, title: 'Recovered'),
      ]);
      final container = _container(store, service);
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);

      await controller.connect();
      expect(
        container.read(lokalRemoteControllerProvider).status,
        LokalRemoteConnectionStatus.connected,
      );
      expect(
        container
            .read(lokalRemoteControllerProvider)
            .snapshot!
            .currentTrack!
            .title,
        'Track',
      );

      await controller.refresh();
      final offline = container.read(lokalRemoteControllerProvider);
      expect(offline.status, LokalRemoteConnectionStatus.offline);
      expect(offline.snapshot!.currentTrack!.title, 'Track');

      await controller.connect();
      final recovered = container.read(lokalRemoteControllerProvider);
      expect(recovered.status, LokalRemoteConnectionStatus.connected);
      expect(recovered.snapshot!.currentTrack!.title, 'Recovered');
    },
  );

  test('older desktop timestamps cannot overwrite a newer snapshot', () async {
    final store = _Store();
    final service = _Service([
      _snapshot(updatedAt: 20, title: 'New'),
      _snapshot(updatedAt: 10, title: 'Old'),
    ]);
    final container = _container(store, service);
    addTearDown(container.dispose);
    final controller = container.read(lokalRemoteControllerProvider.notifier);
    await controller.saveConfiguration(
      origin: 'http://desktop:3421/remote',
      remoteToken: 'token',
      apiKey: '',
    );
    await controller.connect();
    await controller.refresh();

    expect(
      container
          .read(lokalRemoteControllerProvider)
          .snapshot!
          .currentTrack!
          .title,
      'New',
    );
  });

  test(
    'commands are delivered through the remote service, not local playback',
    () async {
      final store = _Store()..value = _credentials;
      final service = _Service([
        _snapshot(updatedAt: 1),
        _snapshot(updatedAt: 2),
      ]);
      final container = _container(store, service);
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);
      await controller.connect();
      await controller.sendCommand(LokalRemoteAction.volume, value: .25);

      expect(service.commands, [(LokalRemoteAction.volume, .25)]);
    },
  );
}
