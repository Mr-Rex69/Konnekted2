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

Song _song(String id, {Duration duration = const Duration(minutes: 3)}) => Song(
  id: id,
  title: 'Track $id',
  artist: 'Artist $id',
  duration: duration,
  fileType: 'FLAC',
);

void main() {
  test('Full Library browser is labelled Library and shows total duration', () {
    final page = lokalLibraryPage('songs') as LokalSongListPage;
    expect(page.title, 'Library');
    expect(page.showTotalDuration, isTrue);
    expect(page.preferencesKey, 'lokal.library.songs.song_browser_view.v1');
    final added = lokalLibraryPage('recentlyAdded') as LokalSongListPage;
    expect(added.title, 'Library');
    expect(added.showTotalDuration, isTrue);
    // The You tab's history navigation retains a distinct, truthful page.
    final history = lokalLibraryPage('recentlyPlayed') as LokalSongListPage;
    expect(history.title, 'Recently played');
  });

  testWidgets('Recently Added becomes Library; Recently Played remains intact', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final opened = <KonnektedDestination>[];
    final library = [
      _song('library', duration: const Duration(minutes: 65)),
      _song('library2', duration: const Duration(minutes: 5)),
    ];
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
    expect(find.byType(LokalNavRow), findsNWidgets(6));
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
    expect(find.descendant(
      of: libraryShelf,
      matching: find.text('Track library'),
    ), findsOneWidget);
    expect(find.descendant(
      of: libraryShelf,
      matching: find.text('Track library2'),
    ), findsOneWidget);
    final widget = tester.widget<KonnektedSongShelf>(libraryShelf);
    expect(widget.showTotalDuration, isTrue);
    expect(widget.summarySongs?.value?.length, library.length);
    expect(find.descendant(
      of: libraryShelf,
      matching: find.text('Track r1'),
    ), findsNothing);
    expect(find.text('2 songs · 1 hr 10 min'), findsOneWidget);
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
    expect(opened, [KonnektedDestination.recentlyAdded]);
    final playedShelf = find.byWidgetPredicate(
      (widget) => widget is KonnektedSongShelf &&
          widget.title == 'Recently played',
    );
    await tester.scrollUntilVisible(
      playedShelf,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final playedWidget = tester.widget<KonnektedSongShelf>(playedShelf);
    expect(playedWidget.showTotalDuration, isFalse);
    expect(playedWidget.summarySongs, isNull);
    expect(find.descendant(
      of: playedShelf, matching: find.text('Track r1'),
    ), findsOneWidget);
    expect(find.descendant(
      of: playedShelf, matching: find.text('Track r2'),
    ), findsOneWidget);
    await tester.tap(find.descendant(
      of: playedShelf, matching: find.text('See all'),
    ));
    expect(opened, [
      KonnektedDestination.recentlyAdded,
      KonnektedDestination.recentlyPlayed,
    ]);
    expect(tester.takeException(), isNull);
  });
}
