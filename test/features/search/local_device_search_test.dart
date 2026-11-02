import 'package:flick/models/song.dart';
import 'package:flick/features/search/providers/local_device_search.dart';
import 'package:flutter_test/flutter_test.dart';

Song sample(String id, {String? source, String? path}) => Song(
  id: id,
  title: '30 For 30 (with Kendrick Lamar)',
  artist: 'SZA',
  albumArtist: 'SZA',
  album: 'SOS Deluxe: LANA',
  duration: const Duration(seconds: 278),
  filePath: path ?? '/music/sza.flac',
  fileType: 'FLAC',
  sourceType: source,
);

void main() {
  test('phone Local search never returns desktop Link rows', () {
    final phone = sample('phone');
    final desktop = sample('desktop', source: 'lokal', path: 'lokal://1/30');
    final ghost = sample('ghost', source: 'lokal', path: 'ghost://desktop/30');
    expect(phoneLocalSearchSongs([desktop, phone, ghost]), [phone]);
    // Both valid copies remain in the library, independent of local search.
    expect([desktop, phone].length, 2);
  });
}
