import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/lyrics_flac_vorbis_reader.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/features/player/widgets/flowing_background_vocals.dart';

/// Anonymized structural fixture from the user-supplied Phantom Liberty FLAC.
/// Preserves *all actual lead/background timestamps*, alternating [bg:] rows,
/// repeated <time> word boundaries, VORBIS_COMMENT block position and dual
/// lyric tags. No copyrighted lyrical text or audio is committed.
void main() {
  const leadTimes = <String>[
    '00:12.44', '00:24.012', '00:31.732', '00:38.296', '00:43.464',
    '00:55.033', '01:02.918', '01:09.337', '01:15.433', '01:23.055',
    '01:30.669', '01:38.672', '01:53.001', '02:04.784', '02:12.517',
    '02:18.646', '02:22.953', '02:27.80', '02:35.686', '02:43.154',
    '02:50.104', '02:55.942', '03:03.755', '03:11.332', '03:19.17',
    '03:33.491', '03:41.292', '03:49.128', '03:56.038', '04:05.63',
    '04:13.445', '04:21.202', '04:28.986', '04:36.663', '04:44.418',
    '04:52.122', '04:59.871', '05:14.207', '05:18.137', '05:25.929',
    '05:33.691',
  ];
  const vocalWindows = <(String, String)>[
    ('01:17.254', '01:21.736'), ('01:25.069', '01:30.069'),
    ('01:32.837', '01:38.029'), ('01:40.523', '01:45.475'),
    ('02:57.887', '03:02.73'), ('03:05.656', '03:10.844'),
    ('03:13.452', '03:18.287'), ('03:21.323', '03:26.022'),
    ('04:07.644', '04:12.345'), ('04:15.428', '04:20.385'),
    ('04:23.095', '04:28.381'), ('04:30.828', '04:36.071'),
    ('04:38.568', '04:43.42'), ('04:46.325', '04:51.269'),
    ('04:54.103', '04:59.004'), ('05:01.777', '05:06.70'),
  ];

  String anonymizedLyrics() {
    final service = LyricsService();
    final rows = <(int, String)>[];
    for (final time in leadTimes) {
      final ms = service.parseTimestamp(time)!.inMilliseconds;
      rows.add((ms, '[' + time + ']v1:<' + time + '>Lead <' +
          time + '>voice <' + time + '>'));
    }
    for (final (start, end) in vocalWindows) {
      final ms = service.parseTimestamp(start)!.inMilliseconds;
      rows.add((ms, '[bg:<' + start + '><' + start +
          '>Harmony <' + end + '><' + end + '>]'));
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return '[ti:Fixture]\n[ar:Fixture]\n[by:Fixture]\n\n' +
        rows.map((e) => e.$2).join('\n');
  }

  Uint8List vorbisBlock(String lyrics) {
    final bytes = BytesBuilder(copy: false);
    void le32(int n) => bytes.add([
      n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255,
    ]);
    final vendor = utf8.encode('Lavf62.12.102');
    le32(vendor.length);
    bytes.add(vendor);
    final entries = <String>[
      'major_brand=mp41', 'minor_version=0', 'TITLE=Fixture',
      'ALBUM=Fixture', 'ARTIST=Fixture', 'COMMENT=Test',
      'UNSYNCEDLYRICS=' + lyrics,
      'LYRICS=' + lyrics,
      ...List.generate(13, (i) => 'OTHER_TAG_' + i.toString() + '=Value'),
    ];
    expect(entries.length, 21);
    le32(entries.length);
    for (final entry in entries) {
      final value = utf8.encode(entry);
      le32(value.length);
      bytes.add(value);
    }
    return bytes.toBytes();
  }

  Uint8List flacBytes(String lyrics) {
    final comment = vorbisBlock(lyrics);
    final output = BytesBuilder(copy: false);
    output.add(ascii.encode('fLaC'));
    output.add([0, 0, 0, 34]);
    output.add(Uint8List(34)); // STREAMINFO
    output.add([
      4,
      (comment.length >> 16) & 255,
      (comment.length >> 8) & 255,
      comment.length & 255,
    ]);
    output.add(comment);
    output.add([0x81, 0, 0, 8]); // final padding block
    output.add(Uint8List(8));
    return output.toBytes();
  }

  test('actual 41+16 FLAC layout survives raw Vorbis binary decoding', () {
    final decoded = FlacVorbisLyricsReader.fromVorbisCommentBlock(
      vorbisBlock(anonymizedLyrics()),
    )!;
    expect(FlacVorbisLyricsReader.backgroundCount(decoded), 16);
    final parsed = LyricsService().parseLyricsText(decoded);
    expect(parsed.lines.length, 41);
    expect(LyricsService.supportingVocalCount(parsed), 16);
    final lead = parsed.lines.firstWhere(
      (l) => l.timestamp.inMilliseconds == 284418,
    );
    expect(lead.backgroundText, 'Harmony');
    expect(lead.backgroundWords!.first.start.inMilliseconds, 286325);
    expect(lead.backgroundWords!.last.end.inMilliseconds, 291269);
  });

  test('reads complete FLAC from disk, not platform metadata API', () async {
    final directory = await Directory.systemTemp.createTemp('lokal-flac-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = directory.path + Platform.pathSeparator + 'fixture.flac';
    await File(path).writeAsBytes(flacBytes(anonymizedLyrics()));
    final extracted = await FlacVorbisLyricsReader.readFile(path);
    expect(extracted, isNotNull);
    expect(FlacVorbisLyricsReader.backgroundCount(extracted), 16);
    expect(LyricsService.supportingVocalCount(
      LyricsService().parseLyricsText(extracted!),
    ), 16);
  });

  test('fullscreen renderer sees 16 voices from real FLAC tag structure', () {
    final payload = FlacVorbisLyricsReader.fromVorbisCommentBlock(
      vorbisBlock(anonymizedLyrics()),
    )!;
    final parsed = LyricsService().parseLyricsText(payload);
    final voices = flowingBackgroundVocalLines(parsed.lines);
    expect(voices, hasLength(16));
    final index = activeFlowingBackgroundVocalIndex(
      voices, const Duration(minutes: 4, seconds: 49),
    );
    expect(index, isNot(-1),
      reason: 'Fullscreen must display singer at 04:49 under the lead.');
    expect(voices[index].timestamp.inMilliseconds, 286325);
    expect(voices[index].words!.last.end.inMilliseconds, 291269);
    expect(
      activeFlowingBackgroundVocalIndex(
        voices, const Duration(milliseconds: 291269),
      ),
      -1,
      reason: 'The backing voice stops at its independently timed end.',
    );
  });

  // Anonymized structural fixture from Pump It.flac. That file stores
  // 126 lead rows and 41 [b]/[bw] backing events in LOKAL_LYRICS, while its
  // ordinary LYRICS field contains the backing only as inline parentheses.
  // Use the actual timing relationships; no audio or copyrighted lines.
  test('native LOKAL_LYRICS beats portable lead-only FLAC text', () {
    const native = '{"lokal":1,"sync":"syllable","language":"en","lines":['
      '{"t":15.902,"x":"Lead A","w":[["Lead",15.902,16.564,0]],'
      '"b":"Harmony A","bw":[["Harmony",16.732,17.660,0]]},'
      '{"t":17.669,"x":"Lead B","w":[["Lead",17.669,18.330,0]],'
      '"b":"Harmony B","bw":[["Harmony",18.334,19.216,0]]},'
      '{"t":35.223,"x":"Lead C","w":[["Lead",35.223,36.282,0]],'
      '"b":"Harmony C","bw":[["Harmony",36.421,36.739,0]]},'
      '{"t":36.711,"x":"Lead D","w":[["Lead",36.711,38.090,0]]}'
      ']}';
    const portable = '[00:15.90]Lead A (Harmony A)\\n[00:17.67]Lead B';
    final bytes = BytesBuilder(copy: false);
    void le32(int n) => bytes.add([n & 255, (n >> 8) & 255,
      (n >> 16) & 255, (n >> 24) & 255]);
    final vendor = utf8.encode('Fixture encoder');
    le32(vendor.length);
    bytes.add(vendor);
    final comments = ['LYRICS=$portable', 'LOKAL_LYRICS=$native'];
    le32(comments.length);
    for (final comment in comments) {
      final encoded = utf8.encode(comment);
      le32(encoded.length);
      bytes.add(encoded);
    }
    final extracted = FlacVorbisLyricsReader.fromVorbisCommentBlock(
      bytes.toBytes(),
    );
    expect(extracted, native);
    expect(FlacVorbisLyricsReader.backgroundCount(extracted), 3);
    final parsed = LyricsService().parseLyricsText(extracted!);
    expect(parsed.isSynchronized, isTrue);
    expect(parsed.lines, hasLength(4));
    expect(LyricsService.supportingVocalCount(parsed), 3);
    expect(parsed.lines[0].words!.last.end.inMilliseconds, 16564);
    expect(parsed.lines[0].backgroundWords!.last.end.inMilliseconds, 17660);
    expect(parsed.lines[2].backgroundWords!.last.end.inMilliseconds, 36739);
    expect(flowingBackgroundVocalLines(parsed.lines), hasLength(3));
  });

  test('independent vocal events cannot replace fullscreen lead timeline', () {
    const lead = LyricsLine(
      timestamp: Duration(seconds: 15),
      text: 'Lead vocalist',
    );
    const bg = LyricsLine(
      timestamp: Duration(seconds: 17),
      text: 'Backing vocalist',
      voice: 'bg',
      words: [
        LyricsWord(
          start: Duration(seconds: 17),
          end: Duration(seconds: 22),
          text: 'Backing vocalist',
        ),
      ],
    );
    final voices = flowingBackgroundVocalLines([lead, bg]);
    expect(voices, hasLength(1));
    expect(voices.single.text, 'Backing vocalist');
    expect(activeFlowingBackgroundVocalIndex(
      voices, const Duration(seconds: 20),
    ), 0);
  });

}
