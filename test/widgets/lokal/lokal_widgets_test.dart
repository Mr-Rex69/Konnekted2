import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/appearance/lokal_appearance_screen.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';

Widget _app(Widget child) => ProviderScope(
  child: Consumer(
    builder: (context, ref, _) => MaterialApp(
      theme: LokalTheme.build(ref.watch(lokalAppearanceProvider).tokens),
      home: child,
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('glass blurs, and turns solid in performance mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Center(
            child: LokalGlass(child: SizedBox(width: 80, height: 40)),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);

    final element = tester.element(find.byType(LokalGlass));
    await ProviderScope.containerOf(element)
        .read(lokalAppearanceProvider.notifier)
        .setPerformanceMode(true);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('static glass cards retain material but never sample the backdrop',
      (tester) async {
    await tester.pumpWidget(
      _app(const Scaffold(
        body: Center(
          child: LokalGlass(
            staticSurface: true,
            child: SizedBox(width: 160, height: 80),
          ),
        ),
      )),
    );
    final card = tester.widget<LokalGlass>(find.byType(LokalGlass));
    expect(card.staticSurface, isTrue);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(DecoratedBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo sticker takes the accent', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: LokalLogo(size: 40))));
    Color? sticker() => tester
        .widgetList<Image>(find.byType(Image))
        .firstWhere((image) => image.color != null)
        .color;
    expect(sticker(), LokalTokens.resolve(LokalThemeId.dark).accent);

    final element = tester.element(find.byType(LokalLogo));
    await ProviderScope.containerOf(element)
        .read(lokalAppearanceProvider.notifier)
        .setAccent(LokalAccent.pink);
    await tester.pumpAndSettle();
    expect(sticker(), LokalAccent.pink.value);
  });

  testWidgets('Appearance screen switches theme and accent', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const LokalAppearanceScreen()));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LokalAppearanceScreen)),
    );

    await tester.tap(find.bySemanticsLabel('Ocean theme'));
    await tester.pumpAndSettle();
    expect(container.read(lokalAppearanceProvider).theme, LokalThemeId.ocean);
    expect(
      Theme.of(tester.element(find.byType(LokalAppearanceScreen)))
          .extension<LokalTokens>()!
          .bg,
      LokalTokens.resolve(LokalThemeId.ocean).bg,
    );

    await tester.ensureVisible(find.bySemanticsLabel('Pink accent'));
    await tester.tap(find.bySemanticsLabel('Pink accent'));
    await tester.pumpAndSettle();
    expect(container.read(lokalAppearanceProvider).accent, LokalAccent.pink);
  });
}
