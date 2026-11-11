import 'dart:io';
import 'dart:ui' as ui;

import 'package:flick/core/theme/app_theme.dart';
import 'package:flick/features/player/widgets/full_player_seek_bar.dart';
import 'package:flick/features/player/widgets/waveform_envelope.dart';
import 'package:flick/features/player/widgets/waveform_preview_peaks.dart';
import 'package:flick/models/progress_bar_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final rtl in [false, true]) {
    test(
      'filled envelope preserves silence and moves its played edge (RTL $rtl)',
      () async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        paintWaveformEnvelope(
          canvas,
          const Rect.fromLTWH(0, 0, 600, 80),
          peaks: [.8, .8, 0, 0, .8, .8],
          progress: .25,
          rtl: rtl,
          active: const Color(0xFF00FF00),
          inactive: const Color(0xFFFF0000),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(600, 80);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int channel(int x, int y, int c) =>
            bytes.getUint8((y * 600 + x) * 4 + c);
        final played = rtl ? 560 : 40, upcoming = rtl ? 40 : 560;
        expect(
          channel(played, 20, 1),
          greaterThan(200),
          reason: 'played body is filled',
        );
        expect(
          channel(played, 60, 1),
          greaterThan(200),
          reason: 'lower half mirrors the recording',
        );
        expect(
          channel(upcoming, 20, 0),
          greaterThan(200),
          reason: 'remaining body keeps its own color',
        );
        expect(
          channel(300, 15, 3),
          0,
          reason: 'silence must not become random peaks',
        );
        expect(
          channel(300, 39, 3),
          greaterThan(0),
          reason: 'quiet sections retain a timeline',
        );
        image.dispose();
        picture.dispose();
      },
    );
  }

  testWidgets('settings envelope uses the same seek control as the player', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: const Color(0xFF141418),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: SizedBox(
                    width: 360,
                    child: FullPlayerSeekBar(
                      style: ProgressBarStyle.waveform,
                      value: .55,
                      peaks: waveformPreviewPeaks,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FullPlayerSeekBar)).height, 48);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 3);
      final output = Platform.environment['WAVEFORM_PREVIEW_PATH'];
      if (output != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(png!.buffer.asUint8List());
      }
      image.dispose();
    });
  });
}
