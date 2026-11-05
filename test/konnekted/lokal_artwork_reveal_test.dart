import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/features/konnekted/library/lokal_artwork_reveal.dart';

void main() {
  Widget page(String identity, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        backgroundColor: const Color(0xFF101015),
        body: Center(
          child: SizedBox.square(
            dimension: 200,
            child: LokalArtworkReveal(
              identity: identity,
              child: ColoredBox(
                color: identity == 'cover'
                    ? const Color(0xFFE0B528)
                    : const Color(0xFF1F3855),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('replacing a late cover preserves the previous image briefly', (
    tester,
  ) async {
    await tester.pumpWidget(page('placeholder'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('cover'));
    await tester.pump(const Duration(milliseconds: 80));

    final stage = find.byType(LokalArtworkReveal);
    expect(
      find.descendant(
        of: stage,
        matching: find.byKey(const ValueKey('placeholder')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: stage,
        matching: find.byKey(const ValueKey('cover')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: stage,
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
      reason: 'Only the artwork should crossfade, never the full route',
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
  });

  testWidgets('OS reduced motion swaps artwork without retaining a fade', (
    tester,
  ) async {
    await tester.pumpWidget(page('placeholder', reduceMotion: true));
    await tester.pumpWidget(page('cover', reduceMotion: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
  });

  testWidgets('unchanged artwork identity does not trigger a new fade', (
    tester,
  ) async {
    await tester.pumpWidget(page('cover'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('cover'));
    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
  });
}
