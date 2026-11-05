import 'package:flick/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = LyricsService();

  test('enhanced LRC backing vocals are timed separately under the lead', () {
    const lrc = '[ti:Example]\n'
        '[00:15.433]v1:<00:15.433>Lead <00:16.353>voice <00:22.852>\n'
        '[bg:<00:17.254><00:17.254>Backing <00:17.726><00:17.726>voice <00:21.736><00:21.736>]\n'
        '[00:23.055]v1:<00:23.055>Next <00:24.039>line <00:24.474>';
    final parsed = service.parseLyricsText(lrc);
    expect(parsed.isSynchronized, isTrue);
    expect(parsed.lines, hasLength(2));
    final lead = parsed.lines.first;
    expect(lead.text, 'Lead voice');
    expect(lead.voice, 'v1');
    expect(lead.backgroundText, 'Backing voice');
    expect(lead.translation, isNull);
    expect(lead.backgroundWords!.map((w) => w.text).toList(), ['Backing ', 'voice ']);
    expect(lead.backgroundWords!.map((w) => w.start.inMilliseconds).toList(), [17254, 17726]);
    expect(lead.backgroundWords!.last.end.inMilliseconds, 21736);
    final playback = service.playbackLines(parsed);
    expect(playback.first.backgroundText, 'Backing voice');
    expect(playback.first.backgroundWords!.last.end.inMilliseconds, 21736);
    expect(playback.last.backgroundText, isNull);
  });

  test('backing words survive enhanced-LRC export and desktop payload import', () {
    const input = '[00:01.00]<00:01.00>Lead<00:03.00>\n'
        '[bg:<00:01.50><00:01.50>Harmony<00:02.50><00:02.50>]';
    final parsed = service.parseLyricsText(input);
    final encoded = service.buildLrcContent(lines: parsed.lines);
    expect(encoded, contains('[bg:'));
    final roundTrip = service.parseLyricsText(encoded);
    expect(roundTrip.lines.single.backgroundText, 'Harmony');
    expect(roundTrip.lines.single.backgroundWords!.first.start.inMilliseconds, 1500);
    final imported = LyricsService.fromDesktop({
      'type': 'synced',
      'lines': [
        {
          'time': 1.0,
          'text': 'Lead',
          'bgText': 'Harmony',
          'bgWords': [
            {'word': 'Harmony', 'time': 1.5, 'end': 2.5, 'space': false},
          ],
        },
      ],
    })!;
    expect(imported.lines.single.backgroundText, 'Harmony');
    expect(imported.lines.single.backgroundWords!.single.end.inMilliseconds, 2500);
  });

  test('multiple backing rows attach to the same lead, without translations', () {
    const input = '[00:01.00]<00:01.00>Lead<00:04.00>\n'
        '[bg:<00:01.50>Low<00:02.00>]\n'
        '[bg:<00:02.10>High<00:03.00>]\n'
        '[00:05.00]<00:05.00>Next<00:06.00>';
    final parsed = service.parseLyricsText(input);
    expect(parsed.lines, hasLength(2));
    expect(parsed.lines.first.backgroundText, 'Low High');
    expect(parsed.lines.first.translation, isNull);
  });

  test('ordinary unstamped notes are not mistaken for backing voices', () {
    final parsed = service.parseLyricsText(
      '[00:01.00]<00:01.00>Lead<00:02.00>\n'
      'Unstamped note\n'
      '[00:03.00]<00:03.00>Next<00:04.00>',
    );
    expect(parsed.lines, hasLength(2));
    expect(parsed.lines.every((l) => l.backgroundText == null), isTrue);
  });
}
