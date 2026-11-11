import 'dart:io';
import 'dart:ui' as ui;

import 'package:flick/features/player/widgets/full_player_identity_layout.dart';
import 'package:flick/features/player/widgets/karaoke_lyric_line.dart';
import 'package:flick/features/player/widgets/lokal_player_columns.dart';
import 'package:flick/features/player/widgets/lyric_motion_line.dart';
import 'package:flick/features/player/widgets/player_lyric_style.dart';
import 'package:flick/features/player/widgets/player_video_frame.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends Fake implements PlayerService {
  @override
  final positionNotifier = ValueNotifier(const Duration(milliseconds: 500));
  @override
  final isPlayingNotifier = ValueNotifier(false);
  @override
  final playbackSpeedNotifier = ValueNotifier(1.0);
}

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('GoogleSansFlex', 'assets/fonts/GoogleSansFlex-Bold.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  testWidgets(
    'tablet player follows mobile portrait and split landscape in both cover modes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final fillCover in [false, true]) {
          for (final size in [
            const Size(768, 1024),
            const Size(1024, 768),
            const Size(900, 500),
          ]) {
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData.dark().copyWith(
                  platform: platform,
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'GoogleSansFlex',
                  ),
                ),
                home: RepaintBoundary(
                  key: capture,
                  child: Scaffold(
                    backgroundColor: const Color(0xFF171921),
                    body: LokalPlayerColumns(
                      preferColumns: true,
                      fillCover: fillCover,
                      header: const SizedBox(height: 48),
                      stage: const PlayerVideoFrame(
                        child: ColoredBox(
                          key: ValueKey('video'),
                          color: Color(0xFF577673),
                          child: Center(
                            child: Icon(Icons.play_circle_outline, size: 72),
                          ),
                        ),
                      ),
                      controls: LokalPlayerControls(
                        compact: size.height < 600,
                        heading: const Text(
                          'NOW PLAYING',
                          textAlign: TextAlign.center,
                        ),
                        identity: const FullPlayerIdentityLayout(
                          key: ValueKey('identity'),
                          titleFontSize: 29,
                          titleToArtistGap: 3,
                          title: Text(
                            'Northern Lights',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          artist: Text('The Quiet Hours'),
                          trailing: [Text('LOSSLESS')],
                        ),
                        timeline: const Slider(
                          key: ValueKey('timeline'),
                          value: .4,
                          onChanged: null,
                        ),
                        transport: const Row(
                          key: ValueKey('transport'),
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Icon(Icons.shuffle),
                            Icon(Icons.skip_previous),
                            Icon(Icons.play_circle, size: 44),
                            Icon(Icons.skip_next),
                            Icon(Icons.repeat),
                          ],
                        ),
                        options: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Icon(Icons.favorite_border),
                            Icon(Icons.queue_music),
                            Icon(Icons.lyrics_outlined),
                          ],
                        ),
                        footer: const Text(
                          'Audio · Lossless',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final video = tester.getRect(find.byKey(const ValueKey('video')));
            final identity = tester.getRect(
              find.byKey(const ValueKey('identity')),
            );
            final timeline = tester.getRect(
              find.byKey(const ValueKey('timeline')),
            );
            final transport = tester.getRect(
              find.byKey(const ValueKey('transport')),
            );
            expect(video.width / video.height, closeTo(16 / 9, .01));
            if (size.width > size.height) {
              expect(identity.left, greaterThan(video.right));
            } else {
              expect(identity.top, greaterThanOrEqualTo(video.bottom));
            }
            expect(timeline.top, greaterThan(identity.bottom));
            expect(transport.top, greaterThan(timeline.bottom));
            expect(tester.takeException(), isNull);
            final directory = Platform.environment['LOKAL_TEST_SCREENSHOT_DIR'];
            if (directory != null &&
                size.width == 1024 &&
                platform == TargetPlatform.iOS) {
              await tester.runAsync(() async {
                final boundary =
                    capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(directory).create(recursive: true);
                await File(
                  '$directory/tablet-${fillCover ? 'fullcover' : 'standard'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
      }
    },
  );

  testWidgets(
    'shared syllable paragraphs center short lines within the panel',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final alignment in [
        TextAlign.left,
        TextAlign.center,
        TextAlign.right,
      ]) {
        final painter = LyricMotionLine.layout(
          context,
          'Hello',
          playerLyricStyle,
          320,
          align: alignment,
        );
        final box = painter
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 5),
            )
            .single;
        expect(painter.width, 320);
        if (alignment == TextAlign.center)
          expect((box.left + box.right) / 2, closeTo(160, .1));
        if (alignment == TextAlign.left) expect(box.left, closeTo(0, .1));
        if (alignment == TextAlign.right) expect(box.right, closeTo(320, .1));
        painter.dispose();
      }
    },
  );

  testWidgets(
    'sidebar syllables resolve the same end windows as full-player lyrics',
    (tester) async {
      final service = LyricsService();
      final lyrics = service.parseLyricsText(
        '[00:00.00]<00:00.00>Hello <00:01.00>world\n[00:02.00]Next line',
      );
      final originalEnd = lyrics.lines.first.words!.first.end;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: KaraokeLyricLine(
                playerService: _Player(),
                lyricsService: service,
                lyrics: lyrics,
                lineIndex: 0,
                textAlign: TextAlign.center,
                style: playerLyricStyle,
                sungColor: Colors.white,
                unsungColor: Colors.white30,
              ),
            ),
          ),
        ),
      );
      final rendered = tester.widget<LyricMotionLine>(
        find.byType(LyricMotionLine),
      );
      final expected = service.playbackLines(lyrics).first;
      expect(
        rendered.line.words!.map((word) => word.end),
        expected.words!.map((word) => word.end),
      );
      expect(
        rendered.line.words!.first.end,
        greaterThan(rendered.line.words!.first.start),
      );
      expect(rendered.style, playerLyricStyle);
      expect(rendered.lightweight, isFalse);
      expect(lyrics.lines.first.words!.first.end, originalEnd);
    },
  );
}
