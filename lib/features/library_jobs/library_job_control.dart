import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/library/artist_follow_store.dart';

import 'library_jobs.dart';

class LibraryJobControl extends ConsumerWidget {
  const LibraryJobControl(this.job, {super.key});
  final LibraryJob job;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(libraryJobsProvider);
    final library = ref.watch(konnektedLibraryProvider);
    final active = status.job == job && status.running;
    final hasLocalSongs = library.value?.isNotEmpty == true;
    final hasFollowedArtists =
        job == LibraryJob.artists && ArtistFollowStore.instance.knownNames.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  icon: Icon(
                    active
                        ? Icons.hourglass_top_rounded
                        : Icons.refresh_rounded,
                  ),
                  label: Text(active ? status.message : job.label),
                  onPressed:
                      status.running || (!hasLocalSongs && !hasFollowedArtists)
                      ? null
                      : () => unawaited(
                          ref
                              .read(libraryJobsProvider.notifier)
                              .start(job, library.value ?? const []),
                        ),
                ),
              ),
              if (active)
                TextButton(
                  onPressed: () =>
                      ref.read(libraryJobsProvider.notifier).cancel(),
                  child: const Text('Stop'),
                ),
            ],
          ),
          if (active)
            LinearProgressIndicator(
              value: status.total > 0 ? status.done / status.total : null,
              color: context.lokal.accent,
            ),
          if (!active && status.job == job && status.done > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                status.message,
                style: TextStyle(color: context.lokal.text, fontSize: 12),
              ),
            ),
          if (!active)
            Text(
              job == LibraryJob.videos
                  ? 'Search YouTube Music for official videos of your library songs.'
                  : job == LibraryJob.releases
                  ? 'Refresh album release data and upgrade low-resolution local album covers. Hand-picked artwork stays intact.'
                  : 'Refresh artist metadata and portraits for library and followed artists. Local tags stay unchanged.',
              style: TextStyle(color: context.lokal.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
