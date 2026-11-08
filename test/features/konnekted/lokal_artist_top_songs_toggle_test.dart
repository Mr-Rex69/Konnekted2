import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';

void main() {
  testWidgets('artist Top songs action toggles See all and Hide', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              final tracks = ['One', 'Two', 'Three', 'Four', 'Five', 'Six'];
              return Column(
                children: [
                  LokalSectionTitle(
                    title: 'Top songs',
                    onSeeAll: () => setState(() => expanded = !expanded),
                    actionLabel: expanded ? 'Hide' : null,
                  ),
                  for (final title in expanded ? tracks : tracks.take(5))
                    Text(title),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);
    expect(find.text('Six'), findsNothing);
    expect(find.bySemanticsLabel('See all Top songs'), findsOneWidget);

    await tester.tap(find.text('See all'));
    await tester.pump();

    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Six'), findsOneWidget);
    final hide = find.bySemanticsLabel('Hide Top songs');
    expect(hide, findsOneWidget);
    expect(tester.getSemantics(hide).hasFlag(SemanticsFlag.isButton), isTrue);

    await tester.tap(find.text('Hide'));
    await tester.pump();

    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);
    expect(find.text('Six'), findsNothing);
    expect(find.bySemanticsLabel('See all Top songs'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sections without a toggle do not show See all', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: const Scaffold(body: LokalSectionTitle(title: 'Songs')),
      ),
    );
    expect(find.text('See all'), findsNothing);
    expect(find.text('Hide'), findsNothing);
  });
}
