import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all three dock surfaces retain the same live glass optics',
      (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget dock({required bool collapsed}) => ProviderScope(
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: KonnektedDock(
                    selected: KonnektedTab.listen,
                    onSelect: (_) {},
                    miniPlayer: const SizedBox.expand(),
                    hasMiniPlayer: true,
                    collapsed: collapsed,
                  ),
                ),
              ),
            ),
          ),
        );

    void checkGlass(double expectedOpacity) {
      final glasses = tester.widgetList<LokalGlass>(
        find.byType(LokalGlass),
      ).toList();
      // Mini player, navigation capsule and separate Search button.
      expect(glasses, hasLength(3));
      for (final glass in glasses) {
        expect(glass.pronouncedRim, isTrue);
        expect(glass.lens?.profile, LokalLensProfile.squircle);
        expect(glass.liquidBlurRadius, 1.5);
        expect(glass.liquidTintOpacity, closeTo(expectedOpacity, .001));
      }
    }

    await tester.pumpWidget(dock(collapsed: false));
    await tester.pump();
    checkGlass(.20);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(dock(collapsed: true));
    await tester.pump();
    checkGlass(.28);
    expect(tester.takeException(), isNull);
  });
}
