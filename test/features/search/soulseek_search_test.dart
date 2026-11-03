import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/soulseek_service.dart';
import 'package:flick/features/search/widgets/soulseek_search_section.dart';

void main() {
  test('remote paths preserve peer, filename and directory identity', () {
    final file = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Library\Artist\Album\01 - Track.FLAC',
      'size': 10485760, 'extension': 'FLAC', 'bitDepth': 24,
      'sampleRate': 96000, 'freeSlot': true, 'score': 200,
    });
    expect(file.name, '01 - Track.FLAC');
    expect(file.folder, 'Album');
    expect(file.key, contains('peer'));
    expect(file.quality, 'FLAC 24-bit/96.0kHz');
    expect(file.lossless, isTrue);
    expect(SoulseekFile.fromMap(file.toMap()).key, file.key);
  });

  test('file labels and sizes handle empty and compressed results', () {
    final file = SoulseekFile.fromMap({
      'username': 'another', 'filename': r'Various\Example.mp3',
      'size': 0, 'extension': 'MP3', 'bitrate': 320,
    });
    expect(file.lossless, isFalse);
    expect(file.quality, 'MP3 320 kbps');
    expect(soulseekSize(0), '0 B');
    expect(soulseekSize(1048576), '1.0 MB');
    expect(soulseekSize(1073741824), '1.00 GB');
  });

  test('album downloads never combine different peer directories', () {
    final first = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Music\Artist A\Greatest Hits\01.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    final otherArtist = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Music\Artist B\Greatest Hits\02.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    final nextTrack = SoulseekFile.fromMap({
      'username': 'peer', 'filename': r'Music\Artist A\Greatest Hits\03.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    final otherPeer = SoulseekFile.fromMap({
      'username': 'another', 'filename': r'Music\Artist A\Greatest Hits\01.flac',
      'size': 1024, 'extension': 'FLAC',
    });
    expect(first.folder, 'Greatest Hits');
    expect(first.albumGroupKey, nextTrack.albumGroupKey);
    expect(first.albumGroupKey, isNot(otherArtist.albumGroupKey));
    expect(first.albumGroupKey, isNot(otherPeer.albumGroupKey));
  });


  test('sharing never accidentally exposes entire device or SD-card roots', () {
    for (final unsafe in <String>[
      '/', '/sdcard', '/storage/emulated/0', '/storage/emulated/10',
      '/storage/1234-5678', '/storage/self/primary', '/mnt',
      '/mnt/media_rw/1234-5678', '/mnt/runtime/default/1234-5678',
      '/data', '/storage',
    ]) {
      expect(soulseekIsUnsafeShareRoot(unsafe), isTrue, reason: unsafe);
    }
    for (final allowed in <String>[
      '/storage/emulated/0/Music',
      '/storage/1234-5678/My Music',
      '/mnt/media_rw/1234-5678/Audio',
    ]) {
      expect(soulseekIsUnsafeShareRoot(allowed), isFalse, reason: allowed);
    }
  });

}
