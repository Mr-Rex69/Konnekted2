import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Reveals Space as a soft frosted surface lifting from the bottom of the
/// player. It uses the already-painted album palette / ambient mesh below
/// rather than adding a dark layer that appears to sink into the controls.
///
/// The current cover is an exact, rounded cutout: its underlying still art,
/// video or Canvas continues to render normally through the transition.
class SpaceCoverBloomReveal extends StatelessWidget {
  const SpaceCoverBloomReveal({
    super.key,
    required this.progress,
    required this.child,
    this.coverRect,
    this.coverCornerRadius = 20,
    this.canvasMode = false,
    this.surfaceColor = const Color(0xFF15141C),
  });

  final Animation<double> progress;
  final Widget child;
  final Rect? coverRect;
  final double coverCornerRadius;
  final bool canvasMode;
  final Color surfaceColor;

  // A static filter over the *already blurred* player backdrop. Only the
  // clipping wave changes with progress; sigma is never animated or decoded
  // from the album art on each frame. Kept modest for high-refresh devices.
  static final ui.ImageFilter _frost = ui.ImageFilter.blur(
    sigmaX: 8,
    sigmaY: 8,
    tileMode: ui.TileMode.clamp,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final cover = spaceCoverRevealAnchor(
            viewport,
            coverRect: coverRect,
            canvasMode: canvasMode,
          );
          final radius = canvasMode ? 0.0 : coverCornerRadius;
          return Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: ClipPath(
                  clipper: _SpaceRisingFrostClipper(
                    progress: progress,
                    cover: cover,
                    cornerRadius: radius,
                  ),
                  // Blur only where the ascending wave has passed. The
                  // original album-derived mesh stays mounted and animating
                  // underneath; no second artwork decode is necessary.
                  child: BackdropFilter(
                    filter: _frost,
                    child: CustomPaint(
                      painter: _SpaceRisingHighlight(progress),
                      child: ColoredBox(
                        color: Color.lerp(
                          surfaceColor,
                          Colors.white,
                          .84,
                        )!.withValues(alpha: .035),
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: ClipPath(
                  clipper: _SpaceRisingLyricsClipper(progress),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: progress,
                      curve: const Interval(
                        .25, .80, curve: Curves.easeInOutCubic,
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: progress,
                      child: child,
                      builder: (context, lyric) => Transform.translate(
                        offset: Offset(0, 12 * (1 - progress.value)),
                        child: lyric,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

/// Same cover anchor for the normal player, Fullcover banner and Canvas.
/// Canvas is edge-to-edge; protect its upper visual plane instead of creating
/// an artificial inset rounded rectangle across the video.
@visibleForTesting
Rect spaceCoverRevealAnchor(
  Size size, {
  Rect? coverRect,
  bool canvasMode = false,
}) {
  if (size.isEmpty) return Rect.zero;
  if (canvasMode) {
    return Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height * .64,
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

/// The frosted region enters from BELOW the playback controls and rises above
/// the cover. This is the opposite of the old bottom-heavy dark expansion.
@visibleForTesting
double spaceRisingBlurFront(Size size, double progress) {
  if (size.isEmpty) return 0;
  final t = Curves.easeInOutCubic.transform(
    progress.clamp(0.0, 1.0),
  );
  return ui.lerpDouble(size.height * 1.04, -size.height * .12, t)!;
}

/// Tests and both clippers use the same wave path so lyrics and frost advance
/// upward together. The front is deliberately slightly curved, not a hard
/// horizontal bar across the control row.
Path _spaceRisingWave(Size size, double progress) {
  final front = spaceRisingBlurFront(size, progress);
  if (front >= size.height + 12 || size.isEmpty) return Path();
  final overscan = size.width * .08;
  return Path()
    ..moveTo(-overscan, front + 9)
    ..quadraticBezierTo(
      size.width * .5,
      front - 14,
      size.width + overscan,
      front + 9,
    )
    ..lineTo(size.width + overscan, size.height + 24)
    ..lineTo(-overscan, size.height + 24)
    ..close();
}

/// Exact transparency around a normal 20px-radius cover. During the entire
/// transition the cutout is unchanged: previous 20→7px corner interpolation
/// exposed four conspicuous wedges around the album art.
@visibleForTesting
Path spaceRisingFrostClip(
  Size size,
  Rect cover,
  double progress, {
  double cornerRadius = 20,
}) {
  final wave = _spaceRisingWave(size, progress);
  if (wave.getBounds().isEmpty) return wave;
  final cutout = Path()
    ..addRRect(RRect.fromRectAndRadius(
      cover,
      Radius.circular(cornerRadius),
    ));
  return Path.combine(PathOperation.difference, wave, cutout);
}

class _SpaceRisingFrostClipper extends CustomClipper<Path> {
  _SpaceRisingFrostClipper({
    required this.progress,
    required this.cover,
    required this.cornerRadius,
  }) : super(reclip: progress);

  final Animation<double> progress;
  final Rect cover;
  final double cornerRadius;

  @override
  Path getClip(Size size) => spaceRisingFrostClip(
        size,
        cover,
        progress.value,
        cornerRadius: cornerRadius,
      );

  @override
  bool shouldReclip(covariant _SpaceRisingFrostClipper oldClipper) =>
      oldClipper.progress != progress ||
      oldClipper.cover != cover ||
      oldClipper.cornerRadius != cornerRadius;
}

class _SpaceRisingLyricsClipper extends CustomClipper<Path> {
  _SpaceRisingLyricsClipper(this.progress) : super(reclip: progress);

  final Animation<double> progress;

  @override
  Path getClip(Size size) => _spaceRisingWave(size, progress.value);

  @override
  bool shouldReclip(covariant _SpaceRisingLyricsClipper oldClipper) =>
      oldClipper.progress != progress;
}

/// A very restrained soft highlight on the ascending leading edge. Unlike
/// the previous gradient, this does NOT accumulate dark opacity at the bottom
/// of the screen or impose a different color palette on the blurred mesh.
class _SpaceRisingHighlight extends CustomPainter {
  _SpaceRisingHighlight(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = progress.value.clamp(0.0, 1.0);
    if (p <= .005 || p >= .995) return;
    final top = spaceRisingBlurFront(size, p);
    if (top < -60 || top > size.height + 60) return;
    final rect = Rect.fromLTWH(0, top - 36, size.width, 100);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00FFFFFF),
            Color(0x12FFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SpaceRisingHighlight oldDelegate) =>
      oldDelegate.progress != progress;
}
