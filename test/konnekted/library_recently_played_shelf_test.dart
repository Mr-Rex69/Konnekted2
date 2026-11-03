import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_destination.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/konnekted/konnekted_library.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/features/konnekted/library/lokal_library_pages.dart';
import 'package:flick/features/konnekted/library/lokal_song_browser.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Track $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

void main() {
  test('Full Library browser is labelled Library and shows total duration', () {
    final page = lokalLibraryPage('songs') as LokalSongListPage;
    expect(page.title, 'Library');
    expect(page.showTotalDuration, isTrue);
    expect(page.preferencesKey, 'lokal.library.songs.song_browser_view.v1');
    // The You tab's history navigation retains a distinct, truthful page.
    final history = lokalLibraryPage('recentlyPlayed') as LokalSongListPage;
    expect(history.title, 'Recently played');
  });

  testWidgets('Library shows full collection, subtitle and route below More', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final opened = <KonnektedDestination>[];
    final library = [_song('library'), _song('library2')];
    final history = [_song('r1'), _song('r2')];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          konnektedLibraryProvider.overrideWithValue(
            AsyncData(library),
          ),
          konnektedRecentSongsProvider.overrideWith(
            (ref) => Stream.value(history),
          ),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(body: KonnektedLibrary(onNavigate: opened.add)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The More group no longer includes a history row.
    await tester.scrollUntilVisible(
      find.text('More'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(LokalNavRow), findsNWidgets(4));
    expect(find.byIcon(Icons.history_rounded), findsNothing);

    final libraryShelf = find.byWidgetPredicate(
      (widget) =>
          widget is KonnektedSongShelf && widget.title == 'Library',
    );
    await tester.scrollUntilVisible(
      libraryShelf,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.descendant(
      of: libraryShelf,
      matching: find.text('Library'),
    ), findsOneWidget);
    expect(find.text('Track library'), findsOneWidget);
    expect(find.text('Track library2'), findsOneWidget);
    expect(find.text('Track r1'), findsNothing);
    expect(find.text('2 songs · 6 min'), findsOneWidget);
    final horizontalList = tester.widget<ListView>(
      find.descendant(of: libraryShelf, matching: find.byType(ListView)),
    );
    expect(horizontalList.scrollDirection, Axis.horizontal);

    // The shell has already reserved the dock height in MediaQuery. The
    // Library must not add the old 150px spacer on top of that clearance.
    await tester.scrollUntilVisible(
      find.byKey(const Key('library-bottom-clearance')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    final clearance = find.byKey(const Key('library-bottom-clearance'));
    final bottomInsets = MediaQuery.paddingOf(tester.element(clearance)).bottom;
    expect(
      tester.widget<SizedBox>(clearance).height,
      12 + bottomInsets,
    );

    await tester.scrollUntilVisible(
      libraryShelf,
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: libraryShelf, matching: find.text('See all')),
    );
    expect(opened, [KonnektedDestination.songs]);
    expect(tester.takeException(), isNull);
  });
}
