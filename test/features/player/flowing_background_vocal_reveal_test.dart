import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/flowing_background_vocals.dart';

void main() {
  test('a supporting vocal fades and grows into the currently playing line', () {
    final reveal = FlowingBackgroundVocalReveal();
    expect(reveal.visibleIndex, -1);
    expect(reveal.value, 0);

    reveal.advance(0, 1 / 60);
    expect(reveal.visibleIndex, 0);
    expect(reveal.value, greaterThan(0));
    expect(reveal.value, lessThan(1));

    for (var i = 0; i < 40; i++) {
      reveal.advance(0, 1 / 60);
    }
    expect(reveal.visibleIndex, 0);
    expect(reveal.value, closeTo(1, .02));
  });

  test('backing lyrics fade out before releasing their layout height', () {
    final reveal = FlowingBackgroundVocalReveal();
    reveal.advance(0, 0, reduceMotion: true);
    reveal.advance(-1, 1 / 60);
    expect(reveal.visibleIndex, 0,
        reason: 'Keep the outgoing line mounted during the exit');
    expect(reveal.value, greaterThan(0));
    expect(reveal.value, lessThan(1));
    for (var i = 0; i < 50; i++) {
      reveal.advance(-1, 1 / 60);
    }
    expect(reveal.visibleIndex, -1);
    expect(reveal.value, 0);
  });

  test('new voice waits until the previous one fades out', () {
    final reveal = FlowingBackgroundVocalReveal();
    reveal.advance(0, 0, reduceMotion: true);
    reveal.advance(1, 1 / 60);
    expect(reveal.visibleIndex, 0);
    expect(reveal.value, inInclusiveRange(0, 1));
    for (var i = 0; i < 55; i++) {
      reveal.advance(1, 1 / 60);
    }
    expect(reveal.visibleIndex, 1);
    expect(reveal.value, greaterThan(0));
  });

  test('rapid seek reversals keep the current opacity instead of snapping', () {
    final reveal = FlowingBackgroundVocalReveal();
    reveal.advance(0, .025);
    final before = reveal.value;
    reveal.advance(-1, .015);
    expect(reveal.value, lessThan(before));
    final duringExit = reveal.value;
    reveal.advance(0, .015);
    expect(reveal.visibleIndex, 0);
    expect(reveal.value, greaterThan(duringExit));
  });

  test('system reduced motion shows and removes vocals immediately', () {
    final reveal = FlowingBackgroundVocalReveal();
    reveal.advance(3, .016, reduceMotion: true);
    expect(reveal.visibleIndex, 3);
    expect(reveal.value, 1);
    reveal.advance(-1, .016, reduceMotion: true);
    expect(reveal.visibleIndex, -1);
    expect(reveal.value, 0);
  });
}
