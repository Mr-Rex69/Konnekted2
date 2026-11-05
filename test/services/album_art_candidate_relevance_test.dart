import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/album_art_import_service.dart';

AlbumArtCandidate cover(String title, String artist, String image) =>
    AlbumArtCandidate(
      title: title,
      artist: artist,
      imageUrl: 'https://cdn.test/$image.jpg',
      previewUrl: 'https://cdn.test/$image.jpg',
      sourceLabel: 'iTunes',
    );

void main() {
  test('SZA album artwork ranks ahead of same-named unrelated releases', () {
    final results = relevantAlbumArtwork(
      album: 'SOS',
      artist: 'SZA',
      candidates: [
        cover('SOS', 'Other Artist', 'wrong'),
        cover('SOS (Deluxe)', 'SZA', 'deluxe'),
        cover('SOS', 'SZA', 'exact'),
      ],
    );
    expect(results.map((c) => c.imageUrl).toList(), [
      'https://cdn.test/exact.jpg',
      'https://cdn.test/deluxe.jpg',
    ]);
  });

  test('duplicate source URLs do not consume the candidate limit', () {
    final same = cover('Album', 'Artist', 'one');
    final results = relevantAlbumArtwork(
      album: 'Album', artist: 'Artist',
      candidates: [same, same, cover('Album', 'Artist', 'two')],
    );
    expect(results.length, 2);
  });

  test('non-Latin titles and artists retain exact match', () {
    final results = relevantAlbumArtwork(
      album: '東京', artist: '竹内まりや',
      candidates: [
        cover('東京', 'Other Artist', 'wrong'),
        cover('東京', '竹内まりや', 'correct'),
      ],
    );
    expect(results.single.imageUrl, 'https://cdn.test/correct.jpg');
  });

  test('shorter album and partial artist names do not match', () {
    expect(relevantAlbumArtwork(
      album: 'Blue Train', artist: 'John',
      candidates: [
        cover('Blue', 'John', 'wrong-album'),
        cover('Blue Train', 'Johnny', 'wrong-artist'),
      ],
    ), isEmpty);
  });

  test('similarly named releases by different artists are rejected', () {
    expect(relevantAlbumArtwork(
      album: 'Dangerous', artist: 'Artist A',
      candidates: [
        cover('Dangerous', 'Artist B', 'bad'),
        cover('Dangerously', 'Artist A', 'different-title'),
      ],
    ), isEmpty);
  });
}
