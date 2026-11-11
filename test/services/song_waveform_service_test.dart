import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flick/data/entities/song_audio_cache_entity.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/audio_analysis_queue.dart';
import 'package:flick/services/song_waveform_service.dart';
import 'package:flick/src/rust/api/audio_analysis.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AudioAnalysisResult envelope() => AudioAnalysisResult(
  peaks: Float32List.fromList([.25, .75, 0, 0, .5, .25]),
  lufs: -14,
  clipping: false,
);

Song track(String path, {String id = '12', int? start}) => Song(
  id: id,
  title: 'Fixture',
  artist: 'Artist',
  fileType: 'FLAC',
  duration: const Duration(minutes: 3),
  filePath: path,
  startOffsetMs: start,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lokal-waveform-');
    file = await File('${root.path}/track.flac').writeAsBytes([1, 2, 3, 4]);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'cache miss prepares available audio once and persists measured peaks',
    () async {
      SongAudioCacheEntity? saved;
      var decodes = 0;
      final service = SongWaveformService(
        readCache: (_) async => saved,
        writeCache: (_, cache) async => saved = cache,
        analysis: AudioAnalysisQueue(
          analyze: (path) async {
            expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
            decodes++;
            return envelope();
          },
        ),
      );
      final song = track(file.path);
      final first = await service.load(song);
      expect(first, envelope().peaks.toList());
      expect(saved!.songId, 12);
      expect(saved!.lufs, -14);
      expect(await service.load(song), first);
      expect(decodes, 1);
    },
  );

  test(
    'folder-picker files are staged with the bounded original-audio cache',
    () async {
      const storage = MethodChannel('com.mossapps.flick/storage');
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, (
        call,
      ) async {
        calls.add(call);
        return file.path;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          storage,
          null,
        ),
      );
      final paths = <String>[];
      final service = SongWaveformService(
        readCache: (_) async => null,
        writeCache: (_, __) async {},
        analysis: AudioAnalysisQueue(
          analyze: (path) async {
            paths.add(path);
            return envelope();
          },
        ),
      );
      expect(
        await service.load(track('content://library/tree/album/document/song')),
        isNotNull,
      );
      expect(paths, [file.path]);
      expect(calls.single.method, 'cacheUriForPlayback');
      expect(calls.single.arguments['extensionHint'], 'flac');
      expect(calls.single.arguments['maxStagingBytes'], greaterThan(0));
    },
  );

  test(
    'a retired subscriber cannot cancel a second player sharing its analysis',
    () async {
      final started = Completer<void>(),
          finish = Completer<AudioAnalysisResult?>();
      var resolveCount = 0, current = true, writes = 0;
      final service = SongWaveformService(
        readCache: (_) async => null,
        writeCache: (_, __) async => writes++,
        resolveFile: (_) async {
          resolveCount++;
          return file.path;
        },
        analysis: AudioAnalysisQueue(
          analyze: (_) {
            started.complete();
            return finish.future;
          },
        ),
      );
      final first = service.load(track(file.path), isCurrent: () => current);
      await started.future;
      final second = service.load(track(file.path));
      current = false;
      finish.complete(envelope());
      expect(await first, isNull);
      expect(await second, envelope().peaks.toList());
      expect(resolveCount, 1);
      expect(writes, 1);
    },
  );

  test(
    'a failed persistence operation does not hide a ready waveform',
    () async {
      final service = SongWaveformService(
        readCache: (_) async => throw StateError('unavailable database'),
        writeCache: (_, __) async => throw StateError('write failed'),
        analysis: AudioAnalysisQueue(analyze: (_) async => envelope()),
      );
      expect(await service.load(track(file.path)), envelope().peaks.toList());
    },
  );

  test(
    'cache freshness follows changed file bytes rather than player ID alone',
    () async {
      var decodes = 0;
      final old = SongAudioCacheEntity()
        ..peaks = [.1, .1]
        ..computedAt = DateTime(2020).millisecondsSinceEpoch;
      final service = SongWaveformService(
        readCache: (_) async => old,
        writeCache: (_, __) async {},
        analysis: AudioAnalysisQueue(
          analyze: (_) async {
            decodes++;
            return envelope();
          },
        ),
      );
      expect(await service.load(track(file.path)), envelope().peaks.toList());
      await file.writeAsBytes([1, 2, 3, 4, 5, 6]);
      expect(await service.load(track(file.path)), envelope().peaks.toList());
      expect(decodes, 2);
    },
  );

  test(
    'unsupported, partial, clipped and uncached live audio stay truthful lines',
    () async {
      var decodes = 0;
      final service = SongWaveformService(
        readCache: (_) async => null,
        writeCache: (_, __) async {},
        analysis: AudioAnalysisQueue(
          analyze: (_) async {
            decodes++;
            return null;
          },
        ),
      );
      expect(
        await service.load(track('https://example.invalid/live.flac')),
        isNull,
      );
      expect(await service.load(track(file.path, start: 40000)), isNull);
      final part = await File('${file.path}.part').writeAsBytes([1, 2]);
      expect(await service.load(track(part.path)), isNull);
      expect(decodes, 0);
      expect(await service.load(track(file.path)), isNull);
      expect(decodes, 1);
    },
  );
}
