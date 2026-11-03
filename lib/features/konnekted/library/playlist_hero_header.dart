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
    final height = (width * 1.04).clamp(310.0, 520.0);
    final sampled = playlistHeroCoversForSession(playlistId, covers);
    final fallback = PlaylistDiagonalCollage(
      key: ValueKey('playlist-art:$playlistId'),
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
                  stops: const [0.0, .38, .72, 1.0],
                  colors: [
                    theme.bg.withValues(alpha: .05),
                    theme.bg.withValues(alpha: .12),
                    theme.bg.withValues(alpha: .80),
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

/// Four staggered columns rotating as one composited layer. Only the outer
/// transform changes per frame; album thumbnails are cached and static.
class PlaylistDiagonalCollage extends StatefulWidget {
  const PlaylistDiagonalCollage({super.key, required this.covers});

  final List<PlaylistHeroCover> covers;

  @override
  State<PlaylistDiagonalCollage> createState() =>
      _PlaylistDiagonalCollageState();
}

class _PlaylistDiagonalCollageState extends State<PlaylistDiagonalCollage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 34),
    value: .5,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
      _drift.value = .5;
    } else if (!_drift.isAnimating) {
      _drift.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final covers = widget.covers;
    if (covers.isEmpty) {
      return ColoredBox(
        color: context.lokal.surface2,
        child: Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: 84,
            color: context.lokal.muted,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tile = (width * .48).clamp(120.0, 230.0);
        const gap = 14.0;
        final side = tile * 4 + gap * 3;
        final tiles = <Widget>[
          for (var index = 0; index < 16; index++)
            SizedBox.square(
              dimension: tile,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CachedImageWidget(
                  key: ValueKey('playlist-collage-slot-$index'),
                  imagePath: covers[index % covers.length].imagePath,
                  audioSourcePath:
                      covers[index % covers.length].audioSourcePath,
                  width: tile,
                  height: tile,
                  useThumbnail: true,
                  thumbnailWidth: 320,
                  thumbnailHeight: 320,
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ];
        // The collage is larger than the viewport in both directions; slow
        // motion therefore never reveals a blank edge.
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
                          tiles[row * 4 + col],
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
            child: Center(
              child: AnimatedBuilder(
                animation: _drift,
                child: raster,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    (_drift.value - .5) * 50,
                    (_drift.value - .5) * 66,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
