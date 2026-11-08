import 'package:flick/features/player/widgets/full_player_visuals.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('reference full-player album palette', () {
    test('warm artwork produces a dark header and saturated lower half', () {
      final colors = FullPlayerVisuals.fromPalette(const [
        Color(0xFFB75D1B),
        Color(0xFF854A24),
        Color(0xFF26160F),
      ]);
      final top = HSLColor.fromColor(colors.top);
      final bottom = HSLColor.fromColor(colors.bottom);
      expect(
        colors.top.computeLuminance(),
        lessThan(colors.bottom.computeLuminance()),
      );
      expect(top.lightness, lessThan(.15));
      expect(bottom.saturation, greaterThan(.50));
      expect(colors.play.computeLuminance(), greaterThan(.5));
      expect(colors.play, isNot(const Color(0xFFC8FF57)));
    });

    test('cool artwork retains its own hue instead of using a red preset', () {
      final visuals = FullPlayerVisuals.fromPalette(const [
        Color(0xFF2168B9),
        Color(0xFF124E83),
      ]);
      final hue = HSLColor.fromColor(visuals.bottom).hue;
      expect(hue, greaterThan(175));
      expect(hue, lessThan(265));
    });

    test('previous/next blends resolved surface colors continuously', () {
      final warm = FullPlayerVisuals.fromPalette(const [
        Color(0xFFBB5B2C),
        Color(0xFF7A351E),
      ]);
      final cool = FullPlayerVisuals.fromPalette(const [
        Color(0xFF245BBA),
        Color(0xFF183D90),
      ]);
      final atStart = FullPlayerVisuals.lerp(warm, cool, 0);
      final atHalf = FullPlayerVisuals.lerp(warm, cool, .5);
      final atEnd = FullPlayerVisuals.lerp(warm, cool, 1);
      expect(atStart.top, warm.top);
      expect(atEnd.bottom, cool.bottom);
      expect(atHalf.top, Color.lerp(warm.top, cool.top, .5));
      expect(atHalf.bottom, Color.lerp(warm.bottom, cool.bottom, .5));
    });

    test('monochrome artwork remains monochrome', () {
      final visuals = FullPlayerVisuals.fromPalette(const [
        Color(0xFF777777),
        Color(0xFF242424),
      ]);
      expect(HSLColor.fromColor(visuals.bottom).saturation, closeTo(0, .001));
      expect(HSLColor.fromColor(visuals.play).saturation, closeTo(0, .001));
    });
  });

  testWidgets('transport is balanced and does not resize during play/pause', (
    tester,
  ) async {
    var playing = false;
    late StateSetter change;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    change = setState;
                    return PlayerTransportControls(
                      playing: playing,
                      compact: false,
                      lyricsProgress: 0,
                      accent: const Color(0xFFEBD4CB),
                      onAccent: Colors.black,
                      onPrevious: () {},
                      onNext: () {},
                      onPlayPause: () => setState(() => playing = !playing),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final playButton = find.byKey(const ValueKey('player-play-button'));
    final widthBefore = tester.getSize(playButton).width;
    expect(widthBefore, closeTo(124, 2));
    await tester.tap(playButton);
    await tester.pumpAndSettle();
    expect(tester.getSize(playButton).width, closeTo(widthBefore, .01));
    change(() => playing = false);
    await tester.pumpAndSettle();
    expect(tester.getSize(playButton).width, closeTo(widthBefore, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('transport remains operable on a narrow handset', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: PlayerTransportControls(
                  playing: true,
                  compact: true,
                  lyricsProgress: 0,
                  accent: const Color(0xFFEBD4CB),
                  onAccent: Colors.black,
                  onPrevious: () => pressed++,
                  onNext: () => pressed++,
                  onPlayPause: () => pressed++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.tap(find.byKey(const ValueKey('player-play-button')));
    expect(pressed, 3);
    expect(tester.takeException(), isNull);
  });
}
