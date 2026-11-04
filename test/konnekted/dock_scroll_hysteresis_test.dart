import 'package:flick/features/konnekted/konnekted_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jittering small scroll deltas cannot repeatedly reverse dock', () {
    final gate = DockScrollHysteresis(threshold: 24);
    var collapsed = false;

    for (final delta in [4.0, -3, 7, -6, 8, -4, 9, -5]) {
      final change = gate.push(delta, collapsed: collapsed);
      expect(change, isNull,
          reason: 'Tiny reversing motions should not flip the glass spring');
    }
    expect(collapsed, isFalse);

    for (final delta in [9.0, 10, 5]) {
      collapsed = gate.push(delta, collapsed: collapsed) ?? collapsed;
    }
    expect(collapsed, isTrue);
    // An already-collapsed direction does not queue a second event.
    expect(gate.push(40, collapsed: collapsed), isNull);

    for (final delta in [-7.0, -8, -9]) {
      collapsed = gate.push(delta, collapsed: collapsed) ?? collapsed;
    }
    expect(collapsed, isFalse);
  });

  test('an intentional reversal requires its own accumulated distance', () {
    final gate = DockScrollHysteresis(threshold: 24);
    expect(gate.push(20, collapsed: false), isNull);
    expect(gate.push(-12, collapsed: false), isNull);
    expect(gate.push(12, collapsed: false), isNull);
    expect(gate.push(11, collapsed: false), isNull);
    expect(gate.push(1, collapsed: false), isTrue);
  });

  test('end-of-gesture clears partial scroll intent', () {
    final gate = DockScrollHysteresis(threshold: 24);
    expect(gate.push(18, collapsed: false), isNull);
    gate.reset();
    expect(gate.push(10, collapsed: false), isNull);
    expect(gate.push(14, collapsed: false), isTrue);
    expect(gate.push(double.nan, collapsed: false), isNull);
  });
}
