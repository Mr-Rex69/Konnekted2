import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/features/player/widgets/lyric_motion_line.dart';
import 'package:flick/features/player/widgets/player_panel_stage.dart';

void main() {
  testWidgets(
    'tablet square stage fills its pane and keeps queue/lyrics cover transitions',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1024, 768)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final (queue, lyrics) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]) {
        final compact = queue + lyrics > 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 620,
                height: 620,
                child: PlayerPanelStage(
                  artGap: 0,
                  infoReserve: compact ? 72 : 0,
                  queueProgress: AlwaysStoppedAnimation(queue),
                  lyricsProgress: AlwaysStoppedAnimation(lyrics),
                  queueOpen: queue > 0,
                  lyricsOpen: lyrics > 0,
                  artwork: (_, _, _) => const ColoredBox(
                    key: ValueKey('tablet-square-cover'),
                    color: Colors.blue,
                  ),
                  info: (_, _) => compact
                      ? const SizedBox(height: 44, child: Text('Recording'))
                      : const SizedBox.shrink(),
                  queue: const SizedBox.expand(),
                  lyrics: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        final size = tester.getSize(
          find.byKey(const ValueKey('tablet-square-cover')),
        );
        expect(size.width, closeTo(size.height, .01));
        expect(size.width, compact ? 52 : greaterThan(600));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'lyrics cover returns by tap or swipe up, without stealing list gestures',
    (tester) async {
      var returns = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 560,
              child: PlayerPanelStage(
                queueProgress: const AlwaysStoppedAnimation(0.0),
                lyricsProgress: const AlwaysStoppedAnimation(1.0),
                queueOpen: false,
                lyricsOpen: true,
                onLyricsCoverReturn: () => returns++,
                artwork: (_, _, _) => const ColoredBox(
                  key: ValueKey('return-cover'),
                  color: Colors.blue,
                ),
                info: (_, _) => const SizedBox(height: 44, child: Text('Song')),
                queue: const SizedBox(),
                lyrics: const ColoredBox(
                  key: ValueKey('lyrics-area'),
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );
      final cover = find.byKey(const ValueKey('return-cover'));
      await tester.tapAt(tester.getCenter(cover));
      expect(returns, 1);
      await tester.dragFrom(tester.getCenter(cover), const Offset(0, -90));
      expect(returns, 2);
      await tester.dragFrom(tester.getCenter(cover), const Offset(0, 90));
      expect(returns, 2);
      await tester.tap(find.byKey(const ValueKey('lyrics-area')));
      expect(returns, 2);
    },
  );
  testWidgets(
    'wrapped timed Japanese uses its measured paragraph height at large text scales',
    (tester) async {
      const text = '見覚えのある レインコート 黄昏の駅で 胸が震えた';
      const line = LyricsLine(
        timestamp: Duration.zero,
        text: text,
        words: [
          LyricsWord(
            start: Duration.zero,
            end: Duration(seconds: 3),
            text: text,
          ),
        ],
      );
      const style = TextStyle(
        fontSize: 34,
        height: 1.25,
        fontWeight: FontWeight.w700,
      );
      for (final scale in [1.0, 1.5]) {
        double? expected;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  width: 280,
                  child: Builder(
                    builder: (context) {
                      expected = LyricMotionLine.height(
                        context,
                        text,
                        style,
                        280,
                      );
                      return const LyricMotionLine(
                        key: ValueKey('line'),
                        line: line,
                        position: Duration(seconds: 1),
                        style: style,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('line'))).height,
          expected,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'one cover moves between queue and lyrics without growing or losing scroll',
    (tester) async {
      final q = ValueNotifier<double>(1), l = ValueNotifier<double>(0);
      addTearDown(q.dispose);
      addTearDown(l.dispose);
      Widget list(String name) => ListView(
        key: ValueKey(name),
        children: [
          for (var i = 0; i < 50; i++)
            SizedBox(height: 40, child: Text('$name $i')),
        ],
      );
      final queue = list('queue'), lyrics = list('lyrics');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 560,
              child: ValueListenableBuilder<double>(
                valueListenable: l,
                builder: (context, value, _) => PlayerPanelStage(
                  queueProgress: AlwaysStoppedAnimation(q.value),
                  lyricsProgress: AlwaysStoppedAnimation(value),
                  queueOpen: value == 0 && q.value > 0,
                  lyricsOpen: value > 0,
                  artwork: (context, side, progress) => const ColoredBox(
                    key: ValueKey('shared-cover'),
                    color: Colors.blue,
                  ),
                  info: (context, progress) => const SizedBox(
                    height: 44,
                    child: Text('Song title', key: ValueKey('shared-title')),
                  ),
                  queue: queue,
                  lyrics: lyrics,
                ),
              ),
            ),
          ),
        ),
      );
      ScrollableState scroll(String name) => tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.byType(Scrollable),
        ),
      );
      scroll('queue').position.jumpTo(160);
      final start = tester.getRect(find.byKey(const ValueKey('shared-cover')));
      expect(start.width, 52);
      var previousY = start.top;
      for (final t in [.1, .3, .5, .7, 1.0]) {
        l.value = t;
        await tester.pump();
        final rect = tester.getRect(find.byKey(const ValueKey('shared-cover')));
        expect(rect.width, 52); // Never returns via the large cover.
        expect(rect.top, greaterThan(previousY));
        previousY = rect.top;
        expect(find.byKey(const ValueKey('shared-cover')), findsOneWidget);
      }
      scroll('lyrics').position.jumpTo(200);
      for (final t in [.8, .4, .6, .2, 0.0]) {
        l.value = t;
        await tester.pump();
      }
      expect(scroll('queue').position.pixels, 160);
      expect(scroll('lyrics').position.pixels, 200);
      expect(tester.getRect(find.byKey(const ValueKey('shared-cover'))), start);
      q.value = 0;
      l.value = .01;
      await tester.pump();
      l.value = 0;
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('shared-cover'))).width,
        greaterThan(300),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
