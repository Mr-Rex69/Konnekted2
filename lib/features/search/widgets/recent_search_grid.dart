import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/discovery/discovery_artwork.dart';

import '../providers/recent_search_tracks.dart';

class RecentSearchGrid extends ConsumerWidget {
  const RecentSearchGrid({
    super.key,
    required this.onSelected,
    this.headerSlivers = const <Widget>[],
  });
  final ValueChanged<RecentSearchTrack> onSelected;
  final List<Widget> headerSlivers;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(recentSearchTracksProvider);
    final library = ref.watch(konnektedLibraryProvider).value ?? const [];
    final t = context.lokal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
        final side = (constraints.maxWidth - 40 - 14 * (columns - 1)) / columns;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        return CustomScrollView(
          slivers: [
            ...headerSlivers,
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recently searched',
                        style: TextStyle(
                          color: t.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        ref.read(recentSearchTracksProvider.notifier).clear(),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                  mainAxisExtent: side + 10 + 44 * textScale,
                ),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final song = library
                      .where((song) => song.id == track.songId)
                      .firstOrNull;
                  return InkWell(
                    onTap: () => onSelected(track),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox.square(
                            dimension: side,
                            child: song != null
                                ? KonnektedArtwork(
                                    song: song,
                                    size: side,
                                    radius: 12,
                                  )
                                : DiscoveryArtwork(
                                    kind: DiscoveryArtworkKind.track,
                                    title: track.title,
                                    artist: track.artist,
                                    url: track.artwork ?? '',
                                    width: side,
                                    height: side,
                                    placeholder: ColoredBox(
                                      color: t.surface2,
                                      child: Center(
                                        child: Icon(
                                          Icons.music_note_rounded,
                                          color: t.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
