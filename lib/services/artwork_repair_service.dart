import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import '../features/discovery/discovery_http.dart';
import '../core/utils/artist_credits.dart' show splitArtistCredits;
import 'album_art_import_service.dart';
import 'album_art_service.dart';
import 'artwork_pixel_validation.dart';
import 'graceful_http_client.dart';

/// An explicit maintenance operation, never a startup/background scan.
/// Only exact album/artist matches are eligible; user-selected artwork is
/// protected, and ambiguous catalogue editions are not guessed.
class ArtworkRepairProgress {
  const ArtworkRepairProgress({
    required this.total,
    required this.checked,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.running = false,
    this.cancelled = false,
  });
  final int total;
  final int checked;
  final int updated;
  final int skipped;
  final int failed;
  final bool running;
  final bool cancelled;
}

String repairIdentity(String value) =>
    value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// Use the album's lead credit instead of searching a combined feature list.
String repairLeadArtist(Song song) {
  final raw = song.albumArtist?.trim().isNotEmpty == true
      ? song.albumArtist!
      : song.artist;
  return splitArtistCredits(raw).firstOrNull ?? raw;
}

/// MediaStore/SAF audio is represented by a content URI, not an absolute
/// filesystem path. Those tracks must be eligible for cover repair as well.
bool isRepairableLocalSource(Song song) {
  final path = song.filePath ?? '';
  if (path.isEmpty || song.isNetworkSource) return false;
  final scheme = Uri.tryParse(path)?.scheme ?? '';
  return p.isAbsolute(path) || scheme == 'content' || scheme == 'file';
}

bool canRepairAlbum(Song song) {
  final album = repairIdentity(song.album ?? '');
  final artist = repairIdentity(repairLeadArtist(song));
  return album.isNotEmpty &&
      artist.isNotEmpty &&
      !const {
        'unknown album',
        'unknown',
        'untitled',
        'n/a',
        'various artists',
      }.contains(album) &&
      !const {'unknown artist', 'unknown', 'various artists'}.contains(artist);
}

/// A candidate must identify exactly the same album and album artist. Prefer
/// an unambiguous entry in a known catalogue, not the first fuzzy result.
AlbumArtCandidate? exactRepairCandidate(
  Song song,
  List<AlbumArtCandidate> candidates,
) {
  final album = repairIdentity(song.album ?? '');
  final artist = repairIdentity(repairLeadArtist(song));
  if (!canRepairAlbum(song)) return null;
  final exact = candidates
      .where(
        (candidate) =>
            repairIdentity(candidate.title) == album &&
            repairIdentity(
                  splitArtistCredits(candidate.artist).firstOrNull ??
                      candidate.artist,
                ) ==
                artist,
      )
      .toList();
  AlbumArtCandidate? unique(List<AlbumArtCandidate> matches) {
    final urls = matches.map((candidate) => candidate.imageUrl).toSet();
    if (urls.length == 1) return matches.first;
    if (urls.length < 2) return null;
    // The same album can have multiple editions in iTunes/MusicBrainz. Only
    // disambiguate when the locally tagged release year agrees with exactly
    // one candidate; otherwise leave the existing cover unchanged.
    final year = song.year;
    if (year == null || year <= 0) return null;
    final dated = matches
        .where((item) => item.releaseDate?.startsWith('$year') == true)
        .toList();
    return dated.map((item) => item.imageUrl).toSet().length == 1 &&
            dated.isNotEmpty
        ? dated.first
        : null;
  }

  for (final source in ['iTunes', 'Deezer', 'Cover Art Archive']) {
    final matches = exact
        .where((candidate) => candidate.sourceLabel == source)
        .toList();
    if (matches.isNotEmpty) return unique(matches);
  }
  // Other providers are used only when the edition is unambiguous.
  return unique(exact);
}

bool isCoverUpgrade({
  required int currentShortSide,
  required int newShortSide,
}) {
  return currentShortSide < 640 &&
      newShortSide >= 640 &&
      newShortSide >= currentShortSide * 1.5;
}

class ArtworkRepairService {
  ArtworkRepairService({
    SongRepository? repository,
    AlbumArtImportService? importer,
    http.Client? client,
  }) : _repository = repository ?? SongRepository(),
       _importer = importer ?? AlbumArtImportService.instance,
       _client = client ?? GracefulHttpClient(),
       _ownsClient = client == null;

  final SongRepository _repository;
  final AlbumArtImportService _importer;
  final http.Client _client;
  final bool _ownsClient;
  bool _cancel = false;
  bool _running = false;
  Completer<void>? _cancelRequest;

  void cancel() {
    _cancel = true;
    final request = _cancelRequest;
    if (request != null && !request.isCompleted) request.complete();
  }

  void dispose() {
    cancel();
    if (_ownsClient) _client.close();
  }

  Future<int?> _existingShortSide(
    Song song, {
    Map<String, int?>? measured,
  }) async {
    var path = song.albumArt;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      // A scanned content:// recording often has no filesystem art pointer
      // until embedded art is extracted. Resolve it once before deciding that
      // the original image is missing or low resolution.
      if (path != null &&
          (path.startsWith('http:') || path.startsWith('https:'))) {
        return null; // Unknown remote dimensions: never overwrite blindly.
      }
      try {
        path = await AlbumArtService.instance.resolveArtworkPath(
          existingPath: song.albumArt,
          audioSourcePath: song.filePath ?? '',
        );
      } catch (_) {
        return null; // Unreadable source: not evidence of missing art.
      }
      if (path == null) return 0;
    }
    // Multiple songs in an album often point to the same cover. Avoid
    // decoding the same 3000px image dozens of times during one manual scan.
    // Rechecks before committing bypass this cache to detect concurrent edits.
    if (measured != null && measured.containsKey(path)) return measured[path];
    final file = File(path);
    if (!await file.exists()) return 0;
    final length = await file.length();
    if (length <= 0 || length > 5 * 1024 * 1024) return null;
    final validated = await validateArtworkBytes(await file.readAsBytes());
    measured?[path] = validated?.shortSide;
    return validated?.shortSide;
  }

  Future<Uint8List?> _fetchArtwork(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    if (_cancel) return null;
    try {
      final builder = BytesBuilder(copy: false);
      await DiscoveryHttp(_client).transfer(
        uri,
        headers: const {'Accept': 'image/*'},
        maxBytes: artworkMaxBytes,
        deadline: const Duration(seconds: 12),
        onChunk: builder.add,
        cancel: _cancelRequest!.future,
        followArtworkRedirects: true,
      );
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  Future<ArtworkRepairProgress> refresh({
    required void Function(ArtworkRepairProgress) onProgress,
  }) async {
    if (_running) throw StateError('Artwork refresh already running');
    _running = true;
    _cancel = false;
    _cancelRequest = Completer<void>();
    var total = 0, checked = 0, updated = 0, skipped = 0, failed = 0;
    void report() => onProgress(
      ArtworkRepairProgress(
        total: total,
        checked: checked,
        updated: updated,
        skipped: skipped,
        failed: failed,
        running: _running,
        cancelled: _cancel,
      ),
    );
    try {
      final songs = await _repository.getAllSongs();
      final eligible = <String, List<Song>>{};
      for (final song in songs) {
        if (!isRepairableLocalSource(song) ||
            _importer.isCustomArtworkPath(song.albumArt) ||
            !canRepairAlbum(song)) {
          continue;
        }
        final key =
            '${repairIdentity(song.album!)}|'
            '${repairIdentity(repairLeadArtist(song))}';
        eligible.putIfAbsent(key, () => []).add(song);
      }
      total = eligible.values.fold<int>(
        0,
        (sum, tracks) => sum + tracks.length,
      );
      report();
      final measured = <String, int?>{};
      for (final group in eligible.values) {
        if (_cancel) break;
        final low = <(Song, int)>[];
        for (final song in group) {
          if (_cancel) break;
          try {
            final side = await _existingShortSide(song, measured: measured);
            if (side != null && side < 640) {
              low.add((song, side));
            } else {
              skipped++;
              checked++;
            }
          } catch (_) {
            failed++;
            checked++;
          }
          report();
        }
        if (_cancel || low.isEmpty) continue;
        AlbumArtCandidate? candidate;
        try {
          candidate = exactRepairCandidate(
            low.first.$1,
            await _importer.searchOnlineCandidates(low.first.$1),
          );
        } catch (_) {
          /* Offline catalogue: leave originals untouched. */
        }
        if (_cancel) break;
        if (candidate == null) {
          skipped += low.length;
          checked += low.length;
          report();
          continue;
        }
        final bytes = await _fetchArtwork(candidate.imageUrl);
        if (_cancel) break;
        if (bytes == null) {
          failed += low.length;
          checked += low.length;
          report();
          continue;
        }
        final newSide = (await validateArtworkBytes(bytes))?.shortSide ?? 0;
        final replacements = <Song>[];
        for (final (song, currentSide) in low) {
          if (_cancel) break;
          try {
            if (!isCoverUpgrade(
              currentShortSide: currentSide,
              newShortSide: newSide,
            )) {
              skipped++;
            } else {
              // Reload the row: the original Song is an immutable snapshot and
              // cannot reveal an artwork edit made during the network lookup.
              final latest = await _repository.getSongById(song.id);
              if (_cancel) break;
              if (latest == null ||
                  latest.filePath != song.filePath ||
                  latest.albumArt != song.albumArt ||
                  _importer.isCustomArtworkPath(latest.albumArt) ||
                  exactRepairCandidate(latest, [candidate]) == null ||
                  await _existingShortSide(latest) != currentSide) {
                skipped++;
                continue;
              }
              if (_cancel) break;
              replacements.add(latest);
            }
          } catch (_) {
            failed++;
          } finally {
            checked++;
            report();
          }
        }
        if (replacements.isNotEmpty && !_cancel) {
          try {
            // One durable image and one DB operation per album, not one
            // misleading custom override per song in the album.
            final result = await _importer.applyAutomaticRepair(
              songs: replacements,
              bytes: bytes,
            );
            updated += result.filePaths.length;
            skipped += replacements.length - result.filePaths.length;
          } catch (_) {
            failed += replacements.length;
          }
          report();
        }
        // One album request at a time, to avoid provider rate-limit bursts.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } finally {
      _running = false;
      _cancelRequest = null;
      report();
    }
    return ArtworkRepairProgress(
      total: total,
      checked: checked,
      updated: updated,
      skipped: skipped,
      failed: failed,
      cancelled: _cancel,
    );
  }
}
