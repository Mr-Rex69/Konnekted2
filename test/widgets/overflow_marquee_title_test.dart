import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/widgets/common/marquee_widget.dart';
import 'package:flick/widgets/common/overflow_marquee_title.dart';
import 'package:flick/models/mini_player_config.dart';

void main() {
  Widget preview(
    String title, {
    bool reducedMotion = false,
    double width = 170,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: OverflowMarqueeTitle(
              title: title,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('long player titles scroll without an ellipsis', (tester) async {
    await tester.pumpWidget(
      preview('A Very Long Song Title That Needs To Move Horizontally'),
    );
    await tester.pump();
    expect(find.byType(MarqueeWidget), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('short titles do not animate', (tester) async {
    await tester.pumpWidget(preview('Short Title', width: 240));
    await tester.pump();
    expect(find.byType(MarqueeWidget), findsNothing);
    expect(find.text('Short Title'), findsOneWidget);
  });

  testWidgets('reduced-motion settings disable title animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview(
        'A Very Long Song Title That Needs To Move Horizontally',
        reducedMotion: true,
      ),
    );
    await tester.pump();
    expect(find.byType(MarqueeWidget), findsNothing);
  });

  test(
    'mini player defaults to scrolling titles but respects truncate choice',
    () {
      expect(
        MiniPlayerConfig.defaultConfig.titleMode,
        MiniPlayerTitleMode.scroll,
      );
      expect(
        MiniPlayerConfig.fromJson(const {}).titleMode,
        MiniPlayerTitleMode.scroll,
      );
      expect(
        MiniPlayerConfig.fromJson(const {'titleMode': 'truncate'}).titleMode,
        MiniPlayerTitleMode.truncate,
      );
    },
  );
}
