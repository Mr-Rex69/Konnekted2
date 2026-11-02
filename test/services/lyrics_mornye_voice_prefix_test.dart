import 'package:flick/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = LyricsService();

  test('Mornye plain LRC voice labels are not displayed', () {
    final lyrics = service.parseLyricsText(
      '[00:01.00]v1: Hello\n[00:02.00]v2： World',
    );
    expect(lyrics.lines.map((line) => line.text).toList(), ['Hello', 'World']);
    expect(lyrics.lines.map((line) => line.voice).toList(), ['v1', 'v2']);
    expect(lyrics.lines.first.timestamp, const Duration(seconds: 1));
    expect(lyrics.lines.last.timestamp, const Duration(seconds: 2));
  });

  test('word-synced labels split over timed units do not get highlighted', () {
    final lyrics = service.parseLyricsText(
      '[00:01.00]<00:01.00>v1<00:01.10>:<00:01.20>Hello <00:01.60>world',
    );
    final line = lyrics.lines.single;
    expect(line.text, 'Hello world');
    expect(line.voice, 'v1');
    expect(line.words!.map((word) => word.text).toList(), ['Hello ', 'world']);
    expect(line.words!.first.start, const Duration(milliseconds: 1200));
    expect(line.words!.last.start, const Duration(milliseconds: 1600));
  });

  test('two tagged voices at one timestamp are not folded as translation', () {
    final lyrics = service.parseLyricsText(
      '[00:01.00]v1: First\n[00:01.00]v2: Reply',
    );
    expect(lyrics.lines, hasLength(2));
    expect(lyrics.lines.map((line) => line.text).toList(), ['First', 'Reply']);
    expect(lyrics.lines.every((line) => line.translation == null), isTrue);
  });

  test('prefix cleanup includes embedded plain text and TTML', () {
    final plain = service.parseLyricsText('v1: First\nv2：Second');
    expect(plain.isSynchronized, isFalse);
    expect(plain.lines.map((line) => line.text).toList(), ['First', 'Second']);

    final ttml = service.parseLyricsText(
      '<tt><body><div><p begin="1s">'
      '<span begin="1s" end="1.1s">v2: </span>'
      '<span begin="1.1s" end="1.8s">Reply</span>'
      '</p></div></body></tt>',
    );
    expect(ttml.lines.single.text, 'Reply');
    expect(ttml.lines.single.words!.map((word) => word.text).toList(), [
      'Reply',
    ]);
    expect(ttml.lines.single.words!.single.start,
        const Duration(milliseconds: 1100));
  });

  test('desktop-imported cached lines are normalized on read', () {
    final lyrics = LyricsService.fromDesktop({
      'type': 'synced',
      'lines': [
        {
          'time': 1.0,
          'text': 'v2: Reply',
          'words': [
            {'word': 'v2:', 'time': 1.0, 'end': 1.1, 'space': true},
            {'word': 'Reply', 'time': 1.1, 'end': 1.5, 'space': false},
          ],
        },
      ],
    })!;
    expect(lyrics.lines.single.text, 'Reply');
    expect(lyrics.lines.single.voice, 'v2');
    expect(lyrics.lines.single.words, hasLength(1));
    expect(lyrics.lines.single.words!.single.start,
        const Duration(milliseconds: 1100));
  });

  test('ordinary lyrics mentioning v1 are not changed', () {
    final lyrics = service.parseLyricsText(
      '[00:01.00]I tried v1: again\n[00:02.00]v1: ',
    );
    expect(lyrics.lines.map((line) => line.text).toList(), [
      'I tried v1: again',
      'v1:',
    ]);
  });
}
