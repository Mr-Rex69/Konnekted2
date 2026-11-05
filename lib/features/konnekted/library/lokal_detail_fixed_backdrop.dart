import 'package:flutter/material.dart';

/// The full-resolution hero remains sharp, with no image-local blur or narrow
/// feather strip. The page draws its separate wash and fixed progressive top
/// frost *above* the artwork in the outer UI Stack.
class LokalDetailFixedBackdrop extends StatelessWidget {
  const LokalDetailFixedBackdrop({
    super.key,
    required this.artwork,
    required this.background,
  });

  final Widget artwork;
  final Color background;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: background),
          RepaintBoundary(child: artwork),
        ],
      ),
    ),
  );
}

/// BitChord-style easing into the page surface, rendered as a foreground UI
/// layer rather than modifying the image. The long ramp hides the seam
/// between the hero and the opaque content without a visibly blurred band.
///
/// Live or animated artwork remains untouched; the same wash works for video.
class LokalDetailHeroWash extends StatelessWidget {
  const LokalDetailHeroWash({
    super.key,
    required this.background,
  });

  final Color background;

  @visibleForTesting
  static const stops = [0.0, .46, .62, .76, .86, .94, 1.0];

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: stops,
          colors: [
            background.withValues(alpha: 0),
            background.withValues(alpha: 0),
            background.withValues(alpha: .16),
            background.withValues(alpha: .48),
            background.withValues(alpha: .76),
            background.withValues(alpha: .94),
            background,
          ],
        ),
      ),
    ),
  );
}
