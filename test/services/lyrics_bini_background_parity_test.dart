import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/flowing_background_vocals.dart';
import 'package:flick/features/player/widgets/lyrics_focus_timing.dart';
import 'package:flick/services/lyrics_service.dart';

void main() {
  final parser = LyricsService();

  test('BiniLyrics TTML moves trailing parentheses to independently timed background words', () {
    // Anonymized Pump It-style Apple TTML: the ad-lib begins after the lead
    // but finishes after a following line has already started.
    const bini = '''
<tt xml:lang="en"><body><div>
  <p begin="10s" end="14s">
    <span begin="10s" end="11s">Pump</span> <span begin="11s" end="11.5s">it</span>
    <span begin="11.6s" end="12.7s">(Answer</span> <span begin="12.7s" end="13.9s">here)</span>
  </p>
  <p begin="13.2s" end="14.9s"><span begin="13.2s" end="14.9s">Next</span></p>
</div></body></tt>''';
    final lyrics = parser.parseLyricsText(bini, source: 'BiniLyrics');
    expect(lyrics.isSynchronized, isTrue);
    expect(lyrics.source, 'BiniLyrics');
    expect(lyrics.lines, hasLength(2));
    final first = lyrics.lines.first;
    expect(first.text, 'Pump it');
    expect(first.backgroundText, '(Answer here)');
    expect(first.words, hasLength(2));
    expect(first.backgroundWords, hasLength(2));
    expect(first.words!.last.end, const Duration(milliseconds: 11500));
    expect(first.backgroundWords!.first.start, const Duration(milliseconds: 11600));
    expect(first.backgroundWords!.last.end, const Duration(milliseconds: 13900));
    expect(flowingBackgroundVocalLines(lyrics.lines), hasLength(1));
    expect(focusedLeadUntilVocalsFinish(
      lyrics.lines, const Duration(milliseconds: 13300),
    ), 0, reason: 'Do not scroll away from a still-singing background voice.');
    expect(focusedLeadUntilVocalsFinish(
      lyrics.lines, const Duration(milliseconds: 13900),
    ), 1);
  });

  test('Apple/Bini TTML x-bg role separates a nested voice instead of joining lead', () {
    const bini = '''
<tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
  <body><div><p begin="10s" end="20s">
    <span begin="10s" end="11s">Lead</span>
    <span ttm:role="x-bg">
      <span begin="12s" end="13s">(Reply</span> <span begin="13s" end="16s">again)</span>
    </span>
    <span ttm:role="x-roman">TRANSLITERATION-NOT-SUNG</span>
  </p></div></body>
</tt>''';
    final parsed = parser.parseLyricsText(bini, source: 'BiniLyrics');
    final first = parsed.lines.single;
    expect(first.text, 'Lead');
    expect(first.words, hasLength(1));
    expect(first.backgroundText, '(Reply again)');
    expect(first.backgroundWords, hasLength(2));
    expect(first.backgroundWords!.first.start, const Duration(seconds: 12));
    expect(first.backgroundWords!.last.end, const Duration(seconds: 16));
    expect(parsed.rawContent, bini);
  });

  test('standalone TTML x-bg paragraph never steals the following lead row', () {
    const xml = '''
<tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
  <body><div>
    <p begin="10s"><span begin="10s" end="11s">Lead</span></p>
    <p begin="12s"><span ttm:role="x-bg">
      <span begin="12s" end="13s">(Response)</span></span></p>
    <p begin="14s"><span begin="14s" end="15s">Next</span></p>
  </div></body>
</tt>''';
    final parsed = parser.parseLyricsText(xml);
    expect(parsed.lines, hasLength(3));
    expect(parsed.lines[1].voice, 'bg');
    expect(parsed.lines[1].text, '(Response)');
    expect(flowingBackgroundVocalLines(parsed.lines), hasLength(1));
  });

  test('enhanced LRC trailing parenthesis keeps each singer on its own timed lane', () {
    const lrc = '[00:10.00]<00:10.00>Lead <00:11.00>(Backing <00:13.00>voice)';
    final parsed = parser.parseLyricsText(lrc);
    final line = parsed.lines.single;
    expect(line.text, 'Lead');
    expect(line.backgroundText, '(Backing voice)');
    expect(line.words, hasLength(1));
    expect(line.backgroundWords, hasLength(2));
    expect(line.backgroundWords!.first.start, const Duration(seconds: 11));
    expect(line.backgroundWords!.last.start, const Duration(seconds: 13));
  });

  test('line-synced LRC splits trailing brackets without inventing word timings', () {
    const lrc = '[00:10.00]Lead (Response)\n[00:15.00]Next';
    final parsed = parser.parseLyricsText(lrc);
    expect(parsed.lines.first.text, 'Lead');
    expect(parsed.lines.first.backgroundText, '(Response)');
    expect(parsed.lines.first.words, isNull);
    expect(parsed.lines.first.backgroundWords, isNull);
    expect(parsed.lines.last.backgroundText, isNull);
  });

  test('parenthesized word suffixes, non-trailing comments, and bg-only lines stay intact', () {
    final data = parser.parseLyricsText([
      '[00:01.00]wait(ing)',
      '[00:02.00](only a response)',
      '[00:03.00]Main (clarification) continues',
    ].join('\n'));
    expect(data.lines.map((x) => x.text).toList(), [
      'wait(ing)', '(only a response)',
      'Main (clarification) continues',
    ]);
    expect(data.lines.every((x) => x.backgroundText == null), isTrue);
  });

  test('already structured background vocals are never split or duplicated', () {
    final data = parser.parseLyricsText(
      '[00:10.00]<00:10.00>Lead<00:11.00>\n'
      '[bg:<00:10.20>(Backing)<00:11.60>]',
    );
    expect(data.lines, hasLength(1));
    expect(data.lines.single.backgroundText, '(Backing)');
    expect(LyricsService.supportingVocalCount(data), 1);
  });
}
