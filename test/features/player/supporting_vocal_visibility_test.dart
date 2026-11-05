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

  test('the focused lead does not shift when a standalone bg row begins', () {
    const timeline = LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [
        LyricsLine(timestamp: Duration(seconds: 15), text: 'Starting to fade'),
        LyricsLine(
          timestamp: Duration(seconds: 17),
          text: 'Quiet backing voice',
          voice: 'bg',
          words: [
            LyricsWord(
              start: Duration(seconds: 17),
              end: Duration(seconds: 21),
              text: 'Quiet backing voice',
            ),
          ],
        ),
        LyricsLine(
          timestamp: Duration(seconds: 19),
          text: 'Next main lyric',
        ),
      ],
    );
    expect(visibleLeadLyricIndices(timeline), [0, 2]);
    expect(focusedVisibleLyricIndex(timeline, const Duration(seconds: 18)), 0);
    expect(focusedVisibleLyricIndex(timeline, const Duration(seconds: 20)), 1);
    final bgOnFirst = activeSupportingVocals(
      timeline, const Duration(seconds: 18), 0,
    );
    expect(bgOnFirst, hasLength(1));
    expect(bgOnFirst.single.lineIndex, 1);
    expect(bgOnFirst.single.standalone, isTrue);
    final bgOnSecond = activeSupportingVocals(
      timeline, const Duration(seconds: 20), 2,
    );
    expect(bgOnSecond, hasLength(1));
    expect(bgOnSecond.single.lineIndex, 1);
    expect(bgOnSecond.single.standalone, isTrue);
    expect(activeSupportingVocals(
      timeline, const Duration(seconds: 21), 2,
    ), isEmpty);
  });

  test('attached background voice appears beneath its own active lead', () {
    final selected = activeSupportingVocals(
      lyrics, const Duration(seconds: 18), 0,
    );
    expect(selected, hasLength(1));
    expect(selected.single.lineIndex, 0);
    expect(selected.single.standalone, isFalse);
    // At t=20 the same singer moves beneath the new active lead.
    final overlap = activeSupportingVocals(
      lyrics, const Duration(seconds: 20), 1,
    );
    expect(overlap, hasLength(1));
    expect(overlap.single.lineIndex, 0);
    expect(overlap.single.standalone, isFalse);
  });

  test('untimed attached backing text follows its own active lead only', () {
    const sample = LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [
        LyricsLine(
          timestamp: Duration(seconds: 10),
          text: 'Lead',
          backgroundText: 'Untimed harmony',
        ),
        LyricsLine(timestamp: Duration(seconds: 15), text: 'Next'),
      ],
    );
    expect(activeSupportingVocals(
      sample, const Duration(seconds: 12), 0,
    ), hasLength(1));
    expect(activeSupportingVocals(
      sample, const Duration(seconds: 17), 1,
    ), isEmpty);
  });

  test('background-only file remains readable if there is no lead', () {
    const only = LyricsData(
      isSynchronized: true,
      rawContent: '',
      lines: [
        LyricsLine(
          timestamp: Duration(seconds: 17),
          voice: 'bg',
          text: 'Independent harmony',
        ),
      ],
    );
    expect(visibleLeadLyricIndices(only), [0]);
    expect(focusedVisibleLyricIndex(only, const Duration(seconds: 18)), 0);
    expect(activeSupportingVocals(only, const Duration(seconds: 18), 0), isEmpty);
  });

}
