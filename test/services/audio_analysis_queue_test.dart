import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flick/services/audio_analysis_queue.dart';
import 'package:flick/src/rust/api/audio_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late List<File> files;
  AudioAnalysisResult result() => AudioAnalysisResult(
    peaks: Float32List.fromList([.2, .8, 0, .5]),
    clipping: false,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lokal-analysis-workers-');
    files = await Future.wait(
      List.generate(
        4,
        (i) => File('${root.path}/$i.wav').writeAsBytes([1, 2, 3]),
      ),
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'library and player requests share bounded decoders; retired jobs skip',
    () async {
      final started = <String>[],
          releases = <String, Completer<AudioAnalysisResult?>>{};
      final firstTwo = Completer<void>(), third = Completer<void>();
      var active = 0, maximum = 0, retired = false;
      final queue = AudioAnalysisQueue(
        analyze: (path) async {
          started.add(path);
          active++;
          if (active > maximum) maximum = active;
          if (started.length == 2) firstTwo.complete();
          if (started.length == 3) third.complete();
          final release = releases[path] = Completer<AudioAnalysisResult?>();
          try {
            return await release.future;
          } finally {
            active--;
          }
        },
      );
      final first = queue.analyze(files[0].path);
      final duplicate = queue.analyze(files[0].path);
      final second = queue.analyze(files[1].path);
      await firstTwo.future;
      final next = queue.analyze(files[2].path);
      final obsolete = queue.analyze(files[3].path, isNeeded: () => !retired);
      retired = true;
      releases[files[0].path]!.complete(result());
      await third.future;
      releases[files[1].path]!.complete(result());
      releases[files[2].path]!.complete(result());
      expect(await first, isNotNull);
      expect(await duplicate, isNotNull);
      expect(await second, isNotNull);
      expect(await next, isNotNull);
      expect(await obsolete, isNull);
      expect(started, unorderedEquals([files[0].path, files[1].path, files[2].path]));
      expect(maximum, 2);
    },
  );

  test('analysis of a changed file cannot publish stale peaks', () async {
    final started = Completer<void>(),
        finish = Completer<AudioAnalysisResult?>();
    final queue = AudioAnalysisQueue(
      analyze: (_) {
        started.complete();
        return finish.future;
      },
    );
    final pending = queue.analyze(files.first.path);
    await started.future;
    await files.first.writeAsBytes([7, 8, 9, 10]);
    finish.complete(result());
    expect(await pending, isNull);
  });

  test(
    'decode failure releases capacity and the same source can be retried',
    () async {
      var count = 0;
      final queue = AudioAnalysisQueue(
        concurrency: 1,
        analyze: (_) async {
          if (++count == 1) throw StateError('unsupported frame');
          return result();
        },
      );
      await expectLater(queue.analyze(files.first.path), throwsStateError);
      expect(await queue.analyze(files.first.path), isNotNull);
      expect(count, 2);
    },
  );
}
