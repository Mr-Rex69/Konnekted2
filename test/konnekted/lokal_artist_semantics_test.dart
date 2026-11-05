import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_albums_artists.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('artist portraits and cover placeholders have equal diameter',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const song = Song(
      id: 'artist-cover',
      title: 'Track',
      artist: 'Artist With Tracks',
      duration: Duration(minutes: 3),
      fileType: 'FLAC',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lokalArtistsProvider.overrideWithValue(const AsyncData([
            LokalArtist('Artist With Tracks', [song]),
            LokalArtist('Artist Without Tracks', []),
          ])),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: const LokalArtistsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fallbackArt = tester.widget<KonnektedArtwork>(
      find.byType(KonnektedArtwork).first,
    );
    expect(fallbackArt.size, 52);
    expect(fallbackArt.radius, 26);
    final placeholder = tester.widget<CircleAvatar>(
      find.byType(CircleAvatar).first,
    );
    expect(placeholder.radius, 26);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'artist row announces name and count once, with favorite action',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final semantics = tester.ensureSemantics();
      const song = Song(
        id: '1',
        title: 'Song',
        artist: 'Unique Artist',
        duration: Duration(minutes: 3),
        fileType: 'FLAC',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lokalArtistsProvider.overrideWithValue(
              const AsyncData([
                LokalArtist('Unique Artist', [song]),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: const LokalArtistsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.getSemantics(find.text('Unique Artist')).label;
      expect(RegExp('Unique Artist').allMatches(label).length, 1);
      expect(label, contains('1 song'));
      expect(
        tester
            .getSemantics(find.byTooltip('Add to favorites'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
    },
  );
}
