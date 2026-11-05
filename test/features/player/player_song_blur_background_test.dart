import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/features/player/widgets/player_song_blur_background.dart';
import 'package:flick/models/song.dart';

const first = Song(
  id: 'first',
  title: 'First recording',
  artist: 'Artist',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
);
const second = Song(
  id: 'second',
  title: 'Second recording',
  artist: 'Artist',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
);

Widget playerBackground(Song song, {required bool fullCover,
    List<Color> colors = const [Colors.red, Colors.black]}) =>
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: PlayerSongBlurBackground(
              song: song,
              colors: colors,
              fullCover: fullCover,
            ),
          ),
        ),
      ),
    );

void main() {
  for (final fullCover in [true, false]) {
    testWidgets(
      'song switch crossfades the outgoing blur in '
      '${fullCover ? 'fullcover' : 'regular'} player',
      (tester) async {
        final oldKey = ValueKey('player-blur:first:null:null:$fullCover');
        final newKey = ValueKey('player-blur:second:null:null:$fullCover');

        await tester.pumpWidget(playerBackground(
          first, fullCover: fullCover,
        ));
        expect(find.byKey(oldKey), findsOneWidget);

        await tester.pumpWidget(playerBackground(
          second, fullCover: fullCover,
          colors: const [Colors.blue, Colors.black],
        ));
        // The real outgoing blur must still exist, not only a new controller
        // whose opacity changes after the old song has been discarded.
        expect(find.byKey(oldKey), findsOneWidget);
        expect(find.byKey(newKey), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byKey(oldKey), findsOneWidget);
        expect(find.byKey(newKey), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1000));
        expect(find.byKey(oldKey), findsNothing);
        expect(find.byKey(newKey), findsOneWidget);
      },
    );
  }

  testWidgets('late palette arrival does not replace same-song blur',
      (tester) async {
    const key = ValueKey('player-blur:first:null:null:false');
    await tester.pumpWidget(playerBackground(first, fullCover: false));
    await tester.pumpWidget(playerBackground(
      first, fullCover: false,
      colors: const [Colors.purple, Colors.black],
    ));
    expect(find.byKey(key), findsOneWidget);
  });
}
