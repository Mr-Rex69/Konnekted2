import 'dart:async';

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

    expect(
      first.map((cover) => cover.imagePath),
      orderedEquals(reopened.map((cover) => cover.imagePath)),
    );
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
    expect(
      covers.any((cover) => cover.audioSourcePath == '/music/b.flac'),
      isTrue,
    );
    expect(
      covers.any((cover) => cover.imagePath == 'https://example.com/a.jpg'),
      isTrue,
    );
  });

  test('empty playlist has no candidate artwork', () {
    expect(playlistHeroCoversForSession('youtube:empty', []), isEmpty);
  });

  testWidgets('generated collage builds immediately, including late covers', (
    tester,
  ) async {
    Widget page(List<PlaylistHeroCover> covers) => MaterialApp(
      theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 300,
          child: PlaylistDiagonalCollage(covers: covers),
        ),
      ),
    );

    await tester.pumpWidget(
      page(const [PlaylistHeroCover(imagePath: '/missing-playlist-art.jpg')]),
    );
    expect(find.byType(CachedImageWidget), findsNWidgets(16));

    await tester.pumpWidget(page(const []));
    expect(find.byType(CachedImageWidget), findsNothing);

    await tester.pumpWidget(
      page(const [PlaylistHeroCover(imagePath: '/missing-late-art.jpg')]),
    );
    expect(find.byType(CachedImageWidget), findsNWidgets(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('first tap waits before push, repeat visit is immediate', (
    tester,
  ) async {
    var pushes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => unawaited(
                  openPlaylistAfterFirstTap(
                    context,
                    'test:playlist-tap-delay',
                    () async {
                      pushes++;
                      await Navigator.of(context).push<void>(
                        LokalPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: PlaylistDiagonalCollage(
                              covers: [
                                PlaylistHeroCover(
                                  imagePath: '/missing-push-art.jpg',
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                child: const Text('Open playlist'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open playlist'));
    await tester.pump();
    expect(pushes, 0);
    // Ignore a second tap while the opening is pending.
    await tester.tap(find.text('Open playlist'));
    await tester.pump(
      playlistHeroFirstOpenTapDelay - const Duration(milliseconds: 1),
    );
    expect(pushes, 0);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(pushes, 1);
    await tester.pump(const Duration(milliseconds: 16));
    // The collage is built on the first route frame, not after the slide.
    expect(
      find.byType(PlaylistDiagonalCollage, skipOffstage: false),
      findsOneWidget,
    );

    final routeContext = tester.element(
      find.byType(PlaylistDiagonalCollage, skipOffstage: false),
    );
    Navigator.of(routeContext).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open playlist'));
    await tester.pump();
    expect(pushes, 2);
    expect(
      find.byType(PlaylistDiagonalCollage, skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('first opening waits for artwork readiness before pushing', (
    tester,
  ) async {
    final artworkReady = Completer<void>();
    var pushes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => unawaited(
                  openPlaylistAfterFirstTap(
                    context,
                    'test:playlist-warmup',
                    () async {
                      pushes++;
                    },
                    prepareArtwork: () => artworkReady.future,
                  ),
                ),
                child: const Text('Open prepared playlist'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open prepared playlist'));
    await tester.pump();
    await tester.tap(find.text('Open prepared playlist'));
    await tester.pump(playlistHeroFirstOpenTapDelay);
    expect(pushes, 0, reason: 'the image decode has not completed');

    artworkReady.complete();
    await tester.pump();
    expect(pushes, 1, reason: 'the route starts after the warmup');

    await tester.tap(find.text('Open prepared playlist'));
    await tester.pump();
    expect(pushes, 2, reason: 'return visits do not wait for artwork again');
  });

  testWidgets('offline artwork cannot block playlist navigation indefinitely', (
    tester,
  ) async {
    final stalledArtwork = Completer<void>();
    var pushes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => unawaited(
                  openPlaylistAfterFirstTap(
                    context,
                    'test:playlist-warmup-timeout',
                    () async {
                      pushes++;
                    },
                    prepareArtwork: () => stalledArtwork.future,
                  ),
                ),
                child: const Text('Open offline playlist'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open offline playlist'));
    await tester.pump();
    await tester.pump(
      playlistHeroWarmupTimeout - const Duration(milliseconds: 1),
    );
    expect(pushes, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(pushes, 1, reason: 'the timeout allows navigation');
  });

}
