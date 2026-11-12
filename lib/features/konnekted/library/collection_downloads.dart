import 'dart:async';
import 'dart:io';

import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/playlist_links/playlist_link_models.dart';
import 'package:flick/features/playlist_links/playlist_unmatched_downloader.dart';
import 'package:flick/features/search/library_download.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:flick/services/remote_source_service.dart';

/// A playback cache is not an offline library download.
bool isOwnedCollectionFile(Song song) =>
    !song.isPending &&
    !song.isNetworkSource &&
    !song.isExternal &&
    !(song.sourcePackage?.startsWith('konnekted.') ?? false) &&
    song.filePath?.isNotEmpty == true &&
    !Uri.parse(song.filePath!).hasScheme;

/// Strict recording matches for catalogue references. Filesystem checks yield
/// instead of blocking frames, and lookups scan only one title.
class OfflineCollectionIndex {
  final Map<String, List<Song>> _titles = {};
  final Map<String, Song> _ids = {};

  static Future<OfflineCollectionIndex> build(
    List<Song> songs, {
    Future<bool> Function(String path)? exists,
  }) async {
    final index = OfflineCollectionIndex();
    final available = exists ?? (path) => File(path).exists();
    final owned = songs.where(isOwnedCollectionFile).toList();
    for (var offset = 0; offset < owned.length; offset += 32) {
      final batch = owned.skip(offset).take(32).toList();
      final present = await Future.wait(
        batch.map((song) => available(song.filePath!)),
      );
      for (var i = 0; i < batch.length; i++) {
        if (present[i]) index.add(batch[i]);
      }
    }
    return index;
  }

  void add(Song song) {
    _ids[song.id] = song;
    (_titles[titleKey(song.title)] ??= []).add(song);
  }

  Song? match(Song song) {
    final exact = _ids[song.id];
    if (exact != null) return exact;
    // Never map a CUE segment to a complete recording or stereo to Atmos.
    final candidates = (_titles[titleKey(song.title)] ?? const <Song>[])
        .where(
          (local) =>
              local.startOffsetMs == song.startOffsetMs &&
              local.endOffsetMs == song.endOffsetMs &&
              (!song.atmosEncoded || local.atmosEncoded) &&
              (song.duration <= Duration.zero ||
                  (local.duration - song.duration).abs() <=
                      const Duration(seconds: 2)) &&
              (recommendationKey(song.album).isEmpty ||
                  recommendationKey(local.album).isEmpty ||
                  recommendationKey(local.album) ==
                      recommendationKey(song.album)),
        )
        .toList();
    return recommendationMatch(
      RecommendationCandidate(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration > Duration.zero ? song.duration : null,
      ),
      candidates,
      (local) => RecommendationCandidate(
        title: local.title,
        artist: local.artist,
        album: local.album,
        duration: local.duration,
      ),
    );
  }

  /// Keep membership, hearts and their order under the stored reference ID.
  Song resolve(Song song) => match(song)?.copyWith(id: song.id) ?? song;
}

class CollectionDownloadProgress {
  const CollectionDownloadProgress({
    required this.total,
    this.completed = 0,
    this.saved = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
    this.status = '',
    this.lastError,
  });
  final int total, completed, saved, skipped, failed;
  final bool cancelled;
  final String status;
  final String? lastError;
  String get summary =>
      'Downloaded $saved · Skipped $skipped · Unavailable $failed'
      '${cancelled ? ' · Stopped' : ''}';
}

typedef CollectionSongDownload = Future<Song> Function(
  Song song, {
  required Future<void> cancel,
  required bool Function() cancelled,
  required void Function(String) onStatus,
});

/// Sequential, cancellable work shared by local playlists and Likes. Collection
/// membership is never rewritten from a potentially stale page snapshot.
class CollectionDownloader {
  CollectionDownloader({
    required this.library,
    required this.download,
    this.exists,
  });
  final Future<List<Song>> Function() library;
  final CollectionSongDownload download;
  final Future<bool> Function(String)? exists;

  Future<CollectionDownloadProgress> run(
    List<Song> songs, {
    required Future<void> cancel,
    required bool Function() cancelled,
    required void Function(CollectionDownloadProgress) onProgress,
  }) async {
    final index = await OfflineCollectionIndex.build(
      await library(),
      exists: exists,
    );
    var saved = 0, skipped = 0, failed = 0, completed = 0;
    String? lastError;
    final seen = <String>{};
    final copies = <String, Song>{};
    CollectionDownloadProgress report([String status = '']) {
      final state = CollectionDownloadProgress(
        total: songs.length,
        completed: completed,
        saved: saved,
        skipped: skipped,
        failed: failed,
        cancelled: cancelled(),
        status: status,
        lastError: lastError,
      );
      onProgress(state);
      return state;
    }

    report();
    for (final song in songs) {
      if (cancelled()) break;
      try {
        if (copies.containsKey(song.id) || index.match(song) != null) {
          skipped++;
        } else if (!seen.add(song.id)) {
          skipped++;
        } else {
          report('Downloading ${song.title}…');
          final local = await download(
            song,
            cancel: cancel,
            cancelled: cancelled,
            onStatus: report,
          );
          // An original desktop transfer may complete after Stop was pressed.
          // Count and retain that finished file, then stop before the next song.
          copies[song.id] = local;
          index.add(local);
          saved++;
        }
      } catch (error) {
        if (cancelled()) break;
        failed++;
        lastError = error.toString();
      }
      completed++;
      report();
    }
    return report();
  }
}

CollectionDownloader collectionDownloader({
  Future<bool> Function(OnlineSource source)? verifySource,
}) => CollectionDownloader(
  library: () => SongRepository().getAllSongs(),
  download:
      (song, {required cancel, required cancelled, required onStatus}) async {
        final repository = SongRepository();
        if (song.sourceType == 'lokal') {
          await LokalDesktopSource.instance.downloadToPhone(song);
          final local = await repository.getSongById(song.id);
          if (local == null || !isOwnedCollectionFile(local)) {
            throw StateError('The desktop copy could not be saved.');
          }
          return local;
        }
        LibraryDownloadResult result;
        if (song.isNetworkSource) {
          final path = await RemoteSourceService.instance.ensureLocal(
            song,
            reportProgress: false,
          );
          if (cancelled()) throw StateError('Download stopped.');
          result = await LibraryDownloader().save(
            song.copyWith(filePath: path),
          );
        } else {
          final videoId = song.remoteId?.replaceFirst(RegExp(r'^yt:'), '');
          final youtube =
              videoId != null &&
              RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) &&
              (song.remoteId!.startsWith('yt:') ||
                  song.sourceDisplayName == 'YouTube Music');
          result = await const PlaylistUnmatchedDownloader().download(
            youtube
                ? ParsedPlaylistLink(
                    source: PlaylistLinkSource.youtube,
                    remoteId: videoId,
                    canonicalUrl: 'https://www.youtube.com/watch?v=$videoId',
                  )
                : null,
            RemotePlaylistEntry(
              title: song.title,
              artist: song.artist,
              album: song.album,
              duration: song.duration > Duration.zero ? song.duration : null,
              remoteId: youtube ? videoId : null,
            ),
            cancel: cancel,
            cancelled: cancelled,
            onStatus: onStatus,
            verifySource: verifySource,
            requireAtmos: song.atmosEncoded,
            save: (ready) {
              if (song.duration > Duration.zero &&
                  ready.duration > Duration.zero &&
                  (ready.duration - song.duration).abs() >
                      const Duration(seconds: 2)) {
                throw StateError(
                  'The downloaded recording has a different duration.',
                );
              }
              return LibraryDownloader().save(
                ready.copyWith(
                  title: song.title,
                  artist: song.artist,
                  album: song.album,
                ),
                artwork: song.albumArt,
              );
            },
          );
        }
        final local = await repository.getSongByFilePath(result.path);
        if (local == null) {
          throw StateError('The downloaded file is missing from the library.');
        }
        return local;
      },
);
