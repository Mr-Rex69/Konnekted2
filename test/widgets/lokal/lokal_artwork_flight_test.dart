import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mini = Rect.fromLTWH(18, 710, 42, 42);
  const expanded = Rect.fromLTWH(0, 110, 400, 400);

  test('J-shaped return dips below the mini-player before curving upward', () {
    expect(LokalArtworkFlight.rect(mini, expanded, 0), mini);
    expect(LokalArtworkFlight.rect(mini, expanded, 1), expanded);
    expect(LokalArtworkFlight.rect(mini, expanded, -1), mini);
    expect(LokalArtworkFlight.rect(mini, expanded, 2), expanded);

    // During a close, descending artwork retains its horizontal position
    // initially, then bends left and briefly passes BELOW its dock target.
    final early = LokalArtworkFlight.rect(mini, expanded, .85);
    final dip = LokalArtworkFlight.rect(mini, expanded, .2);
    final recovery = LokalArtworkFlight.rect(mini, expanded, .05);
    expect(early.center.dx, greaterThan(dip.center.dx + 100));
    expect(dip.center.dy, greaterThan(mini.center.dy + 20));
    expect(recovery.center.dy, greaterThan(mini.center.dy + 10));
    expect(recovery.center.dy, lessThan(dip.center.dy),
        reason: 'Cover must rise from below its destination to dock');

    // It curves to the mini from the right, rather than executing the old
    // centred horizontal sine hump or moving the whole player sheet.
    expect(dip.center.dx, greaterThan(mini.center.dx));
    expect(dip.center.dx, lessThan(early.center.dx));
    for (final progress in [.01, .2, .5, .75, .99]) {
      expect(
        LokalArtworkFlight.rect(mini, expanded, progress).size,
        Rect.lerp(mini, expanded, progress)!.size,
        reason: 'Only the cover centre curves; size/crop never squashes',
      );
    }
  });

  test('full-size and Canvas covers use the same J with exact endpoint landing', () {
    const wideMini = Rect.fromLTWH(18, 710, 52, 52);
    for (final full in [
      const Rect.fromLTWH(0, 0, 400, 480),
      const Rect.fromLTWH(0, 0, 400, 800),
    ]) {
      final dip = LokalArtworkFlight.rect(wideMini, full, .15, sheetTravel: 700);
      expect(dip.center.dy, greaterThan(wideMini.center.dy + 20));
      expect(dip.bottom, greaterThan(wideMini.bottom),
          reason: 'The return must visibly travel below its final position');
      expect(LokalArtworkFlight.rect(wideMini, full, 0), wideMini);
      expect(LokalArtworkFlight.rect(wideMini, full, 1), full);
    }
  });

  test('temporary GlobalKey detachment does not cancel the active morph', () {
    Rect? live = mini;
    final source = LokalArtworkSource(() => live);
    expect(source.current(), mini);
    live = null; // Source hero temporarily moves into an Overlay.
    expect(source.current(), mini);
    const moved = Rect.fromLTWH(28, 690, 42, 42);
    live = moved; // Mini moves with the dock as the tab bar collapses.
    expect(source.current(), moved);
    live = null;
    expect(source.current(), moved);
  });

  test('J curve approaches the mini from below with continuous landing', () {
    final dock = mini.center;
    final nearMini = LokalArtworkFlight.rect(mini, expanded, .001);
    expect(nearMini.center.dy, greaterThan(dock.dy));
    expect((nearMini.center - dock).distance, lessThan(1));
    expect(nearMini.size, Rect.lerp(mini, expanded, .001)!.size);

    final nearFull = LokalArtworkFlight.rect(mini, expanded, .999);
    expect((nearFull.center - expanded.center).distance, lessThan(2));
    expect(LokalArtworkFlight.rect(mini, expanded, 0), mini);
    expect(LokalArtworkFlight.rect(mini, expanded, 1), expanded);
  });

  test('closing and opening follow the same arc in opposite directions', () {
    final opening = LokalArtworkRectTween(begin: mini, end: expanded);
    final closing = LokalArtworkRectTween(begin: expanded, end: mini);
    for (final t in [0.0, .15, .25, .5, .75, .9, 1.0]) {
      final outgoing = opening.lerp(t)!;
      final returning = closing.lerp(1 - t)!;
      expect(returning.left, closeTo(outgoing.left, 1e-9));
      expect(returning.top, closeTo(outgoing.top, 1e-9));
      expect(returning.width, closeTo(outgoing.width, 1e-9));
      expect(returning.height, closeTo(outgoing.height, 1e-9));
    }
  });

  test('almost vertically aligned mini and full art stays centred', () {
    const below = Rect.fromLTWH(178, 710, 42, 42);
    final curved = LokalArtworkFlight.rect(below, expanded, .5);
    final direct = Rect.lerp(below, expanded, .5)!;
    expect((curved.center.dx - direct.center.dx).abs(), lessThan(3));
  });
  test('the J dip scales with sheet travel and remains bounded', () {
    final longer = LokalArtworkFlight.rect(
      mini, expanded, .2, sheetTravel: 700,
    );
    final shorter = LokalArtworkFlight.rect(
      mini, expanded, .2, sheetTravel: 100,
    );
    expect(longer.center.dy, greaterThan(shorter.center.dy + 25));
    expect(longer.center.dy, greaterThan(mini.center.dy));
    expect(shorter.size, longer.size);

    // No inverted J when the mini artwork is *above* its expanded target.
    const upperMini = Rect.fromLTWH(20, 0, 48, 48);
    const upperFull = Rect.fromLTWH(0, 150, 400, 400);
    final direct = Rect.lerp(upperMini, upperFull, .5)!;
    expect(LokalArtworkFlight.rect(upperMini, upperFull, .5), direct);
  });


}
