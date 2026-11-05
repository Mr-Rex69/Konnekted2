import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/synced_lyrics_view.dart';
import 'package:flick/services/lyrics_service.dart';

void main() {
  const lyrics = LyricsData(
    isSynchronized: true,
    rawContent: '',
    lines: [
      LyricsLine(
        timestamp: Duration(seconds: 15),
        text: 'First lead',
        backgroundText: 'Supporting voice',
        backgroundWords: [
          LyricsWord(
            start: Duration(seconds: 17),
            end: Duration(seconds: 22),
            text: 'Supporting voice',
          ),
        ],
      ),
      LyricsLine(
        timestamp: Duration(seconds: 19),
        text: 'Second lead',
      ),
    ],
  );

  test('normal lyrics keep the backing singer active with the next lead', () {
    expect(overlappingBackgroundVocalIndices(
      lyrics, const Duration(seconds: 20), 1,
    ), [0]);
    expect(overlappingBackgroundVocalIndices(
      lyrics, const Duration(seconds: 21), 1,
    ), [0]);
  });

  test('do not duplicate focused line or display vocals outside timing', () {
    expect(overlappingBackgroundVocalIndices(
      lyrics, const Duration(seconds: 20), 0,
    ), isEmpty);
    expect(overlappingBackgroundVocalIndices(
      lyrics, const Duration(seconds: 16), 1,
    ), isEmpty);
    expect(overlappingBackgroundVocalIndices(
      lyrics, const Duration(seconds: 22), 1,
    ), isEmpty);
  });
}
