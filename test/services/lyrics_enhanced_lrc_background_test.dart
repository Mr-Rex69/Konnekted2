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

  test('41 lead lines retain 16 backing vocals grouped after a blank line', () {
    String clock(int seconds) =>
        (seconds ~/ 60).toString().padLeft(2, '0') + ':' +
        (seconds % 60).toString().padLeft(2, '0');
    final leads = List.generate(41, (i) {
      final t = clock(i * 5);
      return '[' + t + '.000]v1:<' + t + '.000>Lead ' +
          (i + 1).toString() + '<' + t + '.900>';
    });
    final backing = List.generate(16, (i) {
      final t = clock(76 + i * 5);
      return '[bg:<' + t + '.100><' + t + '.100>Voice ' +
          (i + 1).toString() + '<' + t + '.900>]';
    });
    final parsed = service.parseLyricsText([...leads, '', ...backing].join('\n'));
    expect(parsed.lines, hasLength(41));
    final withVoices = parsed.lines.where((l) => l.backgroundText != null).toList();
    expect(withVoices, hasLength(16));
    expect(parsed.lines[15].backgroundText, 'Voice 1');
    expect(parsed.lines[16].backgroundText, 'Voice 2');
    expect(parsed.lines[15].backgroundWords!.first.start.inMilliseconds, 76100);
    expect(parsed.lines.first.backgroundText, isNull);
    expect(parsed.lines.last.backgroundText, isNull);
  });

  test('backing vocals before their lead or after unrelated rows are not discarded', () {
    final parsed = service.parseLyricsText([
      '[bg:<00:07.00><00:07.00>Early<00:08.00>]',
      '',
      '[00:05.00]<00:05.00>First<00:09.00>',
      '[00:10.00]<00:10.00>Second<00:13.00>',
      '',
      '[bg:<00:11.00><00:11.00>Late<00:12.00>]',
    ].join('\n'));
    expect(parsed.lines, hasLength(2));
    expect(parsed.lines.first.backgroundText, 'Early');
    expect(parsed.lines.last.backgroundText, 'Late');
  });


  test('background-only embedded lyric payload is a standalone vocal track', () {
    const onlyBacking =
        '[bg:<00:17.254><00:17.254>Backing <00:17.726>voice <00:21.736>]\n'
        '[bg:<00:27.000>Second <00:28.000>voice <00:30.000>]';
    final parsed = service.parseLyricsText(
      onlyBacking, source: 'embedded:vorbis',
    );
    expect(parsed.isSynchronized, isTrue);
    expect(parsed.lines, hasLength(2));
    expect(parsed.lines.every((line) => line.voice == 'bg'), isTrue);
    expect(parsed.lines[0].text, 'Backing voice');
    expect(parsed.lines[0].words!.first.start.inMilliseconds, 17254);
    expect(LyricsService.supportingVocalCount(parsed), 2);
  });

  test('complete 16-voice standalone field overlays 41 rich lead rows', () {
    String clock(int seconds) =>
        (seconds ~/ 60).toString().padLeft(2, '0') + ':' +
        (seconds % 60).toString().padLeft(2, '0');
    final leads = List.generate(41, (i) {
      final t = clock(i * 5);
      return '[' + t + '.000]v1:<' + t + '.000>Lead ' +
          (i + 1).toString() + '<' + t + '.900>';
    });
    final backing = List.generate(16, (i) {
      final t = clock(76 + i * 5);
      return '[bg:<' + t + '.100><' + t + '.100>Voice ' +
          (i + 1).toString() + '<' + t + '.900>]';
    });
    final primary = service.parseLyricsText(leads.join('\n'), source: 'Desktop');
    final bgOnly = service.parseLyricsText(backing.join('\n'),
        source: 'embedded:vorbis');

    expect(LyricsService.supportingVocalCount(primary), 0);
    expect(LyricsService.supportingVocalCount(bgOnly), 16);

    final merged = LyricsService.mergeSupportingVocals(
      primary, [bgOnly],
    )!;
    expect(merged.lines, hasLength(41));
    expect(merged.lines[15].text, primary.lines[15].text);
    expect(merged.lines[15].words!.first.start,
        primary.lines[15].words!.first.start);
    expect(merged.lines[15].backgroundText, 'Voice 1');
    expect(merged.lines[30].backgroundText, 'Voice 16');
    expect(LyricsService.supportingVocalCount(merged), 16);

    // Re-loading the same embedded tag must not double supporting vocals.
    final mergedTwice = LyricsService.mergeSupportingVocals(merged, [bgOnly])!;
    expect(LyricsService.supportingVocalCount(mergedTwice), 16);
    expect(mergedTwice.lines[15].backgroundText, 'Voice 1');
  });

  test('background voice from a lead source survives a lead-only upgrade', () {
    final local = service.parseLyricsText(
      '[00:15.00]<00:15.00>Lead<00:22.00>\n'
      '[bg:<00:17.00><00:17.00>Backing<00:21.00>]',
      source: 'embedded:vorbis',
    );
    final online = service.parseLyricsText(
      '[00:15.00]<00:15.00>Lead<00:22.00>',
      source: 'online',
    );
    final resolved = LyricsService.mergeSupportingVocals(online, [local])!;
    expect(resolved.source, 'online');
    expect(resolved.lines.single.backgroundText, 'Backing');
    expect(resolved.lines.single.backgroundWords!.first.start.inSeconds, 17);
  });

}
