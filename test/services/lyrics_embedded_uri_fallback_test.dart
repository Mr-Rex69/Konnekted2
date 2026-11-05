import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/lyrics_service.dart';

void main() {
  test('scanned FLAC path retains its paired MediaStore URI for lyrics', () {
    final candidates = LyricsService.embeddedUriCandidates(
      '/storage/emulated/0/Music/Phantom Liberty.flac',
      mediaStoreUri: 'content://media/external/audio/media/351',
    );
    expect(candidates, [
      '/storage/emulated/0/Music/Phantom Liberty.flac',
      'content://media/external/audio/media/351',
    ]);
  });

  test('URI-backed local FLAC does not duplicate the same read', () {
    final candidates = LyricsService.embeddedUriCandidates(
      'content://media/external/audio/media/351',
      mediaStoreUri: 'content://media/external/audio/media/351',
    );
    expect(candidates, hasLength(1));
  });

  test('does not redirect a file to an untrusted non-content URI', () {
    final candidates = LyricsService.embeddedUriCandidates(
      '/storage/emulated/0/Music/a.flac',
      mediaStoreUri: 'https://host.invalid/other.flac',
    );
    expect(candidates, ['/storage/emulated/0/Music/a.flac']);
  });
}
