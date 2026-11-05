import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
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

  testWidgets('first view builds no images until its short mount delay',
      (tester) async {
    Widget page(String id, {List<PlaylistHeroCover>? covers}) => MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 300,
              child: PlaylistDiagonalCollage(
                playlistId: id,
                covers: covers ?? const [
                  PlaylistHeroCover(imagePath: '/missing-playlist-art.jpg'),
                ],
              ),
            ),
          ),
        );

    await tester.pumpWidget(page('test:playlist-first'));
    expect(find.byType(CachedImageWidget), findsNothing);
    await tester.pump(const Duration(milliseconds: 79));
    expect(find.byType(CachedImageWidget), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(CachedImageWidget), findsNWidgets(16));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page('test:playlist-first'));
    expect(find.byType(CachedImageWidget), findsNWidgets(16));

    // Every newly generated playlist collage has its own one-time delay.
    await tester.pumpWidget(page('test:playlist-second'));
    expect(find.byType(CachedImageWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty artwork waits until there are candidates',
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
    expect(find.byType(CachedImageWidget), findsNothing);
    await tester.pumpWidget(page(const [
      PlaylistHeroCover(imagePath: '/missing-late-playlist-art.jpg'),
    ]));
    expect(find.byType(CachedImageWidget), findsNothing);
    await tester.pump(playlistHeroPostTransitionDelay);
    expect(find.byType(CachedImageWidget), findsNWidgets(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a route does not build playlist art during its slide',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              LokalPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: PlaylistDiagonalCollage(
                    playlistId: 'test:playlist-during-push',
                    covers: [
                      PlaylistHeroCover(imagePath: '/missing-push-art.jpg'),
                    ],
                  ),
                ),
              ),
            ),
            child: const Text('Open playlist'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('Open playlist'));
    await tester.pump();
    expect(find.byType(CachedImageWidget), findsNothing);

    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(CachedImageWidget), findsNothing);

    await tester.pump(const Duration(milliseconds: 160));
    // The route completed, but decoding is still deferred by 80 ms.
    expect(find.byType(CachedImageWidget), findsNothing);

    await tester.pump(playlistHeroPostTransitionDelay);
    expect(find.byType(CachedImageWidget), findsNWidgets(16));
    expect(tester.takeException(), isNull);
  });
}
