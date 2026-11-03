import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Space expands outward from the actual artwork, as in the original cover
/// reveal. The surrounding player gains a softer, slightly more luminous
/// version of its existing ambient blur; nothing travels bottom-to-top.
///
/// The cover itself remains untouched behind an exact, fixed-radius cutout.
/// Canvas/video surfaces and lyrics remain mounted across both directions.
class SpaceCoverBloomReveal extends StatelessWidget {
  const SpaceCoverBloomReveal({
    super.key,
    required this.progress,
    required this.child,
    this.coverRect,
    this.coverRectResolver,
    this.coverMotion,
    this.coverCornerRadius = 20,
    this.canvasMode = false,
    this.surfaceColor = const Color(0xFF15141C),
  });

  final Animation<double> progress;
  final Widget child;
  final Rect? coverRect;
  /// Read the artwork's *current* bounds during the lyrics/queue morph.
  /// The original fixed rectangle only matched the final resting cover and
  /// could blur the moving sleeve while leaving pixels outside it untreated.
  final Rect? Function()? coverRectResolver;
  /// Notifies the frost clip and glint while the artwork itself animates.
  final Listenable? coverMotion;
  final double coverCornerRadius;
  final bool canvasMode;
  final Color surfaceColor;

  // The sigma is constant. We animate only the clipping geometry, not the
  // blur kernel, and never decode or reparent the artwork or Canvas texture.
  static final ui.ImageFilter _frost = ui.ImageFilter.blur(
    sigmaX: 8,
    sigmaY: 8,
    tileMode: ui.TileMode.clamp,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          Rect coverAt(Size size) => spaceCoverRevealAnchor(
                size,
                coverRect: coverRectResolver?.call() ?? coverRect,
                canvasMode: canvasMode,
              );
          final changes = coverMotion == null
              ? progress
              : Listenable.merge([progress, coverMotion!]);
          final radius = canvasMode ? 0.0 : coverCornerRadius;

          // A neutral, extremely translucent lift rather than a black
          // gradient. The existing artwork mesh supplies the hue and depth.
          final frostTint = Color.lerp(surfaceColor, Colors.white, .78)!
              .withValues(alpha: .045);

          return Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: ClipPath(
                  clipper: _SpaceBloomFrostClipper(
                    progress: progress,
                    coverAt: coverAt,
                    changes: changes,
                    cornerRadius: radius,
                  ),
                  child: BackdropFilter(
                    filter: _frost,
                    child: ColoredBox(color: frostTint),
                  ),
                ),
              ),
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SpaceBloomGlint(
                      progress: progress,
                      coverAt: coverAt,
                      changes: changes,
                      cornerRadius: radius,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: ClipPath(
                  clipper: _SpaceBloomLyricsClipper(
                    progress,
                    coverAt,
                    changes,
                  ),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: progress,
                      curve: const Interval(
                        .44, .85, curve: Curves.easeInOutCubic,
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

/// The normal player supplies its measured square; Fullcover supplies the
/// true poster banner. Canvas stays edge-to-edge without an invented rounded
/// rectangle over its upper visual plane.
@visibleForTesting
Rect spaceCoverRevealAnchor(
  Size size, {
  Rect? coverRect,
  bool canvasMode = false,
}) {
  if (size.isEmpty) return Rect.zero;
  if (canvasMode) {
    return Rect.fromLTWH(0, 0, size.width, size.height * .64);
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

/// A symmetrical outward expansion, NEVER a vertically travelling wave.
/// All edges move away from the cover at once, with a gentle eased spread.
@visibleForTesting
Rect spaceCoverBloomBounds(Size size, Rect cover, double progress) {
  if (size.isEmpty) return Rect.zero;
  final p = Curves.easeInOutCubic.transform(
    progress.clamp(0.0, 1.0),
  );
  final target = Rect.fromLTWH(
    -size.width * .04,
    -size.height * .04,
    size.width * 1.08,
    size.height * 1.08,
  );
  return Rect.lerp(cover.inflate(2), target, p)!;
}

/// The frosted area grows OUTSIDE the current cover's unchanged rounded
/// outline. Matching 20px in normal mode avoids the former corner wedges.
@visibleForTesting
Path spaceCoverBloomFrostClip(
  Size size,
  Rect cover,
  double progress, {
  double cornerRadius = 20,
}) {
  if (size.isEmpty || progress <= 0) return Path();
  final outer = spaceCoverBloomBounds(size, cover, progress);
  final expansion = Curves.easeInOutCubic.transform(
    progress.clamp(0.0, 1.0),
  );
  final outerPath = Path()
    ..addRRect(RRect.fromRectAndRadius(
      outer,
      Radius.circular(cornerRadius * (1 - expansion)),
    ));
  final innerPath = Path()
    ..addRRect(RRect.fromRectAndRadius(
      cover,
      Radius.circular(cornerRadius),
    ));
  return Path.combine(PathOperation.difference, outerPath, innerPath);
}

class _SpaceBloomFrostClipper extends CustomClipper<Path> {
  _SpaceBloomFrostClipper({
    required this.progress,
    required this.coverAt,
    required this.changes,
    required this.cornerRadius,
  }) : super(reclip: changes);

  final Animation<double> progress;
  final Rect Function(Size size) coverAt;
  final Listenable changes;
  final double cornerRadius;

  @override
  Path getClip(Size size) => spaceCoverBloomFrostClip(
        size,
        coverAt(size),
        progress.value,
        cornerRadius: cornerRadius,
      );

  @override
  bool shouldReclip(covariant _SpaceBloomFrostClipper old) =>
      old.progress != progress ||
      old.coverAt != coverAt ||
      old.changes != changes ||
      old.cornerRadius != cornerRadius;
}

class _SpaceBloomLyricsClipper extends CustomClipper<Path> {
  _SpaceBloomLyricsClipper(this.progress, this.coverAt, this.changes)
      : super(reclip: changes);

  final Animation<double> progress;
  final Rect Function(Size size) coverAt;
  final Listenable changes;

  @override
  Path getClip(Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        spaceCoverBloomBounds(size, coverAt(size), p),
        Radius.circular(20 * (1 - p)),
      ));
  }

  @override
  bool shouldReclip(covariant _SpaceBloomLyricsClipper old) =>
      old.progress != progress ||
      old.coverAt != coverAt ||
      old.changes != changes;
}

/// A faint outline only while the reveal grows, not a persistent rim or a
/// darkened layer. It conveys the expansion without changing its direction.
class _SpaceBloomGlint extends CustomPainter {
  _SpaceBloomGlint({
    required this.progress,
    required this.coverAt,
    required this.changes,
    required this.cornerRadius,
  }) : super(repaint: changes);

  final Animation<double> progress;
  final Rect Function(Size size) coverAt;
  final Listenable changes;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = progress.value.clamp(0.0, 1.0);
    if (p <= .005 || p >= .75) return;
    final envelope = math.sin(math.pi * (p / .75));
    if (envelope <= .001) return;
    final bounds = spaceCoverBloomBounds(size, coverAt(size), p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds,
        Radius.circular(cornerRadius * (1 - p)),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: .075 * envelope)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpaceBloomGlint old) =>
      old.progress != progress ||
      old.coverAt != coverAt ||
      old.changes != changes ||
      old.cornerRadius != cornerRadius;
}
