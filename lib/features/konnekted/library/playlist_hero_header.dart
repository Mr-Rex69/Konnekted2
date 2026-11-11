import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_performance_scope.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/services/album_art_service.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/lokal/lokal_page_geometry.dart';

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

// A clock-only 80 ms delay did not warm the collage: decoding still happened
// during the route push. On the first tap, prepare the exact hero image-cache
// keys before starting the transition. Always bound the wait for offline art.
// Returning to the same playlist during this app session remains immediate.
const playlistHeroFirstOpenTapDelay = Duration(milliseconds: 220);
const playlistHeroWarmupTimeout = Duration(milliseconds: 650);
final Set<String> _openedPlaylistPages = <String>{};
final Set<String> _openingPlaylistPages = <String>{};

Future<void> openPlaylistAfterFirstTap(
  BuildContext context,
  String playlistId,
  Future<void> Function() open, {
  Future<void> Function()? prepareArtwork,
}) async {
  if (!_openingPlaylistPages.add(playlistId)) return;
  try {
    if (!_openedPlaylistPages.contains(playlistId)) {
      final minimumWait = Future<void>.delayed(playlistHeroFirstOpenTapDelay);
      if (prepareArtwork != null) {
        try {
          await prepareArtwork().timeout(playlistHeroWarmupTimeout);
        } catch (_) {
          // Invalid, missing, or offline artwork must not block navigation.
        }
      }
      await minimumWait;
    }
    if (!context.mounted) return;
    _openedPlaylistPages.add(playlistId);
    await open();
  } finally {
    _openingPlaylistPages.remove(playlistId);
  }
}

/// Sized against display height, not screen width, so the artwork never
/// dominates more than roughly a third of a phone's vertical viewport.
double playlistHeroHeightForScreen(double height) =>
    math.min(height * .34, 370.0);

/// One collapsing surface for artwork and navigation. The primary app bar
/// owns the system inset, so subsequent pinned search headers stack below
/// its toolbar rather than entering the status bar.
class PlaylistSliverHeader extends StatelessWidget {
  const PlaylistSliverHeader({
    super.key,
    required this.hero,
    required this.navigation,
  });

  final Widget hero;
  final Widget navigation;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final toolbarHeight =
        LokalPageGeometry.barHeight + LokalPageGeometry.barPadding.vertical;
    final expandedHeight = math.max(
      playlistHeroHeightForScreen(media.size.height) - media.padding.top,
      toolbarHeight + media.textScaler.scale(180),
    );
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      toolbarHeight: toolbarHeight,
      expandedHeight: expandedHeight,
      titleSpacing: 0,
      backgroundColor: context.lokal.bg,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      clipBehavior: Clip.hardEdge,
      title: SizedBox(
        key: const ValueKey('playlist-navigation'),
        height: toolbarHeight,
        child: navigation,
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: hero,
      ),
    );
  }
}

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

// Precache the same resized image providers that CachedImageWidget uses for
// the 320px collage thumbnails, so the subsequent route reuses decoded frames.
Future<void> _precacheHeroImage(
  BuildContext context,
  ImageProvider provider,
) async {
  if (!context.mounted) return;
  try {
    await precacheImage(
      provider,
      context,
      onError: (error, stackTrace) {},
    );
  } catch (_) {
    // A failed thumbnail is handled by the normal hero fallback.
  }
}

Future<void> _precacheHeroTile(
  BuildContext context,
  PlaylistHeroCover cover,
) async {
  var path = cover.imagePath.trim();
  if (!path.startsWith('http') &&
      (path.isEmpty || !(await File(path).exists()))) {
    final audioPath = cover.audioSourcePath?.trim();
    if (audioPath == null || audioPath.isEmpty) return;
    path = AlbumArtService.instance.cachedArtworkPathFor(audioPath) ?? '';
    if (path.isEmpty || !(await File(path).exists())) {
      try {
        path = await AlbumArtService.instance.resolveArtworkPath(
              existingPath: cover.imagePath,
              audioSourcePath: audioPath,
            ) ??
            '';
      } catch (_) {
        return;
      }
    }
  }
  if (path.isEmpty || !context.mounted) return;
  if (!path.startsWith('http') && !(await File(path).exists())) return;
  if (!context.mounted) return;
  final ImageProvider source =
      path.startsWith('http') ? NetworkImage(path) : FileImage(File(path));
  await _precacheHeroImage(
    context,
    ResizeImage.resizeIfNeeded(320, 320, source),
  );
}

/// Warm artwork on tap, not after the playlist page has begun sliding.
/// An explicit cover takes priority over the generated collage, just as in
/// PlaylistHeroHeader. The opening gate applies a deadline separately.
Future<void> precachePlaylistHeroArtwork(
  BuildContext context, {
  required String playlistId,
  String? coverUrl,
  String? coverPath,
  Uint8List? coverBytes,
  Iterable<PlaylistHeroCover> covers = const <PlaylistHeroCover>[],
}) async {
  if (!context.mounted) return;
  if (coverBytes != null && coverBytes.isNotEmpty) {
    await _precacheHeroImage(context, MemoryImage(coverBytes));
    return;
  }
  final localCover = coverPath?.trim() ?? '';
  if (localCover.isNotEmpty &&
      (localCover.startsWith('http') || await File(localCover).exists())) {
    if (!context.mounted) return;
    final physicalWidth =
        MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
    final requestedWidth = ((physicalWidth / 64).ceil() * 64).clamp(64, 2048);
    final decodeWidth = LokalPerformanceScope.of(context)
        ? requestedWidth.clamp(64, 768)
        : requestedWidth;
    final ImageProvider source = localCover.startsWith('http')
        ? NetworkImage(localCover)
        : FileImage(File(localCover));
    await _precacheHeroImage(
      context,
      ResizeImage.resizeIfNeeded(decodeWidth, null, source),
    );
    return;
  }
  final remoteCover = coverUrl?.trim() ?? '';
  if (remoteCover.startsWith('https://')) {
    await _precacheHeroImage(context, NetworkImage(remoteCover));
    return;
  }
  final sampled = playlistHeroCoversForSession(playlistId, covers);
  // Limit concurrent decodes/extractions while preparing the first frame.
  for (var i = 0; i < sampled.length; i += 3) {
    if (!context.mounted) return;
    await Future.wait([
      for (final cover in sampled.skip(i).take(3))
        _precacheHeroTile(context, cover),
    ]);
  }
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
          ColoredBox(color: theme.bg),
          // Fade the image itself to zero alpha before the sliver boundary.
          // Painting an opaque wash over an image at the same fractional
          // edge leaves a one-pixel fringe from their separate coverage.
          RepaintBoundary(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .36, .84, 1],
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                  Colors.transparent,
                ],
              ).createShader(bounds),
              child: image,
            ),
          ),
          // Contrast for the floating navigation; the lower surface is the
          // page background, without an overpainted joining strip.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, .16, .43, .84, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: .38),
                    Colors.black.withValues(alpha: .08),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.transparent,
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
class PlaylistDiagonalCollage extends StatelessWidget {
  const PlaylistDiagonalCollage({super.key, required this.covers});

  final List<PlaylistHeroCover> covers;

  @override
  Widget build(BuildContext context) {
    if (covers.isEmpty) {
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
                                imagePath: covers[
                                    (row * 4 + col) % covers.length].imagePath,
                                audioSourcePath: covers[
                                    (row * 4 + col) % covers.length].audioSourcePath,
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
        );
      },
    );
  }
}
