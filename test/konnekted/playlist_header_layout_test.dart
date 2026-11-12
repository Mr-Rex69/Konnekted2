import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/features/konnekted/library/lokal_song_browser.dart';
import 'package:flick/features/konnekted/library/playlist_hero_header.dart';
import 'package:flick/features/playlist_links/playlist_link_models.dart';
import 'package:flick/features/spotify/provider_playlist_track_browser.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

const _canvas = ValueKey('playlist-preview');
late Directory _art;
late List<String> _covers;

Widget _page({
  required bool provider,
  required EdgeInsets insets,
  double textScale = 1,
  LokalThemeId theme = LokalThemeId.dark,
  VoidCallback? onAction,
}) {
  final actions = [
    LokalRoundAction(
      icon: Icons.more_horiz_rounded,
      label: 'Playlist action',
      onPressed: onAction ?? () {},
    ),
  ];
  final tracks = [
    for (var i = 0; i < 100; i++)
      LokalDiscoveryTrack(
        title: 'Track $i',
        artist: 'Artist',
        album: 'Album',
        artworkUrl: _covers[i % _covers.length],
      ),
  ];
  final hero = PlaylistHeroHeader(
    playlistId: 'test:generated',
    title: 'Evening rotation',
    owner: 'Your collection',
    metadata: '100 songs · 5 hr',
    covers: [for (final path in _covers) PlaylistHeroCover(imagePath: path)],
  );
  final page = provider
      ? Scaffold(
          backgroundColor: LokalTokens.resolve(theme).bg,
          body: ProviderPlaylistTrackBrowser(
            header: ProviderPlaylistHeader(
              title: 'Evening rotation',
              playlistId: 'test:provider',
              owner: 'Your collection',
              tracks: tracks,
            ),
            headerActions: actions,
            tracks: tracks,
            source: PlaylistLinkSource.spotify,
            playlistId: 'test:provider',
            accountId: 'test:account',
            artworkBuilder: (_) => const Icon(Icons.music_note),
            onPlay: (_, __) {},
            onSongActions: (_) {},
          ),
        )
      : LokalLibraryPage(
          title: 'Evening rotation',
          edgeToEdgeHeader: true,
          header: hero,
          actions: actions,
          slivers: [
            LokalSongBrowser(
              songs: [
                for (var i = 0; i < 100; i++)
                  Song(
                    id: '$i',
                    title: 'Track $i',
                    artist: 'Artist',
                    duration: const Duration(minutes: 3),
                    fileType: 'FLAC',
                  ),
              ],
              initialSort: LokalSongSort.original,
              originalLabel: 'Playlist order',
              searchHint: 'Search in playlist',
            ),
          ],
        );
  return ProviderScope(
    overrides: [playerProvider.overrideWith(_Player.new)],
    child: MaterialApp(
      theme: LokalTheme.build(LokalTokens.resolve(theme)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: insets,
          viewPadding: insets,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: RepaintBoundary(key: _canvas, child: page),
    ),
  );
}

Future<void> _jump(WidgetTester tester, double offset) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(offset);
  await tester.pumpAndSettle();
}

Future<void> _warmArtwork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    if (images.any((image) => image.image != null)) break;
  }
  await tester.pumpAndSettle();
  expect(
    tester.widget<RawImage>(find.byType(RawImage).first).image,
    isNotNull,
    reason: 'the test must inspect the rendered banner, not its loading placeholder',
  );
  final artwork = tester.widget<RawImage>(find.byType(RawImage).first).image!;
  await tester.runAsync(() async {
    final data = (await artwork.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final colors = <int>{};
    final y = (artwork.height * .25).floor();
    for (var x = 0; x < artwork.width; x += 20) {
      final offset = (y * artwork.width + x) * 4;
      colors.add(
        (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2],
      );
    }
    expect(
      colors.length,
      greaterThan(1),
      reason: 'real collage artwork must have decoded',
    );
  });
}

Future<void> _preview(WidgetTester tester, String name) async {
  final destination = Platform.environment['LOKAL_PLAYLIST_PREVIEW_DIR'];
  if (destination == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_canvas),
    );
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$destination/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _art = Directory.systemTemp.createTempSync('playlist-header-art');
    const pngs = [
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGN4HK0PAAOSAW5pUTZZAAAAAElFTkSuQmCC',
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGPQ71wHAAJRAWc7GkHcAAAAAElFTkSuQmCC',
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNoCtwKAALhAYm18sAfAAAAAElFTkSuQmCC',
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGO4u8MRAARMAdc7NqR8AAAAAElFTkSuQmCC',
    ];
    _covers = [for (var i = 0; i < pngs.length; i++) '${_art.path}/$i.png'];
    for (var i = 0; i < pngs.length; i++) {
      File(_covers[i]).writeAsBytesSync(base64Decode(pngs[i]));
    }
    await (FontLoader('DMSans')
          ..addFont(rootBundle.load('assets/fonts/DMSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/DMSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/DMSans-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'DMMono',
    )..addFont(rootBundle.load('assets/fonts/DMMono-Regular.ttf'))).load();
  });
  tearDownAll(() => _art.deleteSync(recursive: true));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetPreparedPlaylistBanners();
  });

  for (final provider in [false, true]) {
    testWidgets(
      'playlist search remains usable above the keyboard: provider=$provider',
      (tester) async {
        tester.view
          ..physicalSize = const Size(1170, 2532)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _page(provider: provider, insets: const EdgeInsets.only(top: 47)),
        );
        await tester.pumpAndSettle();
        await _jump(tester, 900.35);
        await tester.showKeyboard(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 900);
        await tester.pumpAndSettle();
        final search = tester.getRect(find.byType(TextField));
        expect(search.top, greaterThanOrEqualTo(47 + 56));
        expect(search.bottom, lessThan(844 - 300));
        expect(tester.takeException(), isNull);
      },
    );

    for (final (size, insets, dpr, scale) in [
      (const Size(390, 844), const EdgeInsets.only(top: 47), 3.0, 1.0),
      (const Size(360, 760), const EdgeInsets.only(top: 24), 2.625, 1.0),
      (
        const Size(844, 390),
        const EdgeInsets.only(left: 47, right: 47),
        3.0,
        1.0,
      ),
      (const Size(390, 844), const EdgeInsets.only(top: 59), 3.0, 2.0),
    ]) {
      testWidgets(
        'playlist search stays below navigation: provider=$provider $size scale=$scale',
        (tester) async {
          tester.view
            ..physicalSize = size * dpr
            ..devicePixelRatio = dpr;
          addTearDown(tester.view.reset);
          var actions = 0;
          await tester.pumpWidget(
            _page(
              provider: provider,
              insets: insets,
              textScale: scale,
              onAction: () => actions++,
            ),
          );
          await tester.pumpAndSettle();
          await _warmArtwork(tester);
          if (!provider && size.width == 390 && scale == 1) {
            await _preview(tester, 'playlist-header-expanded');
          }
          await _jump(tester, 900.35);
          final search = tester.getRect(find.byType(TextField));
          expect(search.top, greaterThanOrEqualTo(insets.top + 56));
          final navigation = tester.getRect(
            find.byKey(const ValueKey('playlist-navigation')),
          );
          expect(navigation.top, greaterThanOrEqualTo(insets.top - .1));
          expect(search.top, greaterThanOrEqualTo(navigation.bottom - .1));
          expect(search.left, greaterThanOrEqualTo(insets.left));
          expect(search.right, lessThanOrEqualTo(size.width - insets.right));
          expect(search.bottom, lessThan(size.height));
          await tester.tap(find.byTooltip('Playlist action'));
          expect(actions, 1);
          if (!provider && size.width == 390 && scale == 1) {
            await _preview(tester, 'playlist-header-pinned');
          }
          await tester.enterText(find.byType(TextField), 'Track 90');
          await tester.pumpAndSettle(const Duration(milliseconds: 250));
          expect(find.text('Track 90'), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final theme in [LokalThemeId.dark, LokalThemeId.light]) {
      for (final dpr in [1.0, 2.625, 3.0]) {
        testWidgets(
          'banner joins page without raster seams: provider=$provider ${theme.name} dpr=$dpr',
          (tester) async {
            tester.view
              ..physicalSize = const Size(390, 844) * dpr
              ..devicePixelRatio = dpr;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              _page(
                provider: provider,
                insets: const EdgeInsets.only(top: 47),
                theme: theme,
              ),
            );
            await tester.pumpAndSettle();
            await _warmArtwork(tester);
            final color = LokalTokens.resolve(theme).bg.toARGB32();
            final expected = [
              (color >> 16) & 255,
              (color >> 8) & 255,
              color & 255,
              255,
            ];
            for (final offset in [0.0, .35, 19.35]) {
              await _jump(tester, offset);
              final edge = tester
                  .getRect(find.byType(PlaylistHeroHeader))
                  .bottom;
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(_canvas),
                );
                final image = await boundary.toImage(pixelRatio: dpr);
                try {
                  final data = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List();
                  // The final screenshot column is only partially inside a fractional-width surface.
                  for (var x = 0; x < (390 * dpr).floor(); x++) {
                    for (var dy = -2; dy <= 2; dy++) {
                      final y = (edge * dpr).floor() + dy;
                      final index = (y * image.width + x) * 4;
                      for (var channel = 0; channel < 4; channel++) {
                        expect(
                          data[index + channel],
                          closeTo(expected[channel], 1),
                          reason:
                              'edge at scroll=$offset, y=$y, x=$x, channel=$channel',
                        );
                      }
                    }
                  }
                } finally {
                  image.dispose();
                }
              });
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
