import 'dart:io';
import 'dart:typed_data';

import 'package:flick/data/entities/song_audio_cache_entity.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/full_player_waveform_provider.dart';
import 'package:flick/services/audio_analysis_queue.dart';
import 'package:flick/services/network_cache_service.dart';
import 'package:flick/services/song_waveform_service.dart';
import 'package:flick/src/rust/api/audio_analysis.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'prefetch completion and same-ID replacement refresh the visible waveform',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lokal-prefetch-waveform-',
      );
      final cache = NetworkCacheService(rootDirectory: root);
      var decodes = 0;
      final service = SongWaveformService(
        readCache: (_) async => SongAudioCacheEntity()..peaks = [.99, .99],
        writeCache: (_, __) async => fail(
          'temporary remote audio must not reuse a library cache identity',
        ),
        resolveFile: (_) => cache.getPath(3, 'remote-track', touch: false),
        analysis: AudioAnalysisQueue(
          analyze: (path) async {
            decodes++;
            final bytes = await File(path).readAsBytes();
            return AudioAnalysisResult(
              peaks: Float32List.fromList([bytes.first / 10, .5]),
              clipping: false,
            );
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [songWaveformServiceProvider.overrideWithValue(service)],
      );
      const song = Song(
        id: '42',
        title: 'Track',
        artist: 'Artist',
        fileType: 'FLAC',
        duration: Duration(minutes: 3),
        filePath: 'lokal://3/remote-track',
        sourceType: 'lokal',
        remoteServerId: 3,
        remoteId: 'remote-track',
      );
      final subscription = container.listen(
        fullPlayerWaveformProvider(song),
        (_, __) {},
      );
      try {
        expect(
          await container.read(fullPlayerWaveformProvider(song).future),
          isNull,
        );
        await cache.stash(3, 'remote-track', [2, 2, 2], extension: 'flac');
        await container.pump();
        final first = await container.read(
          fullPlayerWaveformProvider(song).future,
        );
        expect(first!.first, closeTo(.2, .001));
        await cache.stash(3, 'remote-track', [8, 8, 8, 8], extension: 'flac');
        await container.pump();
        final replaced = await container.read(
          fullPlayerWaveformProvider(song).future,
        );
        expect(replaced!.first, closeTo(.8, .001));
        expect(decodes, 2);
      } finally {
        subscription.close();
        container.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
