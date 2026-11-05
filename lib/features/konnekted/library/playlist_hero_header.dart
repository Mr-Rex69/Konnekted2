import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';

/// Album artwork sources for the shared local/Spotify/YouTube playlist hero.
/// [audioSourcePath] supports local files with embedded, not-yet-extracted art.
@immutable
class PlaylistHeroCover {
  const PlaylistHeroCover({required this.imagePath, this.audioSourcePath});

  final String imagePath;
  final String? audioSourcePath;
}

/// One seed for each app process. Navigating between pages retains the same
/// selection; force-closing and relaunching changes the artwork arrangement.
final int _playlistHeroSessionSeed = math.Random().nextInt(0x7fffffff);

// Each playlist's generated collage is staged only once per app session.
// This gives its newly shuffled thumbnail set a short head start on decoding.
const playlistHeroFirstRevealDelay = Duration(milliseconds: 350);
final Set<String> _revealedPlaylistCollages = <String>{};

/// Sized against display height, not screen width, so the artwork never
/// dominates more than roughly a third of a phone's vertical viewport.
double playlistHeroHeightForScreen(double height) =>
    math.min(height * .34, 370.0);

List<PlaylistHeroCover> playlistHeroCoversForSession(
  String playlistId,
  Iterable<PlaylistHeroCover> candidates, {
  int limit = 12,
}) {
  final unique = <String, PlaylistHeroCover>{};
  for (final cover in candidates) {
    final path = cover.imagePath.trim();
    final audio = cover.audioSourcePath?.trim() ?? '';
    if (path.isEmpty && audio.isEmpty) continue;
    final key = path.isNotEmpty ? path : 'embedded:$audio';
    unique.putIfAbsent(key, () => cover);
  }
  final selected = unique.values.toList(growable: false);
  if (selected.isEmpty) return const [];
  final shuffled = List<PlaylistHeroCover>.of(selected)
    ..shuffle(math.Random(
      Object.hash(playlistId, _playlistHeroSessionSeed) & 0x7fffffff,
    ));
  return shuffled.take(limit).toList(growable: false);
}

/// Full-width, gradient-faded playlist art and title. A dedicated playlist
/// cover always wins; only missing/failed cover requests show the collage.
class PlaylistHeroHeader extends StatelessWidget {
  const PlaylistHeroHeader({
    super.key,
    required this.playlistId,
    required this.title,
    required this.metadata,
    required this.covers,
    this.owner,
    this.coverUrl,
    this.coverPath,
    this.coverBytes,
  });

  final String playlistId;
  final String title;
  final String metadata;
  final String? owner;
  final String? coverUrl;
  final String? coverPath;
  final Uint8List? coverBytes;
  final List<PlaylistHeroCover> covers;

  @override
  Widget build(BuildContext context) {
    final theme = context.lokal;
    final width = MediaQuery.sizeOf(context).width;
    // The hero occupies at most ~34% of the screen, including the status
    // bar. Its image extends behind system chrome rather than starting below it.
    final height = playlistHeroHeightForScreen(MediaQuery.sizeOf(context).height);
    final sampled = playlistHeroCoversForSession(playlistId, covers);
    final fallback = PlaylistDiagonalCollage(
      key: ValueKey('playlist-art:$playlistId'),
      playlistId: playlistId,
      covers: sampled,
    );
    final cover = coverUrl?.trim();
    final localCover = coverPath?.trim();
    final image = coverBytes != null && coverBytes!.isNotEmpty
        ? Image.memory(
            coverBytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          )
        : localCover != null && localCover.isNotEmpty
            ? CachedImageWidget(
                imagePath: localCover,
                fit: BoxFit.cover,
                placeholder: ColoredBox(color: theme.surface2),
                errorWidget: fallback,
              )
            : cover != null && cover.startsWith('https://')
                ? Image.network(
                    cover,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => fallback,
                  )
                : fallback;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: image),
          // The art keeps its color; only the lower edge blends into the page.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, .16, .43, .74, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: .38),
                    Colors.black.withValues(alpha: .08),
                    Colors.transparent,
                    theme.bg.withValues(alpha: .73),
                    theme.bg,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: width < 390 ? 38 : 44,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.9,
                      height: 1.08,
                    ),
                  ),
                ),
                if (owner != null && owner!.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    owner!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.muted, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 9),
                Text(
                  metadata,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A static, session-varied diagonal collage. Rounded thumbnails are
/// clipped once and remain stationary; no AnimationController or per-frame
/// widget builds. The sample changes on next process launch, not mid-session.
class PlaylistDiagonalCollage extends StatefulWidget {
  const PlaylistDiagonalCollage({
    super.key,
    required this.playlistId,
    required this.covers,
  });

  final String playlistId;
  final List<PlaylistHeroCover> covers;

  @override
  State<PlaylistDiagonalCollage> createState() =>
      _PlaylistDiagonalCollageState();
}

class _PlaylistDiagonalCollageState extends State<PlaylistDiagonalCollage> {
  Timer? _revealTimer;
  late bool _artworkVisible;

  @override
  void initState() {
    super.initState();
    _scheduleFirstReveal();
  }

  void _scheduleFirstReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _artworkVisible = widget.covers.isEmpty ||
        _revealedPlaylistCollages.contains(widget.playlistId);
    if (_artworkVisible) return;

    // Build the selected images immediately, but hold back their presentation
    // briefly on the first visit so the collage does not assemble visibly.
    _revealTimer = Timer(playlistHeroFirstRevealDelay, () {
      if (!mounted) return;
      _revealedPlaylistCollages.add(widget.playlistId);
      setState(() => _artworkVisible = true);
    });
  }

  @override
  void didUpdateWidget(covariant PlaylistDiagonalCollage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistId != widget.playlistId ||
        oldWidget.covers.isEmpty != widget.covers.isEmpty) {
      _scheduleFirstReveal();
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.covers.isEmpty) {
      return ColoredBox(
        color: context.lokal.surface2,
        child: Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: 72,
            color: context.lokal.muted,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Smaller squares show more artwork without crowding the shortened hero.
        final tile = (width * .34).clamp(105.0, 190.0);
        const gap = 14.0;
        final side = tile * 4 + gap * 3;
        final raster = RepaintBoundary(
          child: Transform.rotate(
            angle: -.26,
            child: SizedBox.square(
              dimension: side,
              child: Column(
                children: [
                  for (var row = 0; row < 4; row++) ...[
                    if (row != 0) const SizedBox(height: gap),
                    Row(
                      children: [
                        for (var col = 0; col < 4; col++) ...[
                          if (col != 0) const SizedBox(width: gap),
                          SizedBox.square(
                            dimension: tile,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedImageWidget(
                                key: ValueKey('playlist-collage-slot-${row * 4 + col}'),
                                imagePath:
                                    widget.covers[(row * 4 + col) % widget.covers.length].imagePath,
                                audioSourcePath:
                                    widget.covers[(row * 4 + col) % widget.covers.length]
                                        .audioSourcePath,
                                width: tile,
                                height: tile,
                                useThumbnail: true,
                                thumbnailWidth: 320,
                                thumbnailHeight: 320,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
        return ClipRect(
          child: ColoredBox(
            color: context.lokal.surface2,
            child: AnimatedOpacity(
              key: ValueKey('playlist-collage-reveal:${widget.playlistId}'),
              opacity: _artworkVisible ? 1 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: Center(
                child: OverflowBox(
                minWidth: side,
                maxWidth: side,
                minHeight: side,
                maxHeight: side,
                  child: raster,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
