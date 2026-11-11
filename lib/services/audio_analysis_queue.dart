import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../src/rust/api/audio_analysis.dart';
import '../data/entities/song_audio_cache_entity.dart';

typedef AudioFileAnalyzer = Future<AudioAnalysisResult?> Function(String path);

/// Shared by library preparation and the visible waveform. No more than two
/// background decoders run; duplicate requests for the same file share work.
class AudioAnalysisQueue {
  AudioAnalysisQueue({AudioFileAnalyzer? analyze, this.concurrency = 2})
    : assert(concurrency > 0),
      _analyze = analyze ?? _nativeAnalysis;

  static final instance = AudioAnalysisQueue();
  static const peakBuckets = 240;
  static const cacheVersion = SongAudioCacheEntity.currentVersion;
  final AudioFileAnalyzer _analyze;
  final int concurrency;
  final _waiting = Queue<Completer<void>>();
  final _tasks = <(String, int, int), _AnalysisTask>{};
  var _active = 0;

  static Future<AudioAnalysisResult?> _nativeAnalysis(String path) =>
      analyzeAudioFile(path: path, peakBuckets: peakBuckets);

  Future<AudioAnalysisResult?> analyze(
    String path, {
    bool Function()? isNeeded,
  }) async {
    final stamp = await File(path).stat();
    if (stamp.type != FileSystemEntityType.file || stamp.size == 0) return null;
    final key = (path, stamp.size, stamp.modified.microsecondsSinceEpoch);
    var task = _tasks[key];
    if (task == null) {
      task = _AnalysisTask();
      task.listeners.add(isNeeded ?? () => true);
      _tasks[key] = task;
      task.work = _run(
        path,
        stamp,
        task,
      ).whenComplete(() => _tasks.remove(key));
    } else {
      task.listeners.add(isNeeded ?? () => true);
    }
    return task.work;
  }

  Future<AudioAnalysisResult?> _run(
    String path,
    FileStat before,
    _AnalysisTask task,
  ) async {
    if (_active < concurrency) {
      _active++;
    } else {
      final permit = Completer<void>();
      _waiting.add(permit);
      await permit.future;
    }
    try {
      // A screen may have moved on while waiting for a library decoder.
      // Do not start work for retired requests, or abandon a decoder's permit
      // on timeout while its native work is actually still running.
      if (!task.listeners.any((needed) => needed())) return null;
      final result = await _analyze(path);
      final after = await File(path).stat();
      if (after.type != FileSystemEntityType.file ||
          before.size != after.size ||
          before.modified != after.modified) {
        return null;
      }
      return result;
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}

class _AnalysisTask {
  final listeners = <bool Function()>[];
  late Future<AudioAnalysisResult?> work;
}
