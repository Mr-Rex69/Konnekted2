import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('artist portrait fills the top inset and opens its viewer on tap',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var artworkTaps = 0;
    var moreTaps = 0;
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 35),
          ),
          child: Scaffold(
            body: LokalDetailHeader(
              title: 'Artist with a portrait',
              artwork: const ColoredBox(
                key: ValueKey('portrait'),
                color: Colors.deepPurple,
                child: SizedBox.expand(),
              ),
              isArtist: true,
              background: Colors.black,
              onArtworkTap: () => artworkTaps++,
              onBack: () {},
              onMore: () => moreTaps++,
              onOnline: () {},
              onlineEnabled: false,
            ),
          ),
        ),
      )),
    );
    await tester.pump();

    // The photograph covers the entire hero, including the simulated Android
    // status-bar inset; the action buttons are separately inset by SafeArea.
    expect(tester.getTopLeft(find.byKey(const ValueKey('portrait'))).dy, 0);
    await tester.tapAt(const Offset(190, 210));
    await tester.pump();
    expect(artworkTaps, 1);
    expect(moreTaps, 0);

    // The overlay must not block header controls either.
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pump();
    expect(moreTaps, 1);
    expect(artworkTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artist portrait darkens gently until the very last edge',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: LokalDetailHeader(
            title: 'Artist',
            artwork: const ColoredBox(color: Colors.brown),
            isArtist: true,
            background: Colors.white,
            onArtworkTap: () {},
            onBack: () {},
            onMore: () {},
            onOnline: () {},
            onlineEnabled: false,
          ),
        ),
      )),
    );
    await tester.pump();
    final gradients = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(LokalDetailHeader),
        matching: find.byType(DecoratedBox),
      ),
    ).map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>();
    final scrim = gradients.singleWhere((g) => g.colors.length == 4);
    // The old scrim had an already 75%-opaque black stop at 63% of
    // portrait height, making the face and shoulders unnaturally dark.
    expect(scrim.stops, [0, .68, .93, 1]);
    expect(scrim.colors.first.a, lessThan(.15));
    expect(scrim.colors[2].a, lessThan(.20));
    expect(scrim.colors.last, Colors.black.withValues(alpha: .45));
    expect(tester.takeException(), isNull);
  });

  testWidgets('album uses the same full-bleed header as artist', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var artworkTaps = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: LokalDetailHeader(
              title: 'Album',
              artwork: const ColoredBox(color: Colors.red),
              isArtist: false,
              fixedArtwork: true,
              background: Colors.black,
              onArtworkTap: () => artworkTaps++,
              onBack: () {},
              onMore: () {},
              onOnline: () {},
              onlineEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final header = tester.widget<LokalDetailHeader>(
      find.byType(LokalDetailHeader),
    );
    expect(header.fixedArtwork, isTrue);
    expect(
      tester.getSize(find.byType(LokalDetailHeader)).height,
      closeTo(844 * .52, .01),
    );
    expect(tester.widget<Text>(find.text('Album')).style?.color, Colors.white);
    await tester.tapAt(const Offset(195, 235));
    expect(artworkTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album cover tap is preserved by the shared detail header',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: LokalDetailHeader(
            title: 'Album',
            artwork: const ColoredBox(color: Colors.red),
            isArtist: false,
            background: Colors.black,
            onArtworkTap: () => taps++,
            onBack: () {},
            onMore: () {},
            onOnline: () {},
            onlineEnabled: false,
          ),
        ),
      )),
    );
    await tester.pump();
    await tester.tapAt(const Offset(195, 230));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
