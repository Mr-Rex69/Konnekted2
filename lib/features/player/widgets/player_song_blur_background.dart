import 'package:flutter/material.dart';

import 'package:flick/models/song.dart';
import 'artwork_gradient_backdrop.dart';
import 'artwork_mesh_blur_backdrop.dart';

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
  });

  final Song song;
  final List<Color> colors;
  final bool fullCover;

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
      transitionBuilder: (child, fade) => FadeTransition(
        opacity: fade,
        child: child,
      ),
      child: Stack(
        key: ValueKey(
          'player-blur:${song.id}:${song.albumArt}:${song.filePath}:$fullCover',
        ),
        fit: StackFit.expand,
        children: [
          ArtworkGradientBackdrop(colors: colors, vibrant: true),
          ArtworkMeshBlurBackdrop(
            song: song,
            preserveArtworkContrast: fullCover,
          ),
        ],
      ),
    );
  }
}
