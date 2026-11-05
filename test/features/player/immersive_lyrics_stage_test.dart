import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/immersive_lyrics_stage.dart';
import 'package:flick/services/lyrics_service.dart';

void main() {
  const synchronized = LyricsData(
    isSynchronized: true,
    rawContent: '',
    lines: [
      LyricsLine(
        timestamp: Duration(seconds: 2), text: 'First lyric',
        translation: 'First translated line',
      ),
      LyricsLine(
        timestamp: Duration(seconds: 6), text: 'Second lyric',
        translation: 'Second translated line',
      ),
      LyricsLine(
        timestamp: Duration(seconds: 10), text: 'Third lyric',
      ),
    ],
  );

  test('subtitle selection follows the same absolute audio clock as normal lyrics', () {
    expect(immersiveLyricsLineIndex(synchronized, Duration.zero), -1);
    expect(immersiveLyricsLineIndex(synchronized, const Duration(seconds: 2)), 0);
    expect(immersiveLyricsLineIndex(synchronized, const Duration(seconds: 5)), 0);
    expect(immersiveLyricsLineIndex(synchronized, const Duration(seconds: 6)), 1);
    expect(immersiveLyricsLineIndex(synchronized, const Duration(seconds: 11)), 2);
    expect(immersiveLyricsLineIndex(synchronized, const Duration(seconds: 3)), 0,
        reason: 'A backward seek must update the selected lyric immediately');
  });

  test('translated or romanized sublines keep timestamps and current line', () {
    const romanized = LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [
        LyricsLine(
          timestamp: Duration(seconds: 2),
          text: 'First lyric',
          translation: 'First romanized line',
        ),
        LyricsLine(
          timestamp: Duration(seconds: 6),
          text: 'Second lyric',
          translation: 'Second romanized line',
        ),
        LyricsLine(timestamp: Duration(seconds: 10), text: 'Third lyric'),
      ],
    );
    for (final t in [0, 2000, 3000, 7000, 12000]) {
      final position = Duration(milliseconds: t);
      expect(
        immersiveLyricsLineIndex(romanized, position),
        immersiveLyricsLineIndex(synchronized, position),
      );
    }
    expect(romanized.lines[1].translation, isNotNull);
  });

  test('Space footer is visible only for synchronized line/word lyrics', () {
    expect(hasImmersiveLyrics(null), isFalse);
    expect(hasImmersiveLyrics(synchronized), isTrue);
    expect(hasImmersiveLyrics(const LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [],
    )), isFalse);
    expect(hasImmersiveLyrics(const LyricsData(
      isSynchronized: false,
      rawContent: '',
      lines: [LyricsLine(timestamp: Duration.zero, text: 'Plain')],
    )), isFalse);
  });

  test('plain lyrics never get fabricated timing', () {
    const plain = LyricsData(
      isSynchronized: false,
      rawContent: 'Plain lyric',
      lines: [
        LyricsLine(timestamp: Duration.zero, text: 'Plain lyric'),
      ],
    );
    expect(immersiveLyricsLineIndex(plain, const Duration(minutes: 2)), -1);
  });

  test('Space treats a standalone backing singer as an independently timed line', () {
    const vocals = LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [
        LyricsLine(
          timestamp: Duration(milliseconds: 17254),
          voice: 'bg',
          text: 'Harmony',
          words: [
            LyricsWord(
              start: Duration(milliseconds: 17254),
              end: Duration(milliseconds: 21736),
              text: 'Harmony',
            ),
          ],
        ),
      ],
    );
    expect(hasImmersiveLyrics(vocals), isTrue);
    expect(LyricsService.supportingVocalCount(vocals), 1);
    expect(immersiveLyricsLineIndex(vocals, const Duration(seconds: 18)), 0);
    expect(
      immersiveActiveLineIndices(vocals, const Duration(seconds: 18)),
      [0],
    );
  });

  test('independent backing timing overlaps the next lead in Space', () {
    const vocals = LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [
        LyricsLine(
          timestamp: Duration(seconds: 15),
          text: 'Lead',
          backgroundText: 'Harmony',
          backgroundWords: [
            LyricsWord(
              start: Duration(seconds: 17),
              end: Duration(seconds: 22),
              text: 'Harmony',
            ),
          ],
        ),
        LyricsLine(timestamp: Duration(seconds: 19), text: 'Next lead'),
      ],
    );
    expect(
      immersiveActiveLineIndices(vocals, const Duration(seconds: 20)),
      [0, 1],
      reason: 'The background singer remains active after the next lead starts',
    );
  });

}
