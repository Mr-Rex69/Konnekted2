import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A filled, mirrored recording envelope. Rounded joins connect real peaks;
/// silence stays on the center line rather than becoming decorative bars.
void paintWaveformEnvelope(
  Canvas canvas,
  Rect rect, {
  required List<double> peaks,
  required double progress,
  required Color active,
  required Color inactive,
  bool rtl = false,
  double start = 0,
  double end = 1,
  double reveal = 1,
}) {
  if (rect.width <= 0 || peaks.length < 2 || end <= start) return;
  final count = math.min(512, math.max(2, (rect.width * 1.5).ceil()));
  final points = <Offset>[];
  for (var i = 0; i < count; i++) {
    final t = i / (count - 1);
    final index =
        (start + (end - start) * t).clamp(0.0, 1.0) * (peaks.length - 1);
    final lo = index.floor(), hi = index.ceil();
    final raw = peaks[lo] + (peaks[hi] - peaks[lo]) * (index - lo);
    final amplitude = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
    points.add(
      Offset(
        rtl ? rect.right - t * rect.width : rect.left + t * rect.width,
        rect.center.dy - amplitude * rect.height / 2 * reveal.clamp(0.0, 1.0),
      ),
    );
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  void edge(List<Offset> values) {
    for (var i = 1; i < values.length; i++) {
      final previous = values[i - 1], next = values[i];
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        (previous.dx + next.dx) / 2,
        (previous.dy + next.dy) / 2,
      );
    }
    path.lineTo(values.last.dx, values.last.dy);
  }

  edge(points);
  final lower = points.reversed
      .map((p) => Offset(p.dx, 2 * rect.center.dy - p.dy))
      .toList();
  path.lineTo(lower.first.dx, lower.first.dy);
  edge(lower);
  path.close();
  final played = ((progress - start) / (end - start)).clamp(0.0, 1.0);
  final x = rtl
      ? rect.right - played * rect.width
      : rect.left + played * rect.width;
  void paint(Color color) {
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: color.a * .86),
    );
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  paint(inactive);
  canvas.save();
  canvas.clipRect(
    Rect.fromLTRB(
      rtl ? x : rect.left,
      rect.top - 1,
      rtl ? rect.right : x,
      rect.bottom + 1,
    ),
  );
  paint(active);
  canvas.restore();
}
