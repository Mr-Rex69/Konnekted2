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

    const progress = .5;
    final direct = Rect.lerp(mini, expanded, progress)!;
    final curved = LokalArtworkFlight.rect(mini, expanded, progress);
    expect(curved.center.dx, greaterThan(direct.center.dx + 8));
    expect(curved.center.dy, lessThan(direct.center.dy - 5));
    expect(curved.size, direct.size,
        reason: 'Only trajectory bends: cover size and crop must not squash');
  });

  test('curve lands tangentially without final-frame snap', () {
    for (final t in [0.001, 0.01, .99, .999]) {
      final curved = LokalArtworkFlight.rect(mini, expanded, t);
      final direct = Rect.lerp(mini, expanded, t)!;
      expect((curved.center - direct.center).distance, lessThan(.04),
          reason: 'Arc correction fades smoothly at p=$t');
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
