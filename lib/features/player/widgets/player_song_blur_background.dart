import 'package:flutter/material.dart';

import 'package:flick/models/song.dart';

import 'artwork_gradient_backdrop.dart';
import 'artwork_mesh_blur_backdrop.dart';
import 'motion_art_frame_source.dart';
import 'motion_cover_blur.dart';

/// Crossfades the *complete* artwork-derived background between recordings.
///
/// The palette and preblurred mesh used to be updated separately: the palette
/// could switch before the next artwork finished decoding, exposing an abrupt
/// change despite each painter having its own fade. Keep the previous song's
/// entire composition on screen until its replacement has faded in.
///
/// This is shared by Fullcover (blur below the poster) and regular player
/// (blur around the cover). Do not key by palette: palette updates for the
/// *same* recording are already blended by ArtworkGradientBackdrop.
class PlayerSongBlurBackground extends StatelessWidget {
  const PlayerSongBlurBackground({
    super.key,
    required this.song,
    required this.colors,
    required this.fullCover,
    this.motionFrames,
  });

  final Song song;
  final List<Color> colors;
  final bool fullCover;
  final MotionArtFrameSource? motionFrames;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 1350),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, fade) => AnimatedBuilder(
        animation: fade,
        child: child,
        builder: (context, artwork) => FadeTransition(
          opacity: fade,
          // Hold the outgoing shader's last frame while compositing its
          // opacity out. Otherwise two full-speed mesh tickers run for the
          // entire transition and can cause precisely the skip jank this
          // crossfade is meant to remove.
          child: TickerMode(
            enabled: fade.status != AnimationStatus.reverse,
            child: artwork!,
          ),
        ),
      ),
      child: _SongBlurComposition(
        key: ValueKey(
          'player-blur:${song.id}:${song.albumArt}:${song.filePath}:$fullCover',
        ),
        song: song,
        colors: colors,
        fullCover: fullCover,
        motionFrames: motionFrames,
      ),
    );
  }
}

class _SongBlurComposition extends StatelessWidget {
  const _SongBlurComposition({
    super.key,
    required this.song,
    required this.colors,
    required this.fullCover,
    this.motionFrames,
  });
  final Song song;
  final List<Color> colors;
  final bool fullCover;
  final MotionArtFrameSource? motionFrames;

  @override
  Widget build(BuildContext context) {
    Widget composition() {
      final controller = motionFrames?.forKey('player:${song.id}');
      final live =
          controller != null &&
          controller.value.isInitialized &&
          !controller.value.hasError &&
          !controller.value.size.isEmpty;
      return Stack(
        fit: StackFit.expand,
        children: [
          TickerMode(
            enabled: !live,
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ArtworkGradientBackdrop(colors: colors, vibrant: true),
                  ArtworkMeshBlurBackdrop(
                    song: song,
                    preserveArtworkContrast: fullCover,
                  ),
                ],
              ),
            ),
          ),
          if (live)
            TweenAnimationBuilder<double>(
              key: ValueKey(controller),
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              child: MotionCoverBlur(
                controller: controller,
                fullCover: fullCover,
              ),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
            ),
        ],
      );
    }

    final frames = motionFrames;
    return frames == null
        ? composition()
        : AnimatedBuilder(animation: frames, builder: (_, __) => composition());
  }
}
