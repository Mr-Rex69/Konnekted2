import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/full_player_seek_bar.dart';
import 'package:flick/models/progress_bar_style.dart';

void main() {
  for (final style in ProgressBarStyle.values) {
    for (final rtl in [false, true]) {
      testWidgets(
        '$style seeks and exposes an adjustable timeline (RTL $rtl)',
        (tester) async {
          final changes = <double>[];
          final commits = <double>[];
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: SizedBox(
                      width: 320,
                      child: FullPlayerSeekBar(
                        style: style,
                        value: .25,
                        peaks: const [.1, .5, 1, .2, .7, .3],
                        onChanged: changes.add,
                        onChangeEnd: commits.add,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.getSize(find.byType(FullPlayerSeekBar)).height, 48);
          await tester.pumpAndSettle();
          final node = tester.getSemantics(find.byType(Slider));

          expect(
            node
                .debugListChildrenInOrder(
                  DebugSemanticsDumpOrder.traversalOrder,
                )
                .any(
                  (child) => child.getSemanticsData().hasAction(
                    SemanticsAction.increase,
                  ),
                ),
            isTrue,
          );
          final rect = tester.getRect(find.byType(Slider));
          await tester.tapAt(
            Offset(rect.left + rect.width * (rtl ? .2 : .8), rect.center.dy),
          );
          await tester.pumpAndSettle();
          expect(changes.last, greaterThan(.7));
          expect(commits, hasLength(1));
          expect(commits.single, changes.last);
          changes.clear();
          commits.clear();
          final gesture = await tester.startGesture(rect.center);
          await gesture.moveBy(Offset(rtl ? -70 : 70, 0));
          await tester.pump();
          expect(changes, isNotEmpty);
          expect(commits, isEmpty);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(commits, hasLength(1));
          expect(commits.single, changes.last);

          semantics.dispose();
        },
      );
    }
    testWidgets('$style disables unknown timing without changing layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: FullPlayerSeekBar(style: style, value: 0, onChanged: null),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(FullPlayerSeekBar));
      await tester.tapAt(rect.center);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(rect.height, 48);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('waveform accepts missing, silent and invalid caches', (
    tester,
  ) async {
    for (final peaks in <List<double>?>[
      null,
      [],
      [0, 0],
      [double.nan, .8, double.infinity],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: FullPlayerSeekBar(
                style: ProgressBarStyle.waveform,
                value: .5,
                peaks: peaks,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
