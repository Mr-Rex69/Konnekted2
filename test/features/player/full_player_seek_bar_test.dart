import 'package:flick/models/song.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/features/player/widgets/waveform_layer.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/full_player_seek_bar.dart';
import 'package:flick/models/progress_bar_style.dart';

import 'dart:async';

import 'package:flick/data/entities/song_audio_cache_entity.dart';
import 'package:flick/features/player/widgets/waveform_seek_bar.dart';
import 'package:flick/providers/full_player_waveform_provider.dart';
import 'package:flick/services/song_waveform_service.dart';

class _SeekPlayer extends Fake implements PlayerService {
  @override
  final durationNotifier = ValueNotifier(const Duration(minutes: 3));
  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
}

void main() {
  testWidgets('late waveform results cannot replace the next song timeline', (
    tester,
  ) async {
    final player = _SeekPlayer();
    final position = ValueNotifier(const Duration(seconds: 10));
    final first = Completer<SongAudioCacheEntity?>(),
        second = Completer<SongAudioCacheEntity?>();
    final service = SongWaveformService(
      readCache: (song) => song.id == 'first' ? first.future : second.future,
      resolveFile: (_) async => null,
      writeCache: (_, __) async {},
    );
    var id = 'first';
    late StateSetter change;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [songWaveformServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  change = setState;
                  return SizedBox(
                    width: 320,
                    child: WaveformLayer(
                      playerService: player,
                      positionNotifier: position,
                      currentSong: Song(
                        id: id,
                        title: id,
                        artist: 'Fixture',
                        fileType: 'FLAC',
                        filePath: 'https://example.invalid/$id',
                        duration: const Duration(minutes: 3),
                      ),
                      styleOverride: ProgressBarStyle.waveform,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    change(() => id = 'second');
    await tester.pump();
    first.complete(SongAudioCacheEntity()..peaks = [.9, .9]);
    await tester.pumpAndSettle();
    expect(
      tester.widget<WaveformSeekBar>(find.byType(WaveformSeekBar)).cachedPeaks,
      isNull,
    );
    second.complete(SongAudioCacheEntity()..peaks = [.1, .4, 0, .7]);
    await tester.pumpAndSettle();
    expect(
      tester.widget<WaveformSeekBar>(find.byType(WaveformSeekBar)).cachedPeaks,
      [.1, .4, 0, .7],
    );
    await tester.tapAt(tester.getRect(find.byType(WaveformSeekBar)).center);
    await tester.pumpAndSettle();
    expect(player.seeks, [const Duration(seconds: 90)]);
    await tester.pumpWidget(const SizedBox.shrink());
    position.dispose();
    player.durationNotifier.dispose();
  });

  testWidgets(
    'classic Wavy drag stays under the finger during engine updates',
    (tester) async {
      final player = _SeekPlayer();
      final position = ValueNotifier(const Duration(seconds: 10));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: WaveformLayer(
                    playerService: player,
                    positionNotifier: position,
                    currentSong: null,
                    styleOverride: ProgressBarStyle.wavy,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(Slider));
      final gesture = await tester.startGesture(
        Offset(rect.left + 60, rect.center.dy),
      );
      await gesture.moveTo(Offset(rect.left + 240, rect.center.dy));
      await tester.pump();
      final dragged = tester.widget<Slider>(find.byType(Slider)).value;
      expect(dragged, greaterThan(.6));
      position.value = const Duration(seconds: 11);
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, dragged);
      expect(player.seeks, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(player.seeks, hasLength(1));
      expect(player.seeks.single.inMilliseconds, closeTo(dragged * 180000, 1));
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
      player.durationNotifier.dispose();
    },
  );

  for (final changeSong in [false, true]) {
    testWidgets(
      'classic Wavy cancels a drag across ${changeSong ? "song" : "style"} changes',
      (tester) async {
        final player = _SeekPlayer();
        final position = ValueNotifier(const Duration(seconds: 10));
        var style = ProgressBarStyle.wavy;
        var songId = 'before';
        late StateSetter change;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      change = setState;
                      return SizedBox(
                        width: 320,
                        child: WaveformLayer(
                          playerService: player,
                          positionNotifier: position,
                          currentSong: Song(
                            id: songId,
                            title: 'Track',
                            artist: 'Artist',
                            album: 'Album',
                            fileType: 'FLAC',
                            duration: const Duration(minutes: 3),
                          ),
                          styleOverride: style,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(Slider));
        final gesture = await tester.startGesture(
          Offset(rect.left + 60, rect.center.dy),
        );
        await gesture.moveTo(Offset(rect.left + 240, rect.center.dy));
        await tester.pump();
        change(() {
          if (changeSong) {
            songId = 'after';
          } else {
            style = ProgressBarStyle.line;
          }
        });
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(player.seeks, isEmpty);
        position.value = const Duration(seconds: 11);
        change(() => style = ProgressBarStyle.wavy);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          closeTo(11 / 180, .001),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        position.dispose();
        player.durationNotifier.dispose();
      },
    );
  }
  for (final style in ProgressBarStyle.values) {
    for (final rtl in [false, true]) {
      testWidgets(
        '$style seeks and exposes an adjustable timeline (RTL $rtl)',
        (tester) async {
          final changes = <double>[];
          final commits = <double>[];
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: SizedBox(
                      width: 320,
                      child: FullPlayerSeekBar(
                        style: style,
                        value: .25,
                        peaks: const [.1, .5, 1, .2, .7, .3],
                        onChanged: changes.add,
                        onChangeEnd: commits.add,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.getSize(find.byType(FullPlayerSeekBar)).height, 48);
          await tester.pumpAndSettle();
          final node = tester.getSemantics(find.byType(Slider));

          expect(
            node
                .debugListChildrenInOrder(
                  DebugSemanticsDumpOrder.traversalOrder,
                )
                .any(
                  (child) => child.getSemanticsData().hasAction(
                    SemanticsAction.increase,
                  ),
                ),
            isTrue,
          );
          final rect = tester.getRect(find.byType(Slider));
          await tester.tapAt(
            Offset(rect.left + rect.width * (rtl ? .2 : .8), rect.center.dy),
          );
          await tester.pumpAndSettle();
          expect(changes.last, greaterThan(.7));
          expect(commits, hasLength(1));
          expect(commits.single, changes.last);
          changes.clear();
          commits.clear();
          final gesture = await tester.startGesture(rect.center);
          await gesture.moveBy(Offset(rtl ? -70 : 70, 0));
          await tester.pump();
          expect(changes, isNotEmpty);
          expect(commits, isEmpty);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(commits, hasLength(1));
          expect(commits.single, changes.last);

          semantics.dispose();
        },
      );
    }
    testWidgets('$style disables unknown timing without changing layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: FullPlayerSeekBar(style: style, value: 0, onChanged: null),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(FullPlayerSeekBar));
      await tester.tapAt(rect.center);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(rect.height, 48);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('waveform accepts missing, silent and invalid caches', (
    tester,
  ) async {
    for (final peaks in <List<double>?>[
      null,
      [],
      [0, 0],
      [double.nan, .8, double.infinity],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: FullPlayerSeekBar(
                style: ProgressBarStyle.waveform,
                value: .5,
                peaks: peaks,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
