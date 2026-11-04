import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mini = Rect.fromLTWH(18, 710, 42, 42);
  const expanded = Rect.fromLTWH(0, 110, 400, 400);

  test('cover takes a shallow curved route to the real mini-player', () {
    expect(LokalArtworkFlight.rect(mini, expanded, 0), mini);
    expect(LokalArtworkFlight.rect(mini, expanded, 1), expanded);
    expect(LokalArtworkFlight.rect(mini, expanded, -1), mini);
    expect(LokalArtworkFlight.rect(mini, expanded, 2), expanded);

    // Bezier trajectory: the artwork first rises away from the mini, then
    // travels toward the full player's centre. No sideways mid-flight hump.
    const progress = .25;
    final direct = Rect.lerp(mini, expanded, progress)!;
    final curved = LokalArtworkFlight.rect(mini, expanded, progress);
    expect(curved.center.dx, lessThan(direct.center.dx - 10));
    expect(curved.center.dy, greaterThan(direct.center.dy + 5));
    expect(curved.size, direct.size,
        reason: 'Only trajectory bends: cover size and crop must not squash');
  });

  test('curved return is actually visible across a normal phone cover flight', () {
    final middle = LokalArtworkFlight.rect(mini, expanded, .5);
    final directMiddle = Rect.lerp(mini, expanded, .5)!;
    final late = LokalArtworkFlight.rect(mini, expanded, .75);
    final directLate = Rect.lerp(mini, expanded, .75)!;
    expect(directMiddle.center.dy - middle.center.dy, greaterThan(7));
    expect(late.center.dx - directLate.center.dx, greaterThan(10),
        reason: 'The arc changes its horizontal tangent during the flight');
    expect(middle.size, directMiddle.size);
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

  test('curve lands tangentially without final-frame snap', () {
    for (final t in [0.001, .999]) {
      final curved = LokalArtworkFlight.rect(mini, expanded, t);
      final anchor = t < .5 ? mini.center : expanded.center;
      // Ends are vertically tangent: horizontal offset decays quadratically.
      expect((curved.center.dx - anchor.dx).abs(), lessThan(.01));
      expect((curved.center.dy - anchor.dy).abs(), lessThan(1));
    }
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
}
