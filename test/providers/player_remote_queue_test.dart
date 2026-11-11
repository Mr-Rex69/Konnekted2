import 'dart:convert';

import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/services/lokal_remote_credentials_store.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _credentials = LokalRemoteCredentials(
  origin: Uri.parse('http://desktop:3421'),
  desktopId: 'paired-desktop',
  remoteToken: 'test-token',
);

class _Credentials extends SecureLokalRemoteCredentialsStore {
  @override
  Future<LokalRemoteCredentials?> read() async => _credentials;
}

class _Remote extends LokalRemoteController {
  final commands = <(String, Object?)>[];

  @override
  LokalRemoteControllerState build() => LokalRemoteControllerState(
    config: LokalRemoteConfig.fromCredentials(_credentials),
    status: LokalRemoteConnectionStatus.connected,
    controlsDesktop: true,
    artworkServerId: 7,
  );

  @override
  Future<void> sendRawCommand(String action, [Object? value]) async {
    commands.add((action, value));
  }
}

class _Library extends SongsNotifier {
  _Library(this.songs);
  final List<Song> songs;

  @override
  Future<SongsState> build() async => SongsState(songs: songs);
}

// Exercise the real queue routing without starting the phone audio engine.
// Falling through to local addToQueue fails because _service is uninitialized.
class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const reference = Song(
    id: 'pending:playlist:saved',
    title: 'Shared recording',
    artist: 'Artist',
    album: 'Album',
    duration: Duration(seconds: 180),
    fileType: 'FLAC',
    sourcePackage: Song.pendingSourcePackage,
  );
  final local = Song(
    id: 'rescanned-phone-id',
    title: reference.title,
    artist: reference.artist,
    album: reference.album,
    duration: reference.duration,
    fileType: reference.fileType,
    filePath: '/music/shared.flac',
  );
  final pc = local.copyWith(
    id: 'desktop-row',
    filePath: 'lokal://7/pc-id',
    sourceType: 'lokal',
    remoteId: 'pc-id',
    remoteServerId: 7,
  );

  for (final synced in [true, false]) {
    test(
      'playlist add routes to desktop with synced library=$synced',
      () async {
        final remote = _Remote();
        var lookups = 0;
        final service = LokalRemoteService(
          client: MockClient((request) async {
            expect(synced, isFalse);
            expect(request.url.path, '/api/remote/library/tracks');
            expect(request.headers['x-remote-token'], 'test-token');
            lookups++;
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'pc-id',
                    'title': reference.title,
                    'artist': reference.artist,
                    'album': reference.album,
                    'duration': 180,
                  },
                ],
                'hasMore': false,
              }),
              200,
            );
          }),
        );
        final container = ProviderContainer(
          overrides: [
            playerProvider.overrideWith(_Player.new),
            songsProvider.overrideWith(() => _Library([local, if (synced) pc])),
            lokalRemoteControllerProvider.overrideWith(() => remote),
            lokalRemoteCredentialsStoreProvider.overrideWithValue(
              _Credentials(),
            ),
            lokalRemoteServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(service.close);

        await container.read(playerProvider.notifier).addToQueue(reference);

        expect(remote.commands.single.$1, 'queueTracks');
        expect(remote.commands.single.$2, {
          'trackIds': ['pc-id'],
        });
        expect(lookups, synced ? 0 : 1);
      },
    );
  }
}
