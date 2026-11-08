import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_song_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/features/konnekted/library/lokal_song_filter.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

Song track(
  String id, {
  String? source,
  int? bits = 24,
  int? rate = 96000,
  String type = 'FLAC',
  String? resolution,
}) => Song(
  id: id,
  title: id,
  artist: 'Artist',
  duration: const Duration(minutes: 3),
  fileType: type,
  filePath: source == null ? '/Music/Artist/Album/$id.flac' : '$source://$id',
  sourceType: source,
  bitDepth: bits,
  sampleRate: rate,
  resolution: resolution,
);

void main() {
  final local = track('local');
  final desktop = track('desktop', source: 'lokal');
  final other = track('nas', source: 'subsonic');
  test('location and exact format filters intersect without hiding other sources from All', () {
    final songs = [local, desktop, other];
    expect(
      songs.where(
        (s) => matchesLibraryFilters(
          s,
          LokalSongLocation.phone,
          'format:24:96000',
        ),
      ),
      [local],
    );
    expect(
      songs.where(
        (s) => matchesLibraryFilters(s, LokalSongLocation.pc, 'quality:hiRes'),
      ),
      [desktop],
    );
    expect(
      songs.where(
        (s) => matchesLibraryFilters(s, LokalSongLocation.other, 'all'),
      ),
      [other],
    );
    expect(
      songs.where(
        (s) => matchesLibraryFilters(s, LokalSongLocation.all, 'all'),
      ),
      songs,
    );
    expect(
      matchesLibraryFilters(local, LokalSongLocation.phone, 'format:16:44100'),
      isFalse,
    );
  });
  test('combined menu includes only unique known formats in numeric order', () {
    final songs = [
      local,
      desktop,
      track('cd', bits: 16, rate: 44100),
      track('48', bits: 16, rate: 48000),
      track('unread', bits: null, rate: null),
    ];
    expect(libraryAudioFormats(songs), [
      'format:16:44100',
      'format:16:48000',
      'format:24:96000',
    ]);
    expect(libraryAudioFilterLabel('format:16:44100'), '16-bit / 44.1 kHz');
    expect(libraryAudioFilterLabel('format:24:96000'), '24-bit / 96 kHz');
  });
  testWidgets(
    'changing format and location updates the list and clears together',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  LokalSongBrowser(
                    songs: [local, track('CD song', bits: 16, rate: 44100)],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CD song'), findsOneWidget);
      await tester.tap(find.text('All formats and qualities'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('24-bit / 96 kHz'),
      );
      await tester.pumpAndSettle();
      expect(find.text('local'), findsOneWidget);
      expect(find.text('CD song'), findsNothing);
      await tester.tap(find.text('All songs'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('PC'),
      );
      await tester.pumpAndSettle();
      expect(find.text('local'), findsNothing);
      expect(find.text('No matching songs'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('local'), findsOneWidget);
      expect(find.text('CD song'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'quality distinguishes low lossy, lossless, hi-res, and unread files',
    () {
      expect(
        matchesLibraryFilters(
          track('low', type: 'MP3', resolution: '128 kbps'),
          LokalSongLocation.all,
          'quality:low',
        ),
        isTrue,
      );
      expect(
        matchesLibraryFilters(
          track('cd', bits: 16, rate: 44100),
          LokalSongLocation.all,
          'quality:lossless',
        ),
        isTrue,
      );
      expect(
        matchesLibraryFilters(local, LokalSongLocation.all, 'quality:hiRes'),
        isTrue,
      );
      expect(
        matchesLibraryFilters(
          track('unknown', bits: null, rate: null),
          LokalSongLocation.all,
          'quality:unknown',
        ),
        isTrue,
      );
    },
  );
}
