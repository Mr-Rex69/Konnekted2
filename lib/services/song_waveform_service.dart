import 'dart:io';

import '../data/entities/song_audio_cache_entity.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import '../src/rust/api/audio_analysis.dart';
import 'audio_analysis_queue.dart';
import 'music_folder_service.dart';
import 'network_cache_service.dart';

typedef WaveformCacheReader = Future<SongAudioCacheEntity?> Function(Song song);
typedef WaveformCacheWriter = Future<void> Function(
  Song song,
  SongAudioCacheEntity cache,
);
typedef WaveformFileResolver = Future<String?> Function(Song song);

/// Resolves only existing audio: never downloads a stream just to paint it.
/// The playback engine, its output path and its clock remain independent.
class SongWaveformService {
  SongWaveformService({
    WaveformCacheReader? readCache,
    WaveformCacheWriter? writeCache,
    WaveformFileResolver? resolveFile,
    AudioAnalysisQueue? analysis,
  }) : _readCache = readCache ?? _readLibraryCache,
       _writeCache = writeCache ?? _writeLibraryCache,
       _resolveFile = resolveFile ?? existingAudioFile,
       _analysis = analysis ?? AudioAnalysisQueue.instance;

  static final instance = SongWaveformService();
  final WaveformCacheReader _readCache;
  final WaveformCacheWriter _writeCache;
  final WaveformFileResolver _resolveFile;
  final AudioAnalysisQueue _analysis;
  final _jobs = <(String?, String?, int?, String?), _WaveformJob>{};
  final _memory = <(String, int, int), AudioAnalysisResult>{};

  static bool validPeaks(List<double>? peaks) =>
      peaks != null &&
      peaks.length > 1 &&
      peaks.every((value) => value.isFinite && value >= 0);

  Future<List<double>?> load(Song song, {bool Function()? isCurrent}) async {
    final current = isCurrent ?? () => true;
    // The existing analyzer describes the whole file, not a CUE excerpt.
    if (song.filePath?.isNotEmpty != true ||
        song.isPending ||
        song.startOffsetMs != null ||
        song.endOffsetMs != null)
      return null;
    try {
      SongAudioCacheEntity? cached;
      try {
        cached = await _readCache(song);
      } catch (_) {}
      if (!current()) return null;
      if (cached != null && validPeaks(cached.peaks)) {
        final local = _plainFile(song.filePath!);
        final stat = local == null ? null : await File(local).stat();
        if (stat == null ||
            (stat.type == FileSystemEntityType.file &&
                stat.modified.millisecondsSinceEpoch <= cached.computedAt)) {
          return cached.peaks;
        }
      }
      if (song.isDsd || song.isWavPack) return null;
      final key = (
        song.filePath,
        song.sourceType,
        song.remoteServerId,
        song.remoteId,
      );
      var job = _jobs[key];
      if (job == null) {
        job = _WaveformJob();
        job.listeners.add(current);
        _jobs[key] = job;
        job.work = _prepare(song, job).whenComplete(() => _jobs.remove(key));
      } else {
        job.listeners.add(current);
      }
      final result = await job.work;
      if (!current() || result == null || !validPeaks(result.peaks))
        return null;
      final id = int.tryParse(song.id);
      if (id != null && !song.isExternal) {
        try {
          await _writeCache(
            song,
            SongAudioCacheEntity()
              ..songId = id
              ..peaks = result.peaks.toList()
              ..lufs = result.lufs
              ..truePeakDb = result.truePeakDb
              ..dr = result.dr
              ..lra = result.lra
              ..clipping = result.clipping
              ..version = AudioAnalysisQueue.cacheVersion
              ..computedAt = job.startedAt,
          );
        } catch (_) {
          /* A failed cache write must not hide a ready waveform. */
        }
      }
      return result.peaks.toList();
    } catch (_) {
      // Revoked grants, evicted downloads and unsupported codecs use the
      // ordinary seek line. Never invent peaks or interrupt playback.
      return null;
    }
  }

  Future<AudioAnalysisResult?> _prepare(Song song, _WaveformJob job) async {
    if (!job.needed) return null;
    final path = await _resolveFile(song);
    if (path == null || !job.needed) return null;
    final stamp = await File(path).stat();
    if (stamp.type != FileSystemEntityType.file ||
        stamp.size == 0 ||
        path.endsWith('.part') ||
        path.endsWith('.tmp'))
      return null;
    final key = (path, stamp.size, stamp.modified.microsecondsSinceEpoch);
    final remembered = _memory.remove(key);
    if (remembered != null) {
      _memory[key] = remembered;
      return remembered;
    }
    final result = await _analysis.analyze(path, isNeeded: () => job.needed);
    if (result != null && validPeaks(result.peaks)) {
      _memory[key] = result;
      while (_memory.length > 24) {
        _memory.remove(_memory.keys.first);
      }
    }
    return result;
  }

  static String? _plainFile(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return null;
    if (uri.scheme == 'file') return uri.toFilePath();
    return uri.scheme.isEmpty ? source : null;
  }

  static Future<String?> existingAudioFile(Song song) async {
    final source = song.filePath;
    if (source == null) return null;
    final local = _plainFile(source);
    if (local != null) return local;
    if (Uri.tryParse(source)?.scheme == 'content') {
      return MusicFolderService().cacheUriForPlayback(
        source,
        extensionHint: song.fileType.toLowerCase(),
      );
    }
    final server = song.remoteServerId, remote = song.remoteId;
    if (song.isNetworkSource && server != null && remote != null) {
      return NetworkCacheService().getPath(server, remote, touch: false);
    }
    return null;
  }

  static Future<SongAudioCacheEntity?> _readLibraryCache(Song song) async {
    if (int.tryParse(song.id) == null || song.isExternal) return null;
    return SongRepository().getAudioCacheForSong(song);
  }

  static Future<void> _writeLibraryCache(
    Song song,
    SongAudioCacheEntity cache,
  ) => SongRepository().upsertAudioCacheForSong(song, cache);
}

class _WaveformJob {
  final listeners = <bool Function()>[];
  final startedAt = DateTime.now().millisecondsSinceEpoch;
  bool get needed => listeners.any((current) => current());
  late Future<AudioAnalysisResult?> work;
}
