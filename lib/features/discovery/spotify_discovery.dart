import 'package:flick/features/spotify/spotify_web_api.dart';
import 'package:flick/features/spotify/spotify_models.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/spotify/spotify_api.dart';
import 'package:flick/features/spotify/spotify_http.dart';
import 'package:flick/features/spotify/spotify_oauth.dart';
import 'package:flick/features/spotify/spotify_storage.dart';

/// The account shelves Spotify exposes for the signed-in listener. Spotify
/// records are still discovery metadata; playback goes through the existing
/// local-library/YouTube Music/addon resolver.
class SpotifyDiscoveryData {
  const SpotifyDiscoveryData({
    required this.account,
    required this.quickPicks,
    required this.recentlyPlayed,
    required this.likedSongs,
    required this.artists,
    required this.albums,
    required this.freshFinds,
    this.warnings = const [],
    this.mixes = const [],
  });

  final String account;
  final List<LokalDiscoveryTrack> quickPicks;
  final List<LokalDiscoveryTrack> recentlyPlayed;
  final List<LokalDiscoveryTrack> likedSongs;
  final List<LokalDiscoveryArtist> artists;
  final List<LokalDiscoveryAlbum> albums;
  final List<LokalDiscoveryTrack> freshFinds;
  final List<String> warnings;
  final List<LokalDiscoveryMix> mixes;

  bool get isEmpty =>
      mixes.isEmpty &&
      quickPicks.isEmpty &&
      recentlyPlayed.isEmpty &&
      likedSongs.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty &&
      freshFinds.isEmpty;
}

/// Settings and auth status are kept in the snapshot so Home can show a clear
/// opt-in/signed-out state without probing Spotify before the user selects it.
class SpotifyDiscoverySnapshot {
  const SpotifyDiscoverySnapshot({
    required this.enabled,
    required this.connected,
    this.data,
    this.error,
  });

  final bool enabled;
  final bool connected;
  final SpotifyDiscoveryData? data;
  final String? error;
}

Future<SpotifyDiscoverySnapshot> loadSpotifyDiscoverySnapshot({
  required SpotifySettingsStore settings,
  required SpotifyOAuthService oauth,
  required SpotifyApi api,
}) async {
  final enabled = await settings.loadDiscoveryEnabled();
  if (!enabled) {
    return const SpotifyDiscoverySnapshot(enabled: false, connected: false);
  }
  final connected = await oauth.isConnected;
  if (!connected) {
    return const SpotifyDiscoverySnapshot(enabled: true, connected: false);
  }
  final web = SpotifyWebApi(store: settings.tokenStore, oauth: oauth);
  try {
    return SpotifyDiscoverySnapshot(
      enabled: true,
      connected: true,
      data: await loadSpotifyWebDiscovery(web),
    );
  } catch (error) {
    return SpotifyDiscoverySnapshot(
      enabled: true,
      connected: true,
      error: spotifyDiscoveryError(error),
    );
  } finally {
    web.close();
  }
}

String spotifyDiscoveryError(Object error) => error is SpotifyApiException
    ? error.message
    : 'Spotify Discovery could not be loaded. Try again later.';

Future<SpotifyDiscoveryData> loadSpotifyDiscovery({
  required SpotifyApi api,
  SpotifyCancellation? cancellation,
}) async {
  final warnings = <String>[];

  Future<T?> optional<T>(String shelf, Future<T> Function() load) async {
    try {
      cancellation?.check();
      return await load();
    } catch (error) {
      cancellation?.check();
      warnings.add('$shelf: ${spotifyDiscoveryError(error)}');
      return null;
    }
  }

  final account = await optional('Profile', () async {
    final json = await api.getJson(
      _endpoint('/v1/me'),
      cancellation: cancellation,
    );
    return _text(json['display_name']) ?? _text(json['id']) ?? 'Spotify';
  });
  final topTracks = await optional('Quick Picks', () async {
    final json = await api.getJson(
      _endpoint('/v1/me/top/tracks', {
        'time_range': 'short_term',
        'limit': '30',
      }),
      cancellation: cancellation,
    );
    return _tracks(json['items']);
  });
  final recentlyPlayed = await optional('Recently played', () async {
    final json = await api.getJson(
      _endpoint('/v1/me/player/recently-played', {'limit': '30'}),
      cancellation: cancellation,
    );
    return _tracks(json['items'], playedAt: true);
  });
  final likedSongs = await optional('Liked Songs', () async {
    final json = await api.getJson(
      _endpoint('/v1/me/tracks', {'limit': '30', 'offset': '0'}),
      cancellation: cancellation,
    );
    return _tracks(json['items']);
  });
  final artists = await optional('Top artists', () async {
    final json = await api.getJson(
      _endpoint('/v1/me/top/artists', {
        'time_range': 'medium_term',
        'limit': '20',
      }),
      cancellation: cancellation,
    );
    return _artists(json['items']);
  });

  final artistAlbums = <LokalDiscoveryAlbum>[];
  final artistSeeds = <String>[];
  for (final artist in artists ?? const <LokalDiscoveryArtist>[]) {
    final id = _idFromSpotifyUrl(artist.url);
    if (id != null) artistSeeds.add(id);
  }
  for (final artistId in artistSeeds.take(8)) {
    final albums = await optional('Artist albums', () async {
      final json = await api.getJson(
        _endpoint('/v1/artists/$artistId/albums', {
          'include_groups': 'album,single',
          'limit': '5',
        }),
        cancellation: cancellation,
      );
      return _albums(json['items']);
    });
    if (albums != null) artistAlbums.addAll(albums);
  }
  final uniqueAlbums = <String, LokalDiscoveryAlbum>{
    for (final album in artistAlbums)
      '${album.artist}\u0000${album.title}': album,
  };

  final freshFinds = await optional('Fresh Finds', () async {
    if (artistSeeds.isEmpty) return const <LokalDiscoveryTrack>[];
    final json = await api.getJson(
      _endpoint('/v1/recommendations', {
        'seed_artists': artistSeeds.take(5).join(','),
        'limit': '30',
      }),
      cancellation: cancellation,
    );
    final heard = {
      for (final track in [...?topTracks, ...?recentlyPlayed, ...?likedSongs])
        track.key,
    };
    return _tracks(json['tracks'])
        .where((track) => !heard.contains(track.key))
        .toList();
  });

  final data = SpotifyDiscoveryData(
    account: account ?? 'Spotify',
    quickPicks: topTracks ?? const [],
    recentlyPlayed: recentlyPlayed ?? const [],
    likedSongs: likedSongs ?? const [],
    artists: artists ?? const [],
    albums: uniqueAlbums.values.toList(growable: false),
    freshFinds: freshFinds ?? const [],
    warnings: warnings,
  );
  if (data.isEmpty && warnings.isNotEmpty) {
    throw SpotifyApiException(warnings.first);
  }
  return data;
}

Uri _endpoint(String path, [Map<String, String> query = const {}]) =>
    SpotifyApi.apiOrigin.replace(path: path, queryParameters: query);

List<LokalDiscoveryTrack> _tracks(Object? raw, {bool playedAt = false}) {
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is Map)
        if (_track(entry, playedAt: playedAt) case final track?) track,
  ];
}

LokalDiscoveryTrack? _track(Map raw, {required bool playedAt}) {
  final value = raw['track'] is Map ? raw['track'] as Map : raw;
  final id = _text(value['id']);
  final title = _text(value['name']);
  final artists = value['artists'];
  final artist = artists is List
      ? artists.map(_artistName).where((name) => name.isNotEmpty).join(', ')
      : '';
  if (id == null || title == null || artist.isEmpty) return null;
  final album = value['album'];
  final albumName = album is Map ? _text(album['name']) ?? '' : '';
  final image = album is Map ? _image(album['images']) : '';
  final played = playedAt
      ? DateTime.tryParse('${raw['played_at'] ?? ''}')
      : null;
  return LokalDiscoveryTrack(
    title: title,
    artist: artist,
    album: albumName,
    artworkUrl: image,
    url: 'https://open.spotify.com/track/$id',
    scrobbledAt: played == null ? null : played.millisecondsSinceEpoch ~/ 1000,
  );
}

List<LokalDiscoveryArtist> _artists(Object? raw) {
  if (raw is! List) return const [];
  final result = <LokalDiscoveryArtist>[];
  for (final value in raw) {
    if (value is! Map) continue;
    final name = _text(value['name']);
    if (name == null) continue;
    result.add(
      LokalDiscoveryArtist(
        name: name,
        image: _image(value['images']),
        url: 'spotify:artist:${_text(value['id']) ?? ''}',
      ),
    );
  }
  return result;
}

List<LokalDiscoveryAlbum> _albums(Object? raw) {
  if (raw is! List) return const [];
  final result = <LokalDiscoveryAlbum>[];
  for (final value in raw) {
    if (value is! Map || value['artists'] is! List) continue;
    final title = _text(value['name']);
    if (title == null) continue;
    final artist = (value['artists'] as List)
        .map(_artistName)
        .where((name) => name.isNotEmpty)
        .join(', ');
    if (artist.isEmpty) continue;
    result.add(
      LokalDiscoveryAlbum(
        title: title,
        artist: artist,
        artworkUrl: _image(value['images']),
        url: 'spotify:album:${_text(value['id']) ?? ''}',
      ),
    );
  }
  return result;
}

String _artistName(Object? value) =>
    value is Map ? _text(value['name']) ?? '' : '';

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String _image(Object? raw) {
  if (raw is! List) return '';
  for (final value in raw) {
    if (value is Map) {
      final url = _text(value['url']);
      if (url != null) return url;
    }
  }
  return '';
}

String? _idFromSpotifyUrl(String value) {
  return RegExp(r'^spotify:artist:(.+)$').firstMatch(value)?.group(1);
}

/// Uses desktop's cookie-backed Home mixes and Liked Songs operations.
Future<SpotifyDiscoveryData> loadSpotifyWebDiscovery(SpotifyWebApi api) async {
  final warnings = <String>[];
  var mixes = <SpotifyPlaylist>[];
  try {
    mixes = await api.getPlaylists();
  } catch (_) {
    warnings.add('Could not load your Spotify mixes.');
  }
  final quick = <LokalDiscoveryTrack>[];
  final liked = <LokalDiscoveryTrack>[];
  for (var i = 0; i < mixes.take(6).length; i += 2) {
    final group = mixes.take(6).skip(i).take(2);
    final batches = await Future.wait(
      group.map((mix) async {
        try {
          return (await api.getPlaylistTracks(
            mix.id,
            max: 30,
          )).map(spotifyDiscoveryTrack).toList();
        } catch (_) {
          warnings.add('Could not load ${mix.name}.');
          return <LokalDiscoveryTrack>[];
        }
      }),
    );
    quick.addAll(batches.expand((v) => v));
  }
  try {
    liked.addAll((await api.getLikedSongs(max: 30)).map(spotifyDiscoveryTrack));
  } catch (_) {
    warnings.add('Could not load Spotify Liked Songs.');
  }
  final unique = <String, LokalDiscoveryTrack>{for (final t in quick) t.key: t};
  final albums = <String, LokalDiscoveryAlbum>{};
  final artists = <String, LokalDiscoveryArtist>{};
  for (final t in unique.values) {
    artists.putIfAbsent(t.artist, () => LokalDiscoveryArtist(name: t.artist));
    if (t.album.isNotEmpty)
      albums.putIfAbsent(
        '${t.artist}|${t.album}',
        () => LokalDiscoveryAlbum(
          title: t.album,
          artist: t.artist,
          artworkUrl: t.artworkUrl,
        ),
      );
  }
  if (mixes.isEmpty && unique.isEmpty && liked.isEmpty && warnings.isNotEmpty)
    throw const SpotifyApiException(
      'Spotify could not load your mixes. Refresh or update your cookie in Data → Accounts.',
    );
  return SpotifyDiscoveryData(
    account: 'Spotify',
    mixes: [
      for (final mix in mixes)
        LokalDiscoveryMix(
          id: mix.id,
          title: mix.name,
          author: 'Spotify',
          artworkUrl: mix.imageUrl ?? '',
        ),
    ],
    quickPicks: unique.values.toList(),
    likedSongs: liked,
    recentlyPlayed: const [],
    artists: artists.values.take(20).toList(),
    albums: albums.values.take(20).toList(),
    freshFinds: const [],
    warnings: warnings,
  );
}

LokalDiscoveryTrack spotifyDiscoveryTrack(SpotifyTrack t) =>
    LokalDiscoveryTrack(
      title: t.title,
      artist: t.artist,
      album: t.album ?? '',
      artworkUrl: t.imageUrl ?? '',
      duration: Duration(milliseconds: t.durationMs),
      url: 'https://open.spotify.com/track/${t.id}',
    );

/// Metadata only; the caller matches local songs or uses the existing resolver.
Future<List<LokalDiscoveryTrack>> loadSpotifyWebMix(
  SpotifyWebApi api,
  String id,
) async =>
    (await api.getPlaylistTracks(id, max: 200).timeout(const Duration(seconds: 30)))
        .map(spotifyDiscoveryTrack)
        .toList();
