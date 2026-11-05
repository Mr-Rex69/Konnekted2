import 'dart:async';

import 'artist_metadata.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flick/features/music_videos/music_video_providers.dart';
import 'package:flick/features/konnekted/library/lokal_library_groups.dart';
import 'package:flick/features/konnekted/library/artist_follow_store.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/features/konnekted/library/lokal_online_catalogue.dart';
import 'package:flick/services/apple_music/apple_music_metadata_service.dart';
import 'package:flick/services/apple_music/apple_artist_visuals_service.dart';
import 'package:flick/services/artwork_repair_service.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/models/song.dart';

enum LibraryJob {
  videos('Find music videos'),
  releases('Refresh album info and covers'),
  artists('Refresh artist info');

  const LibraryJob(this.label);
  final String label;
}

class LibraryJobStatus {
  const LibraryJobStatus({
    this.job,
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.failed = 0,
    this.updated = 0,
    this.cancelled = false,
  });
  final LibraryJob? job;
  final bool running, cancelled;
  final int done, total, failed, updated;
  String get message =>
      '${job?.label ?? 'Library job'} · $done/$total${running
          ? ''
          : cancelled
          ? ' · Stopped'
          : ' · Finished'}${job == LibraryJob.artists ? ' · $updated artist assets refreshed' : job == LibraryJob.releases ? ' · $updated covers upgraded' : ''}${failed > 0 ? ' · $failed unavailable' : ''}';
}

/// Predictable manual-refresh sequence, including followed artists without
/// local tracks. Preserve the library spelling on duplicate credits.
@visibleForTesting
List<String> alphabeticalArtistRefreshNames(
  Iterable<String> libraryNames,
  Iterable<String> followedNames,
) {
  final unique = <String, String>{};
  for (final raw in [...libraryNames, ...followedNames]) {
    final name = raw.trim();
    final key = recommendationKey(name);
    if (key.isNotEmpty) unique.putIfAbsent(key, () => name);
  }
  return unique.values.toList()
    ..sort((a, b) {
      final order = a.toLowerCase().compareTo(b.toLowerCase());
      return order != 0 ? order : a.compareTo(b);
    });
}

/// Explicit, serial metadata jobs. They update the metadata service's disk
/// cache without rewriting local audio tags or starting work in the background.
class LibraryJobs extends Notifier<LibraryJobStatus> {
  bool _cancel = false;
  ArtworkRepairService? _activeRepair;
  @override
  LibraryJobStatus build() {
    ref.onDispose(() {
      _cancel = true;
      _activeRepair?.cancel();
    });
    ref.listen(musicVideoIndexProvider, (previous, next) {
      if (next.scanning || previous?.scanning == true) {
        state = LibraryJobStatus(
          job: LibraryJob.videos,
          running: next.scanning,
          done: next.done,
          total: next.total,
          cancelled: !next.scanning && next.done < next.total,
        );
      }
    });
    return const LibraryJobStatus();
  }

  void cancel() {
    _cancel = true;
    _activeRepair?.cancel();
    if (state.job == LibraryJob.videos) {
      ref.read(musicVideoIndexProvider.notifier).cancel();
    }
  }

  Future<void> start(LibraryJob job, List<Song> songs) async {
    if (state.running) return;
    if (job == LibraryJob.videos) {
      state = const LibraryJobStatus(job: LibraryJob.videos, running: true);
      try {
        await ref.read(musicVideoIndexProvider.notifier).scan(songs);
        if (ref.mounted && state.running) {
          state = LibraryJobStatus(
            job: job,
            done: state.done,
            total: state.total,
          );
        }
      } catch (_) {
        if (ref.mounted) {
          state = LibraryJobStatus(
            job: job,
            done: state.done,
            total: state.total,
            failed: 1,
          );
        }
      }
      return;
    }
    // Merge before sorting: imported Spotify/followed artists otherwise ran
    // after every library artist, making manual refresh appear out of order.
    final artistNames = alphabeticalArtistRefreshNames(
      job == LibraryJob.releases
          ? lokalAlbums(songs).map((album) => album.albumArtist)
          : lokalArtists(songs).map((artist) => artist.name),
      job == LibraryJob.artists
          ? ArtistFollowStore.instance.knownNames
          : const <String>[],
    );
    _cancel = false;
    var done = 0, failed = 0, updated = 0;
    var total = artistNames.length;
    void publish(bool running) {
      if (ref.mounted) {
        state = LibraryJobStatus(
          job: job,
          running: running,
          done: done,
          total: total,
          failed: failed,
          updated: updated,
          cancelled: _cancel,
        );
      }
    }

    publish(true);
    try {
      if (job == LibraryJob.releases && !_cancel && ref.mounted) {
        // Upgrade existing covers first, so large libraries don't wait for
        // hundreds of optional Apple Music release lookups before seeing a
        // single improved image. Album metadata refresh follows afterward.
        final artistDone = done;
        final artistFailures = failed;
        final repair = ArtworkRepairService();
        _activeRepair = repair;
        try {
          final result = await repair.refresh(onProgress: (progress) {
            total = artistNames.length + progress.total;
            done = artistDone + progress.checked;
            failed = artistFailures + progress.failed;
            updated = progress.updated;
            publish(true);
          });
          if (result.updated > 0 && ref.mounted) {
            // The list and album pages use live Song objects, not a lookup
            // cache; invalidate them after durable cover paths are saved.
            ref.invalidate(songsProvider);
            ref.invalidate(songsByAlbumProvider);
          }
        } catch (_) {
          failed++;
        } finally {
          _activeRepair = null;
          repair.dispose();
        }
      }
      for (final artistName in artistNames) {
        if (_cancel || !ref.mounted) break;
        try {
          final api = AppleMusicMetadataService.instance;
          if (job == LibraryJob.releases) {
            final releases = await api.searchAlbums(
              artistName,
              limit: 100,
              refresh: true,
            );
            if (releases.isEmpty) failed++;
          } else {
            final info = await api.getArtistData(artistName, refresh: true);
            if (info == null) {
              failed++;
            } else {
              final portraitSaved = await ref
                  .read(artistMetadataProvider.notifier)
                  .storeRefreshedPortrait(artistName, info.info?.imageUrl);
              // The logo is now part of the explicit artist refresh. Also
              // works for Spotify follows with no local recordings.
              var logoSaved = false;
              try {
                logoSaved = await AppleArtistVisualsService.instance
                    .refreshFromArtistData(artistName, info);
              } catch (_) {
                // No logo endpoint must not invalidate an existing portrait.
              }
              if (portraitSaved || logoSaved) {
                updated++;
              } else {
                failed++;
              }
            }
          }
          LokalOnlineCatalogue.instance.invalidateArtist(artistName);
        } catch (_) {
          failed++;
        }
        done++;
        publish(true);
        // An unavailable catalogue entry must not abort the user's refresh.
        if (!_cancel) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      publish(false);
    }
  }
}

final libraryJobsProvider = NotifierProvider<LibraryJobs, LibraryJobStatus>(
  LibraryJobs.new,
);
