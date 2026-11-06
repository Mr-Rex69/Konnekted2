import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song({String? sourcePackage, String? sourceDisplayName, String? albumArt}) => Song(
  id: 'recording',
  title: 'Song',
  artist: 'Artist',
  duration: Duration.zero,
  fileType: 'FLAC',
  sourcePackage: sourcePackage,
  sourceDisplayName: sourceDisplayName,
  albumArt: albumArt,
);

void main() {
  test('missing LastWave/search cover uses a bounded online fallback', () {
    expect(shouldRecoverOnlineArtwork(
      _song(sourcePackage: Song.pendingSourcePackage)), isTrue);
    expect(shouldRecoverOnlineArtwork(
      _song(sourcePackage: 'konnekted.discovery')), isTrue);
    expect(shouldRecoverOnlineArtwork(
      _song(sourcePackage: 'konnekted.progressive')), isTrue);
    expect(shouldRecoverOnlineArtwork(
      _song(sourcePackage: 'konnekted.morneye-live')), isTrue);

    // Local files never cause an automatic metadata network lookup.
    expect(shouldRecoverOnlineArtwork(_song()), isFalse);
  });

  test('Amazon full player always requests independent artwork, even with a valid cover', () {
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: 'konnekted.morneye-live',
      sourceDisplayName: 'Amazon Music',
      albumArt: 'https://m.media-amazon.com/images/I/COVER._SX1500_.jpg',
    )), isTrue);
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: 'konnekted.discovery',
      sourceDisplayName: 'Amazon (New)',
      albumArt: 'https://cdn.example.com/cover.jpg',
    )), isTrue);
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: 'konnekted.progressive',
      sourceDisplayName: 'Amazon',
      albumArt: null,
    )), isTrue);
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: Song.pendingSourcePackage,
      sourceDisplayName: 'Amazon Music',
    )), isTrue);
  });

  test('other providers and local songs keep the existing artwork policy', () {
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: 'konnekted.morneye-live',
      sourceDisplayName: 'Tidal',
    )), isFalse);
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: 'konnekted.discovery',
      sourceDisplayName: 'LastWave',
    )), isFalse);
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourcePackage: 'konnekted.discovery',
      sourceDisplayName: 'Amazonian Music',
    )), isFalse);
    expect(shouldPreferIndependentAmazonArtwork(_song(
      sourceDisplayName: 'Amazon Music',
      albumArt: 'https://example.com/cover.jpg',
    )), isFalse);
  });
}
