import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A transient Space-mode aperture and starfield. The artwork, Canvas texture
/// and lyrics never move between player trees; only the clip and paint layers
/// animate, preserving frame pacing and existing media ownership.
class SpaceStardustReveal extends StatelessWidget {
  const SpaceStardustReveal({
    super.key,
    required this.progress,
    required this.child,
    this.accent = const Color(0xFFC6D6FF),
  });

  final Animation<double> progress;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ClipPath(
            clipper: _SpaceApertureClipper(progress),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: progress,
                curve: const Interval(.08, .63, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
        ),
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: SpaceStardustPainter(
                progress: progress,
                accent: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Begins around the seekbar/subtitle band, filling the whole viewport by
/// the time Space reaches its settled state. A reclip listenable avoids
/// rebuilding the animated-lyrics widget on every transition frame.
class _SpaceApertureClipper extends CustomClipper<Path> {
  _SpaceApertureClipper(this.progress) : super(reclip: progress);

  final Animation<double> progress;

  @override
  Path getClip(Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    final radius = math.sqrt(size.width * size.width +
            size.height * size.height) *
        Curves.easeOutCubic.transform(p);
    return Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * .5, size.height * .69),
          radius: radius,
        ),
      );
  }

  @override
  bool shouldReclip(covariant _SpaceApertureClipper oldClipper) =>
      oldClipper.progress != progress;
}

@immutable
class _SpaceParticle {
  const _SpaceParticle(this.angle, this.distance, this.radius, this.phase);

  final double angle;
  final double distance;
  final double radius;
  final double phase;
}

/// Fixed deterministic particles are evaluated only while the enter/exit
/// controller runs. Circles and short trails use no blur filters or shaders.
class SpaceStardustPainter extends CustomPainter {
  SpaceStardustPainter({
    required this.progress,
    required this.accent,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color accent;

  static final List<_SpaceParticle> _particles = () {
    final random = math.Random(0x5AACE);
    return List<_SpaceParticle>.unmodifiable([
      for (var i = 0; i < 88; i++)
        _SpaceParticle(
          random.nextDouble() * math.pi * 2,
          .17 + random.nextDouble() * .86,
          .65 + random.nextDouble() * 1.65,
          random.nextDouble(),
        ),
    ]);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    // Space at rest is a completely transparent, zero-work paint layer.
    if (p <= .002 || p >= .998 || size.isEmpty) return;
    final travel = Curves.easeOutCubic.transform(p);
    final envelope = math.sin(math.pi * p).clamp(0.0, 1.0);
    if (envelope < .01) return;

    final center = Offset(size.width * .5, size.height * .69);
    final range = math.sqrt(size.width * size.width +
        size.height * size.height) * .68;
    final bright = Paint()..style = PaintingStyle.fill;
    final halo = Paint()..style = PaintingStyle.fill;
    final trail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round;

    for (final particle in _particles) {
      final dx = math.cos(particle.angle);
      final dy = math.sin(particle.angle);
      final radius = range * particle.distance * travel;
      final point = center + Offset(dx * radius, dy * radius);
      if (point.dx < -10 || point.dx > size.width + 10 ||
          point.dy < -10 || point.dy > size.height + 10) continue;

      final twinkle = .72 + .28 * math.sin(
        (particle.phase + p * .85) * math.pi * 2,
      ).abs();
      final opacity = (envelope * twinkle).clamp(0.0, 1.0);
      final color = Color.lerp(Colors.white, accent, particle.phase)!;
      halo.color = color.withValues(alpha: opacity * .14);
      bright.color = color.withValues(alpha: opacity * .86);
      canvas.drawCircle(point, particle.radius * 2.8, halo);
      canvas.drawCircle(point, particle.radius, bright);

      if (particle.phase > .68 && radius > 12) {
        trail.color = color.withValues(alpha: opacity * .21);
        canvas.drawLine(
          point,
          point - Offset(dx, dy) * (4 + particle.radius * 3.4),
          trail,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SpaceStardustPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}
