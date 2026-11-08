import 'package:flick/features/discovery/spotify_discovery.dart';

import 'dart:convert';

import 'package:flick/services/motion_art/spotify_canvas_service.dart';

import 'package:flick/features/spotify/spotify_web_api.dart';
import 'package:flick/features/spotify/spotify_models.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/features/spotify/spotify_oauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store implements SpotifyTokenStore {
  SpotifyTokens? tokens = SpotifyTokens(
    accessToken: 'test-access',
    refreshToken: null,
    sessionCookie: 'test-cookie',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
  @override
  Future<SpotifyTokens?> readTokens() async => tokens;
  @override
  Future<void> writeTokens(SpotifyTokens value) async => tokens = value;
  @override
  Future<void> clearTokens() async => tokens = null;
}

const uri = 'spotify:track:0123456789012345678901';
Map<String, Object?> track(String name) => {
  '__typename': 'Track',
  'uri': uri,
  'name': name,
  'artists': {
    'items': [
      {
        'profile': {'name': 'Artist'},
      },
    ],
  },
  'albumOfTrack': {
    'name': 'Album',
    'coverArt': {
      'sources': [
        {'url': 'https://i.scdn.co/image/id', 'width': 640},
      ],
    },
  },
  'trackDuration': {'totalMilliseconds': 180000},
};
void main() {
  test('cookie Discovery parses desktop Pathfinder Home mixes, playlist tracks and likes', () async {
    final store = _Store();
    final operations = <String>[];
    var failTracks = false;
    final api = SpotifyWebApi(
      store: store,
      oauth: SpotifyOAuthService(tokenStore: store),
      client: MockClient((request) async {
        expect(request.url.host, 'api-partner.spotify.com');
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer test-access');
        expect(request.headers.containsKey('cookie'), isFalse);
        final json = jsonDecode(request.body) as Map;
        final op = json['operationName'] as String;
        operations.add(op);
        if (failTracks && op != 'home') return http.Response('{}', 500);
        final data = switch (op) {
          'home' => {
            'home': {
              'sectionContainer': {
                'sections': {
                  'items': [
                    {
                      'sectionItems': {
                        'items': [
                          {
                            'content': {
                              '__typename': 'PlaylistResponseWrapper',
                              'data': {
                                '__typename': 'Playlist',
                                'uri':
                                    'spotify:playlist:37i9dQZF1E000000000001',
                                'name': 'Daily Mix',
                                'ownerV2': {
                                  'data': {'name': 'Spotify'},
                                },
                                'images': {
                                  'items': [
                                    {
                                      'sources': [
                                        {
                                          'url': 'https://i.scdn.co/image/mix',
                                          'width': 640,
                                        },
                                      ],
                                    },
                                  ],
                                },
                              },
                            },
                          },
                          {
                            'content': {
                              'data': {
                                '__typename': 'Playlist',
                                'uri':
                                    'spotify:playlist:aaaaaaaaaaaaaaaaaaaaaa',
                                'name': 'Other person',
                                'ownerV2': {
                                  'data': {'name': 'Someone'},
                                },
                              },
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
          'fetchPlaylist' => {
            'playlistV2': {
              '__typename': 'Playlist',
              'content': {
                'items': [
                  {
                    'itemV2': {'data': track('Playlist song')},
                  },
                ],
              },
            },
          },
          'fetchLibraryTracks' => {
            'me': {
              'library': {
                'tracks': {
                  'items': [
                    {
                      'addedAt': {'isoString': '2026-10-21T00:00:00Z'},
                      'track': {
                        '_uri': uri,
                        'data': track('Liked song')..remove('uri'),
                      },
                    },
                  ],
                },
              },
            },
          },
          _ => throw StateError(op),
        };
        return http.Response(jsonEncode({'data': data}), 200);
      }),
    );
    addTearDown(api.close);
    final mixes = await api.getPlaylists();
    expect(mixes.map((m) => m.name), ['Daily Mix']);
    final songs = await api.getPlaylistTracks(mixes.single.id);
    expect(songs.single.title, 'Playlist song');
    expect(songs.single.imageUrl, 'https://i.scdn.co/image/id');
    expect((await api.getLikedSongs()).single.title, 'Liked song');
    expect(operations, ['home', 'fetchPlaylist', 'fetchLibraryTracks']);
    final discovery = await loadSpotifyWebDiscovery(api);
    expect(discovery.mixes.single.title, 'Daily Mix');
    expect(discovery.mixes.single.author, 'Spotify');
    expect(discovery.mixes.single.artworkUrl, 'https://i.scdn.co/image/mix');
    expect(
      (await loadSpotifyWebMix(api, discovery.mixes.single.id)).single.title,
      'Playlist song',
    );
    failTracks = true;
    final partial = await loadSpotifyWebDiscovery(api);
    expect(partial.mixes.single.title, 'Daily Mix');
    expect(partial.isEmpty, isFalse);
    expect(partial.warnings, isNotEmpty);
  });
  test(
    'Canvas uses Pathfinder when REST search rejects a web cookie session',
    () async {
      final store = _Store();
      store.tokens = store.tokens!.copyWith(
        queryHashes: {'searchTracks': 'c' * 64, 'canvas': 'd' * 64},
      );
      final calls = <String>[];
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-access');
        expect(request.headers.containsKey('cookie'), isFalse);
        if (request.url.host == 'api.spotify.com')
          return http.Response('{}', 403);
        final body = jsonDecode(request.body) as Map;
        final op = body['operationName'];
        expect(
          body['extensions']['persistedQuery']['sha256Hash'],
          op == 'searchTracks' ? 'c' * 64 : 'd' * 64,
        );
        calls.add('$op');
        expect(request.method, 'POST');
        expect(request.url.path, '/pathfinder/v2/query');
        return http.Response(
          jsonEncode({
            'data': op == 'searchTracks'
                ? {
                    'searchV2': {
                      'tracksV2': {
                        'items': [
                          {
                            'item': {'data': track('Song')},
                          },
                        ],
                      },
                    },
                  }
                : {
                    'trackUnion': {
                      'canvas': {'url': 'https://video.scdn.co/canvas.mp4'},
                    },
                  },
          }),
          200,
        );
      });
      addTearDown(client.close);
      final canvas = SpotifyCanvasService(
        client: client,
        store: store,
        oauth: SpotifyOAuthService(tokenStore: store),
      );
      expect(
        await canvas.lookup(title: 'Song', artist: 'Artist', album: 'Album'),
        'https://video.scdn.co/canvas.mp4',
      );
      expect(calls, ['searchTracks', 'canvas']);
    },
  );

  test('cookie playlists load more than 1000 songs, even on short pages', () async {
    final store = _Store();
    final offsets = <int>[];
    final api = SpotifyWebApi(
      store: store,
      oauth: SpotifyOAuthService(tokenStore: store),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['operationName'], 'fetchPlaylist');
        final vars = body['variables'] as Map;
        final offset = vars['offset'] as int;
        offsets.add(offset);
        const total = 1234;
        final remaining = total - offset;
        final length = remaining < 40 ? remaining : 40;
        final items = [
          for (var i = 0; i < length; i++)
            {
              'itemV2': {
                'data': {
                  ...track('Song ${offset + i}'),
                  'uri': 'spotify:track:${(offset + i).toString().padLeft(22, '0')}',
                },
              },
            },
        ];
        return http.Response(
          jsonEncode({
            'data': {
              'playlistV2': {
                '__typename': 'Playlist',
                'content': {'totalCount': total, 'items': items},
              },
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final songs = await api.getPlaylistTracks('aaaaaaaaaaaaaaaaaaaaaa');
    expect(songs.length, 1234);
    expect(songs.first.title, 'Song 0');
    expect(songs.last.title, 'Song 1233');
    expect(offsets.first, 0);
    expect(offsets[1], 40);
    expect(offsets.last, 1200);
  });

  test('cookie playlist does not accept an incomplete page as a full list', () async {
    final store = _Store();
    final api = SpotifyWebApi(
      store: store,
      oauth: SpotifyOAuthService(tokenStore: store),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final offset = (body['variables'] as Map)['offset'] as int;
        return http.Response(
          jsonEncode({
            'data': {
              'playlistV2': {
                '__typename': 'Playlist',
                'content': {
                  'totalCount': 125,
                  'items': offset == 0
                      ? [
                          for (var i = 0; i < 100; i++)
                            {'itemV2': {'data': track('Song $i')}},
                        ]
                      : <Object>[],
                },
              },
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.getPlaylistTracks('aaaaaaaaaaaaaaaaaaaaaa'),
      throwsA(predicate((e) => e.toString().contains('before loading all'))),
    );
  });

  test('incremental likes stop at an old entry', () async {
    final store = _Store();
    var requests = 0;
    final api = SpotifyWebApi(
      store: store,
      oauth: SpotifyOAuthService(tokenStore: store),
      likesSince: DateTime.utc(2026, 10, 20),
      client: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'data': {
              'me': {
                'library': {
                  'tracks': {
                    'items': [
                      {
                        'addedAt': {'isoString': '2026-10-21T00:00:00Z'},
                        'track': {'data': track('New')},
                      },
                      {
                        'addedAt': {'isoString': '2026-10-19T00:00:00Z'},
                        'track': {'data': track('Old')},
                      },
                    ],
                  },
                },
              },
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    expect((await api.getLikedSongs()).map((s) => s.title), ['New']);
    expect(requests, 1);
  });
}
