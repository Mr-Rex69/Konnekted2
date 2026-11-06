import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/synced_lyrics_view.dart';
import 'package:flick/features/player/widgets/lyrics_focus_timing.dart';
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

  test('Pump It timing: hold lead focus until background singer finishes', () {
    const lines = <LyricsLine>[
      LyricsLine(
        timestamp: Duration(milliseconds: 15902), text: 'Lead A',
        words: [
          LyricsWord(start: Duration(milliseconds: 15902),
              end: Duration(milliseconds: 16564), text: 'Lead A'),
        ],
        backgroundText: 'Harmony A',
        backgroundWords: [
          LyricsWord(start: Duration(milliseconds: 16732),
              end: Duration(milliseconds: 17660), text: 'Harmony A'),
        ],
      ),
      LyricsLine(
        timestamp: Duration(milliseconds: 17669), text: 'Lead B',
        words: [
          LyricsWord(start: Duration(milliseconds: 17669),
              end: Duration(milliseconds: 18330), text: 'Lead B'),
        ],
      ),
      LyricsLine(
        timestamp: Duration(milliseconds: 35223), text: 'Lead C',
        words: [
          LyricsWord(start: Duration(milliseconds: 35223),
              end: Duration(milliseconds: 36282), text: 'Lead C'),
        ],
        backgroundText: 'Harmony C',
        backgroundWords: [
          LyricsWord(start: Duration(milliseconds: 36421),
              end: Duration(milliseconds: 36739), text: 'Harmony C'),
        ],
      ),
      LyricsLine(
        timestamp: Duration(milliseconds: 36711), text: 'Lead D',
        words: [
          LyricsWord(start: Duration(milliseconds: 36711),
              end: Duration(milliseconds: 38090), text: 'Lead D'),
        ],
      ),
    ];
    const data = LyricsData(isSynchronized: true, rawContent: '', lines: lines);
    // Lead A already ended, yet its background is still sounding.
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 17000)), 0);
    expect(focusedLeadUntilVocalsFinish(lines,
        const Duration(milliseconds: 17000)), 0);
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 17659)), 0);
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 17669)), 1);
    // Lead D starts at 36.711, but Lead C's backing ends at 36.739.
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 36720)), 2);
    expect(focusedLeadUntilVocalsFinish(lines,
        const Duration(milliseconds: 36720)), 2);
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 36739)), 3);
    // A seek is determined purely by time, with no stale prior focus.
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 16500)), 0);
    expect(focusedVisibleLyricIndex(data, const Duration(milliseconds: 36740)), 3);
  });

  test('start-only lyrics without actual word ends switch on next timestamp', () {
    const data = LyricsData(isSynchronized: true, rawContent: '', lines: [
      LyricsLine(timestamp: Duration(seconds: 10), text: 'Start-only'),
      LyricsLine(timestamp: Duration(seconds: 12), text: 'Next'),
    ]);
    expect(focusedVisibleLyricIndex(data, const Duration(seconds: 12)), 1);
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
