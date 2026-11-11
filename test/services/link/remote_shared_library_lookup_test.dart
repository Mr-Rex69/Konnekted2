import 'dart:convert';

import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/link/remote_playback_target.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Song _phone(String title, {String album = 'Album', int seconds = 180}) =>
    Song(
      id: 'phone-1',
      title: title,
      artist: 'Singer',
      album: album,
      duration: Duration(seconds: seconds),
      fileType: 'FLAC',
      filePath: '/storage/emulated/0/Music/track.flac',
    );

Map<String, dynamic> _desktop(String id, String title, {
  String artist = 'Singer',
  String album = 'Album',
  int seconds = 180,
}) => {
  'id': id,
  'title': title,
  'artist': artist,
  'album': album,
  'duration': seconds,
  'fileType': 'flac',
};

void main() {
  test('playlist metadata resolves a desktop copy without a phone file path', () {
    const reference = Song(
      id: 'pending:playlist:saved',
      title: 'Shared song',
      artist: 'Singer',
      album: 'Album',
      duration: Duration(seconds: 180),
      fileType: 'FLAC',
      sourcePackage: Song.pendingSourcePackage,
    );
    final candidates = [
      _desktop('wrong-album', 'Shared song', album: 'Another album'),
      _desktop('wrong-artist', 'Shared song', artist: 'Other singer'),
      _desktop('different-edit', 'Shared song', seconds: 190),
      _desktop('pc-123', 'Shared song'),
    ];
    expect(matchedDesktopIdFromCandidates(
      selected: reference,
      candidates: candidates,
      desktopServerId: 5,
    ), 'pc-123');
    expect(matchedDesktopIdFromCandidates(
      selected: reference,
      candidates: [...candidates, _desktop('pc-second', 'Shared song')],
      desktopServerId: 5,
    ), isNull);
    expect(matchedDesktopIdFromCandidates(
      selected: reference.copyWith(duration: Duration.zero),
      candidates: candidates,
      desktopServerId: 5,
    ), isNull);
  });

  test('legacy overlap resolves an exact desktop recording', () {
    final match = matchedDesktopIdFromCandidates(
      selected: _phone('Shared song'),
      candidates: [
        _desktop('wrong-album', 'Shared song', album: 'Another album'),
        _desktop('wrong-artist', 'Shared song', artist: 'Other singer'),
        _desktop('pc-123', 'Shared song'),
        _desktop('different-edit', 'Shared song', seconds: 190),
      ],
      desktopServerId: 5,
    );
    expect(match, 'pc-123');
  });

  test('shared lookup rejects ambiguous desktop takes and phone-only songs', () {
    final overlapping = [
      _desktop('pc-first', 'Shared song'),
      _desktop('pc-second', 'Shared song', seconds: 181),
    ];
    expect(matchedDesktopIdFromCandidates(
      selected: _phone('Shared song'),
      candidates: overlapping,
      desktopServerId: 5,
    ), isNull);
    expect(matchedDesktopIdFromCandidates(
      selected: _phone('Not on PC'),
      candidates: overlapping,
      desktopServerId: 5,
    ), isNull);
  });

  test('authenticated paginated desktop title lookup retains full results',
      () async {
    final offsets = <String?>[];
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/remote/library/tracks');
      expect(request.url.queryParameters['q'], 'Shared song');
      expect(request.headers['x-remote-token'], 'pair_token');
      offsets.add(request.url.queryParameters['offset']);
      return http.Response(jsonEncode({
        'items': [
          _desktop(request.url.queryParameters['offset'] == '0'
              ? 'wrong-album'
              : 'pc-123', 'Shared song',
              album: request.url.queryParameters['offset'] == '0'
                  ? 'Another album' : 'Album'),
        ],
        'hasMore': request.url.queryParameters['offset'] == '0',
      }), 200);
    });
    final service = LokalRemoteService(client: client);
    addTearDown(service.close);
    final credentials = LokalRemoteCredentials(
      origin: Uri.parse('http://192.168.1.20:3421'),
      remoteToken: 'pair_token',
      desktopId: 'paired-desktop',
    );
    final candidates =
        await service.findDesktopTrackCandidates(credentials, 'Shared song');
    expect(offsets, ['0', '250']);
    expect(matchedDesktopIdFromCandidates(
      selected: _phone('Shared song'),
      candidates: candidates,
      desktopServerId: 5,
    ), 'pc-123');
  });

  test('desktop library command also supports HTTP when socket is offline',
      () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/remote/command');
      expect(request.headers['x-remote-token'], 'pair_token');
      sent = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final service = LokalRemoteService(client: client);
    addTearDown(service.close);
    final credentials = LokalRemoteCredentials(
      origin: Uri.parse('http://192.168.1.20:3421'),
      remoteToken: 'pair_token',
    );
    await service.sendLibraryCommand(credentials, 'playLibraryTrack', {
      'trackId': 'pc-123',
      'trackIds': ['pc-123'],
    });
    expect(sent, {
      'action': 'playLibraryTrack',
      'value': {
        'trackId': 'pc-123',
        'trackIds': ['pc-123'],
      },
    });
  });
}
