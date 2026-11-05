import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/playlist_hero_header.dart';

void main() {
  test('hero stays below 35 percent of phone height', () {
    expect(playlistHeroHeightForScreen(640), closeTo(217.6, .01));
    expect(playlistHeroHeightForScreen(900), closeTo(306, .01));
    expect(playlistHeroHeightForScreen(1200), 370);
    expect(playlistHeroHeightForScreen(1200), lessThan(1200 * .35));
  });

  test('playlist collage keeps its chosen covers during a session', () {
    final candidates = [
      for (var i = 0; i < 24; i++)
        PlaylistHeroCover(imagePath: 'https://example.com/$i.jpg'),
    ];

    final first = playlistHeroCoversForSession('local:one', candidates);
    final reopened = playlistHeroCoversForSession('local:one', candidates);

    expect(first.map((cover) => cover.imagePath),
        orderedEquals(reopened.map((cover) => cover.imagePath)));
    expect(first.length, 12);
    expect(first.map((cover) => cover.imagePath).toSet().length, 12);
  });

  test('duplicate artwork and unavailable covers are excluded', () {
    final covers = playlistHeroCoversForSession('spotify:one', [
      const PlaylistHeroCover(imagePath: ''),
      const PlaylistHeroCover(imagePath: 'https://example.com/a.jpg'),
      const PlaylistHeroCover(imagePath: 'https://example.com/a.jpg'),
      const PlaylistHeroCover(imagePath: '', audioSourcePath: '/music/b.flac'),
    ]);

    expect(covers.length, 2);
    expect(covers.any((cover) =>
        cover.audioSourcePath == '/music/b.flac'), isTrue);
    expect(covers.any((cover) =>
        cover.imagePath == 'https://example.com/a.jpg'), isTrue);
  });

  test('empty playlist has no candidate artwork', () {
    expect(playlistHeroCoversForSession('youtube:empty', []), isEmpty);
  });

  testWidgets('generated collage stages its first reveal, not later visits',
      (tester) async {
    const artwork = [
      PlaylistHeroCover(imagePath: '/missing-playlist-cover.jpg'),
    ];

    Widget page(String id, {List<PlaylistHeroCover> covers = artwork}) =>
        MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 300,
              child: PlaylistDiagonalCollage(playlistId: id, covers: covers),
            ),
          ),
        );

    AnimatedOpacity reveal(String id) => tester.widget<AnimatedOpacity>(
          find.byKey(ValueKey('playlist-collage-reveal:$id')),
        );

    await tester.pumpWidget(page('test:playlist-first'));
    expect(reveal('test:playlist-first').opacity, 0);

    await tester.pump(const Duration(milliseconds: 349));
    expect(reveal('test:playlist-first').opacity, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(reveal('test:playlist-first').opacity, 1);

    // Opening the same playlist again in this process has no artificial wait.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page('test:playlist-first'));
    expect(reveal('test:playlist-first').opacity, 1);

    // Another playlist still gets its own first-visit head start.
    await tester.pumpWidget(page('test:playlist-second'));
    expect(reveal('test:playlist-second').opacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty artwork does not consume the first collage reveal',
      (tester) async {
    Widget page(List<PlaylistHeroCover> covers) => MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 300,
              child: PlaylistDiagonalCollage(
                playlistId: 'test:playlist-late-art',
                covers: covers,
              ),
            ),
          ),
        );

    await tester.pumpWidget(page(const []));
    expect(find.byType(AnimatedOpacity), findsNothing);

    await tester.pumpWidget(page(const [
      PlaylistHeroCover(imagePath: '/missing-late-playlist-cover.jpg'),
    ]));
    final reveal = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey(
        'playlist-collage-reveal:test:playlist-late-art',
      )),
    );
    expect(reveal.opacity, 0);
    await tester.pump(playlistHeroFirstRevealDelay);
    expect(tester.takeException(), isNull);
  });
}
