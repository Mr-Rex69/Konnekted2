import 'package:flick/models/song.dart';
import 'package:flick/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remote owner reconciles MediaSession duration without toggling remote mode', () async {
    const channel = MethodChannel('com.mossapps.flick/player');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final remoteVolumes = <double>[];
    var localVolumeCalls = 0;
    final service = NotificationService();
    service.init(
      onTogglePlayPause: () {},
      onPlay: () {},
      onPause: () {},
      onNext: () {},
      onPrevious: () {},
      onStop: () {},
      onSeek: (_) {},
      onToggleShuffle: () {},
      onToggleFavorite: () {},
      onSetCastVolume: (_) => localVolumeCalls++,
    );
    final owner = MediaNotificationOwner(
      onTogglePlayPause: () {},
      onPlay: () {},
      onPause: () {},
      onStop: () {},
      onSetVolume: remoteVolumes.add,
    );
    addTearDown(() => service.release(owner));

    const firstSong = Song(
      id: 'desktop:one',
      title: 'One',
      artist: 'Artist',
      duration: Duration(seconds: 232),
      fileType: 'FLAC',
    );
    const secondSong = Song(
      id: 'desktop:two',
      title: 'Two',
      artist: 'Artist',
      duration: Duration(seconds: 181),
      fileType: 'FLAC',
    );
    await service.showFor(
      owner,
      song: firstSong,
      isPlaying: true,
      isLive: false,
      isRemotePlayback: true,
      remoteVolume: .7,
      outputName: 'PC',
      position: const Duration(seconds: 34),
    );
    await service.showFor(
      owner,
      song: secondSong,
      isPlaying: true,
      isLive: false,
      position: Duration.zero,
    );
    await service.showFor(
      owner,
      song: secondSong.copyWith(albumArt: '/cache/pc-cover.png'),
      isPlaying: true,
      isLive: false,
      isRemotePlayback: true,
      position: const Duration(seconds: 9),
    );
    expect(
      (calls.last.arguments as Map)['albumArtPath'],
      '/cache/pc-cover.png',
    );
    expect((calls.last.arguments as Map)['position'], 9000);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('setCastVolume', {'volume': .4}),
          ),
          (_) {},
        );
    expect(remoteVolumes, [.4]);
    expect(localVolumeCalls, 0);
    final shows = calls.where((c) => c.method == 'showNotification').toList();
    expect((shows[0].arguments as Map)['duration'], 232000);
    expect((shows[0].arguments as Map)['isRemotePlayback'], true);
    expect((shows[0].arguments as Map)['castVolume'], 70);
    expect((shows[1].arguments as Map)['duration'], 181000);
    expect((shows[1].arguments as Map)['title'], 'Two');

    // Later playback updates must include duration: this used to publish
    // only position/isPlaying, leaving Android's seekbar on the old track.
    await service.updateFor(
      owner,
      position: const Duration(seconds: 14),
      isPlaying: true,
      duration: const Duration(seconds: 175),
    );
    final update = calls.last;
    expect(update.method, 'updateNotification');
    expect((update.arguments as Map)['duration'], 175000);
    expect((update.arguments as Map)['position'], 14000);
    expect((update.arguments as Map)['isPlaying'], isTrue);
    expect(service.isClaimed, isTrue);
    service.release(owner);
    await service.updateNotification(song: firstSong, isPlaying: true);
    expect((calls.last.arguments as Map)['isRemotePlayback'], false);
  });
}
