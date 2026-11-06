import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song({String? sourcePackage}) => Song(
  id: 'recording',
  title: 'Song',
  artist: 'Artist',
  duration: Duration.zero,
  fileType: 'FLAC',
  sourcePackage: sourcePackage,
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
}
