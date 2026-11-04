import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('liquid lens cannot produce multi-pixel rainbow fringes', () {
    final shader = File('shaders/lokal_glass_lens.frag').readAsStringSync();
    expect(shader, contains('min(1.0, 0.6 / fringe)'));
    expect(shader, contains('clamp(redStraight, 0.0, 1.0) * centre.a'));
    expect(shader, contains('clamp(blueStraight, 0.0, 1.0) * centre.a'));
    expect(shader, contains('centre.g,'));
    // The old seven-spectrum samples generated obvious yellow/red/cyan edges.
    expect(shader, isNot(contains('vec4 purple = sampleAt')));
    expect(shader, isNot(contains('vec4 orange = sampleAt')));
  });
}
