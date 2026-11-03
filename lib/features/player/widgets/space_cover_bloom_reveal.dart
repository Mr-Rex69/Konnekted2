import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Space moves out from the *cover*, across the surrounding player and down
/// into the lyrics area. The image/video/Canvas and player controls remain
/// mounted; only a lightweight animated mask and paint layer are introduced.
class SpaceCoverBloomReveal extends StatelessWidget {
  const SpaceCoverBloomReveal({
    super.key,
    required this.progress,
    required this.child,
    this.coverRect,
    this.canvasMode = false,
    this.surfaceColor = const Color(0xFF15141C),
  });

  final Animation<double> progress;
  final Widget child;

  /// Artwork bounds in this overlay's coordinate system, captured when
  /// entering Space. A null value uses responsive geometry instead.
  final Rect? coverRect;
  final bool canvasMode;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      final cover = spaceCoverRevealAnchor(
        viewport,
        coverRect: coverRect,
        canvasMode: canvasMode,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          // A gentle growing veil *outside* the sleeve. The centre of the
          // cover stays uncovered and the underlying album/video continues.
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: SpaceCoverBloomPainter(
                  progress: progress,
                  cover: cover,
                  surfaceColor: surfaceColor,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: ClipPath(
              clipper: _SpaceBloomClipper(progress, cover),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: progress,
                  curve: const Interval(
                    .48, .88, curve: Curves.easeInOutCubic,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// The normal player supplies the real square cover rect; Fullcover supplies
/// the full-width top sleeve. Canvas has no sleeve edge, so the open central
/// visual remains visible while the surrounding controls become immersive.
@visibleForTesting
Rect spaceCoverRevealAnchor(
  Size size, {
  Rect? coverRect,
  bool canvasMode = false,
}) {
  if (size.isEmpty) return Rect.zero;
  if (canvasMode) {
    return Rect.fromLTWH(
      size.width * .08,
      size.height * .10,
      size.width * .84,
      size.height * .53,
    );
  }
  if (coverRect != null &&
      coverRect.isFinite &&
      coverRect.width > 8 &&
      coverRect.height > 8) {
    final left = coverRect.left.clamp(0.0, size.width - 1).toDouble();
    final top = coverRect.top.clamp(0.0, size.height - 1).toDouble();
    final right = coverRect.right.clamp(left + 1, size.width).toDouble();
    final bottom = coverRect.bottom.clamp(top + 1, size.height).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }
  final side = math.min(size.width * .86, size.height * .48);
  return Rect.fromLTWH(
    (size.width - side) / 2,
    size.height * .16,
    side,
    side,
  );
}

/// Progress 0 = narrow soft rim outside the cover, 1 = full-window veil.
/// The same interpolation runs backwards on exit; there is no jump in crop,
/// gradient ownership, playback texture, or lyrics placement.
@visibleForTesting
Rect spaceCoverBloomBounds(
  Size size,
  Rect anchor,
  double progress,
) {
  if (size.isEmpty) return Rect.zero;
  final p = Curves.easeInOutCubic.transform(
    progress.clamp(0.0, 1.0),
  );
  final start = anchor.inflate(9);
  final end = Rect.fromLTWH(
    -size.width * .05,
    -size.height * .05,
    size.width * 1.10,
    size.height * 1.10,
  );
  return Rect.lerp(start, end, p)!;
}

class _SpaceBloomClipper extends CustomClipper<Path> {
  _SpaceBloomClipper(this.progress, this.cover)
      : super(reclip: progress);

  final Animation<double> progress;
  final Rect cover;

  @override
  Path getClip(Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    final bounds = spaceCoverBloomBounds(size, cover, p);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        bounds,
        Radius.circular(24 * (1 - p)),
      ));
  }

  @override
  bool shouldReclip(covariant _SpaceBloomClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.cover != cover;
}

/// No image sampling or saveLayer blur. A single rounded veil with a cover
/// cutout is painted while the controller runs, plus two very soft edge rings.
/// At rest the controller stops ticking and the painted result is cached.
class SpaceCoverBloomPainter extends CustomPainter {
  SpaceCoverBloomPainter({
    required this.progress,
    required this.cover,
    required this.surfaceColor,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Rect cover;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    if (p < .001 || size.isEmpty) return;

    final bounds = spaceCoverBloomBounds(size, cover, p);
    final veil = Path()
      ..addRRect(RRect.fromRectAndRadius(
        bounds, Radius.circular(24 * (1 - p)),
      ));
    // Always preserve the album cover / Canvas centre, even once all
    // ordinary controls have faded out.
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(
        cover,
        Radius.circular(20 * (1 - p) + 7 * p),
      ));
    final outsideArtwork = Path.combine(
      PathOperation.difference,
      veil,
      cutout,
    );
    final strength = Curves.easeOutCubic.transform(p);
    final tint = Color.lerp(surfaceColor, Colors.black, .36)!;
    final darken = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          tint.withValues(alpha: .24 * strength),
          tint.withValues(alpha: .52 * strength),
          tint.withValues(alpha: .83 * strength),
        ],
        stops: const [0, .52, 1],
      ).createShader(Offset.zero & size);
    canvas.drawPath(outsideArtwork, darken);

    // The transitional halo follows the rounded sleeve while the reveal
    // starts. No hard line is left around the artwork after settling.
    final rim = math.sin(
      math.pi * (p / .58).clamp(0.0, 1.0),
    );
    if (rim > .008) {
      final softColor = Color.lerp(
        Colors.white, surfaceColor, .65,
      )!;
      for (var index = 0; index < 2; index++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            cover.inflate(4 + index * 6 + p * 3),
            Radius.circular(21 + index * 5),
          ),
          Paint()
            ..color = softColor.withValues(
              alpha: rim * (index == 0 ? .19 : .08),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = index == 0 ? 1.4 : 4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SpaceCoverBloomPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.cover != cover ||
      oldDelegate.surfaceColor != surfaceColor;
}
