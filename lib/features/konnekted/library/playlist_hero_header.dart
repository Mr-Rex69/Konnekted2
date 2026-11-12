import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
const playlistHeroFirstOpenTapDelay = Duration(milliseconds: 350);
const playlistHeroWarmupTimeout = Duration(milliseconds: 1500);
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
      if (context.mounted) await WidgetsBinding.instance.endOfFrame;
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
    ..shuffle(
      math.Random(
        Object.hash(playlistId, _playlistHeroSessionSeed) & 0x7fffffff,
      ),
    );
  return shuffled.take(limit).toList(growable: false);
}

// Keep a few prepared banners for return navigation. Widgets own image clones,
// so evicting a cache entry cannot dispose an image still on screen.
final _preparedBanners = <String, Future<ui.Image>>{};

@visibleForTesting
void resetPreparedPlaylistBanners() {
  final images = _preparedBanners.values.toList();
  _preparedBanners.clear();
  for (final future in images) {
    unawaited(future.then((image) => image.dispose(), onError: (Object _) {}));
  }
}

String _bannerKey(
  BuildContext context,
  String playlistId,
  String? coverUrl,
  String? coverPath,
  Uint8List? coverBytes,
  List<PlaylistHeroCover> covers,
) =>
    '$playlistId|${MediaQuery.sizeOf(context)}|${MediaQuery.devicePixelRatioOf(context).clamp(1, 2)}|'
    '${context.lokal.bg.toARGB32()}|$coverUrl|$coverPath|${identityHashCode(coverBytes)}|'
    '${coverUrl?.isNotEmpty == true || coverPath?.isNotEmpty == true || coverBytes?.isNotEmpty == true ? '' : playlistHeroCoversForSession(playlistId, covers).map((cover) => '${cover.imagePath}:${cover.audioSourcePath}').join('|')}';

Future<ImageInfo?> _decodeBannerImage(
  ImageConfiguration configuration,
  ImageProvider provider,
) async {
  final stream = provider.resolve(configuration);
  final ready = Completer<ImageInfo?>();
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!ready.isCompleted) {
        ready.complete(info);
      } else {
        info.dispose();
      }
    },
    onError: (Object error, StackTrace? stack) {
      if (!ready.isCompleted) ready.complete(null);
    },
  );
  stream.addListener(listener);
  try {
    return await ready.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => null,
    );
  } finally {
    stream.removeListener(listener);
  }
}

Future<ImageProvider?> _bannerTileProvider(PlaylistHeroCover cover) async {
  var path = cover.imagePath.trim();
  if (!path.startsWith('http') &&
      (path.isEmpty || !await File(path).exists())) {
    final audio = cover.audioSourcePath;
    if (audio == null || audio.isEmpty) return null;
    try {
      path =
          await AlbumArtService.instance.resolveArtworkPath(
            existingPath: cover.imagePath,
            audioSourcePath: audio,
          ) ??
          '';
    } catch (_) {
      return null;
    }
  }
  if (path.isEmpty) return null;
  final ImageProvider provider = path.startsWith('http')
      ? NetworkImage(path)
      : FileImage(File(path));
  return ResizeImage.resizeIfNeeded(320, 320, provider);
}

Future<ui.Image> _prepareBanner(
  BuildContext context, {
  required String playlistId,
  String? coverUrl,
  String? coverPath,
  Uint8List? coverBytes,
  required List<PlaylistHeroCover> covers,
}) {
  final key = _bannerKey(
    context,
    playlistId,
    coverUrl,
    coverPath,
    coverBytes,
    covers,
  );
  final existing = _preparedBanners.remove(key);
  if (existing != null) {
    _preparedBanners[key] = existing;
    return existing;
  }
  final future = _renderBanner(
    context,
    playlistId: playlistId,
    coverUrl: coverUrl,
    coverPath: coverPath,
    coverBytes: coverBytes,
    covers: covers,
  );
  _preparedBanners[key] = future;
  while (_preparedBanners.length > 6) {
    final oldest = _preparedBanners.remove(_preparedBanners.keys.first)!;
    unawaited(oldest.then((image) => image.dispose(), onError: (Object _) {}));
  }
  return future;
}

Future<ui.Image> _renderBanner(
  BuildContext context, {
  required String playlistId,
  String? coverUrl,
  String? coverPath,
  Uint8List? coverBytes,
  required List<PlaylistHeroCover> covers,
}) async {
  // Capture context values before any asynchronous artwork work.
  final configuration = createLocalImageConfiguration(context);
  final width = MediaQuery.sizeOf(context).width;
  final height = playlistHeroHeightForScreen(MediaQuery.sizeOf(context).height);
  final scale = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
  final bg = context.lokal.bg;
  final surface = context.lokal.surface2;
  final sampled = playlistHeroCoversForSession(playlistId, covers);
  final images = <ImageInfo?>[];
  ImageInfo? primary;
  try {
    ImageProvider? provider;
    if (coverBytes != null && coverBytes.isNotEmpty) {
      provider = MemoryImage(coverBytes);
    } else if (coverPath?.isNotEmpty == true) {
      provider = coverPath!.startsWith('http')
          ? NetworkImage(coverPath)
          : FileImage(File(coverPath));
    } else if (coverUrl?.startsWith('https://') == true) {
      provider = NetworkImage(coverUrl!);
    }
    if (provider != null) {
      primary = await _decodeBannerImage(
        configuration,
        ResizeImage.resizeIfNeeded((width * scale).ceil(), null, provider),
      );
    }
    if (primary == null) {
      for (var i = 0; i < sampled.length; i += 3) {
        final providers = await Future.wait(
          sampled.skip(i).take(3).map(_bannerTileProvider),
        );
        images.addAll(
          await Future.wait(
            providers.map(
              (provider) async => provider == null
                  ? null
                  : _decodeBannerImage(configuration, provider),
            ),
          ),
        );
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    final bounds = Rect.fromLTWH(0, 0, width, height);
    canvas.drawRect(bounds, Paint()..color = bg);
    // Artwork is physically confined above the opaque lower surface. Nothing
    // textured can reach the sliver's fractional raster edge, on any backend.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, width, height * .84));
    canvas.drawRect(bounds, Paint()..color = surface);
    void drawCover(ui.Image image, Rect target) {
      final sizes = applyBoxFit(
        BoxFit.cover,
        Size(image.width.toDouble(), image.height.toDouble()),
        target.size,
      );
      final source = Alignment.center.inscribe(
        sizes.source,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
      canvas.drawImageRect(
        image,
        source,
        target,
        Paint()..filterQuality = FilterQuality.low,
      );
    }

    if (primary != null) {
      drawCover(primary.image, bounds);
    } else if (images.any((image) => image != null)) {
      final tile = (width * .34).clamp(105.0, 190.0);
      const gap = 14.0;
      final side = tile * 4 + gap * 3;
      canvas.translate(width / 2, height / 2);
      canvas.rotate(-.26);
      canvas.translate(-side / 2, -side / 2);
      for (var i = 0; i < 16; i++) {
        final image = images[i % images.length]?.image;
        if (image == null) continue;
        final target = Rect.fromLTWH(
          (i % 4) * (tile + gap),
          (i ~/ 4) * (tile + gap),
          tile,
          tile,
        );
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(target, const Radius.circular(16)),
        );
        drawCover(image, target);
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, height),
          [
            Colors.black.withValues(alpha: .38),
            Colors.black.withValues(alpha: .08),
            bg.withValues(alpha: 0),
            bg,
            bg,
          ],
          [0, .16, .36, .84, 1],
        ),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        (width * scale).ceil(),
        (height * scale).ceil(),
      );
    } finally {
      picture.dispose();
    }
  } finally {
    primary?.dispose();
    for (final image in images) {
      image?.dispose();
    }
  }
}

class _PreparedBanner extends StatefulWidget {
  const _PreparedBanner({required this.prepare});
  final Future<ui.Image> prepare;
  @override
  State<_PreparedBanner> createState() => _PreparedBannerState();
}

class _PreparedBannerState extends State<_PreparedBanner> {
  ui.Image? _image;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PreparedBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prepare != widget.prepare) _load();
  }

  void _load() {
    final generation = ++_generation;
    unawaited(
      widget.prepare.then((image) {
        if (!mounted || generation != _generation) return;
        final copy = image.clone();
        setState(() {
          _image?.dispose();
          _image = copy;
        });
      }, onError: (Object _) {}),
    );
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? ColoredBox(color: context.lokal.bg)
      : RawImage(
          image: _image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
        );
}

/// Decode and rasterize the exact banner before starting its first transition.
Future<void> precachePlaylistHeroArtwork(
  BuildContext context, {
  required String playlistId,
  String? coverUrl,
  String? coverPath,
  Uint8List? coverBytes,
  Iterable<PlaylistHeroCover> covers = const [],
}) async {
  await _prepareBanner(
    context,
    playlistId: playlistId,
    coverUrl: coverUrl,
    coverPath: coverPath,
    coverBytes: coverBytes,
    covers: covers.toList(),
  );
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
    final height = playlistHeroHeightForScreen(
      MediaQuery.sizeOf(context).height,
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: theme.bg),
          _PreparedBanner(
            prepare: _prepareBanner(
              context,
              playlistId: playlistId,
              coverUrl: coverUrl,
              coverPath: coverPath,
              coverBytes: coverBytes,
              covers: covers,
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
                                key: ValueKey(
                                  'playlist-collage-slot-${row * 4 + col}',
                                ),
                                imagePath:
                                    covers[(row * 4 + col) % covers.length]
                                        .imagePath,
                                audioSourcePath:
                                    covers[(row * 4 + col) % covers.length]
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
