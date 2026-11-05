import 'package:flick/services/apple_music/apple_music_metadata_service.dart';
import 'package:flick/services/apple_music/apple_music_models.dart';
import 'package:flick/services/global_catalogue_search.dart';
import 'package:flutter_test/flutter_test.dart';

class _Apple extends Fake implements AppleMusicMetadataService {
  final calls = <String>[];
  bool rejectOtherEntities = false;
  bool duplicateArtists = false;

  @override
  Future<List<AppleMusicSearchSong>> searchSongs(
    String term, {
    int limit = 40,
    String? storefront,
    bool refresh = false,
  }) async {
    calls.add('songs');
    return const [
      AppleMusicSearchSong(
        catalogueId: '1',
        title: 'Song',
        artist: 'Singer',
        album: 'Album',
        artworkUrl: '',
        duration: Duration.zero,
      ),
    ];
  }

  @override
  Future<List<AppleMusicAlbumMatch>> searchAlbums(
    String term, {
    int limit = 25,
    String? storefront,
    bool refresh = false,
  }) async {
    calls.add('albums');
    if (rejectOtherEntities) throw StateError('Album search unavailable');
    return const [
      AppleMusicAlbumMatch(
        collectionId: '2',
        name: 'Album',
        artistName: 'Singer',
        url: '',
      ),
    ];
  }

  @override
  Future<List<AppleMusicArtist>> searchArtists(
    String term, {
    int limit = 25,
    String? storefront,
    bool refresh = false,
  }) async {
    calls.add('artists');
    if (rejectOtherEntities) throw StateError('Artist search unavailable');
    if (duplicateArtists) {
      return const [
        AppleMusicArtist(artistId: '3', name: 'Beyoncé'),
        AppleMusicArtist(artistId: '87', name: 'BEYONCE'),
        AppleMusicArtist(artistId: '35', name: ' Beyoncé '),
        AppleMusicArtist(artistId: '4', name: 'Beyoncé Knowles'),
        AppleMusicArtist(artistId: '44', name: 'Beyoncé Knowles'),
        AppleMusicArtist(artistId: '5', name: 'Beyoncé Tribute'),
      ];
    }
    return const [AppleMusicArtist(artistId: '3', name: 'Singer')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Songs makes only a song lookup even when album and artist requests would fail', () async {
    final apple = _Apple()..rejectOtherEntities = true;
    final data = await GlobalCatalogueSearchService(appleMusic: apple)
        .search('Wanted', selected: 'apple', songsOnly: true, refresh: true);
    expect(apple.calls, ['songs']);
    expect(data.songs.single.title, 'Song');
    expect(data.albums, isEmpty);
    expect(data.artists, isEmpty);
  });
  test('Apple results collapse duplicate artist records with different IDs',
      () async {
    final apple = _Apple()..duplicateArtists = true;
    final results = await GlobalCatalogueSearchService(appleMusic: apple)
        .search('Beyoncé', selected: 'apple', refresh: true);
    expect(results.artists.map((artist) => artist.name), [
      'Beyoncé',
      'Beyoncé Knowles',
      'Beyoncé Tribute',
    ]);
    expect(results.albums, hasLength(1));
    expect(results.songs, hasLength(1));
  });

  test('Spotify keeps relevant artist order and the best portrait', () {
    final data = parseSpotifyGlobal({
      'artists': {
        'items': [
          {'id': 'a1', 'name': 'Beyoncé', 'images': []},
          {'id': 'a2', 'name': 'BEYONCE', 'images': [
            {'url': 'https://example.test/portrait.jpg', 'width': 640, 'height': 640},
          ]},
          {'id': 'a3', 'name': 'Beyoncé Tribute', 'images': []},
          {'id': 'a4', 'name': ' Beyoncé  ', 'images': []},
          {'id': 'a5', 'name': 'Beyoncé Knowles', 'images': []},
        ],
      },
    });
    expect(data.artists.map((artist) => artist.name), [
      'Beyoncé',
      'Beyoncé Tribute',
      'Beyoncé Knowles',
    ]);
    expect(data.artists.first.artworkUrl,
        'https://example.test/portrait.jpg');
  });

  test('artist dedup preserves distinct names and drops blank entries', () {
    final artists = deduplicateCatalogueArtists([
      const GlobalCatalogueArtist(name: ' Sade '),
      const GlobalCatalogueArtist(name: 'SADE'),
      const GlobalCatalogueArtist(name: 'Sade Adu'),
      const GlobalCatalogueArtist(name: '  '),
      const GlobalCatalogueArtist(name: 'Sade Tribute'),
      const GlobalCatalogueArtist(name: 'Sade Adu'),
    ]);
    expect(artists.map((artist) => artist.name),
        ['Sade', 'Sade Adu', 'Sade Tribute']);
  });

  test('All retains album and artist lookups for the same query', () async {
    final apple = _Apple();
    final service = GlobalCatalogueSearchService(appleMusic: apple);
    await service.search(
      'Wanted',
      selected: 'apple',
      songsOnly: true,
      refresh: true,
    );
    apple.calls.clear();
    final data = await service.search(
      'Wanted',
      selected: 'apple',
      refresh: true,
    );
    expect(apple.calls, ['songs', 'albums', 'artists']);
    expect(data.songs, hasLength(1));
    expect(data.albums, hasLength(1));
    expect(data.artists, hasLength(1));
  });
}
