import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flick/models/progress_bar_style.dart';

import 'full_player_visuals.dart';
import 'material_player_thumb.dart';
import 'waveform_envelope.dart';

/// Every appearance uses Flutter's Slider for touch, keyboard, RTL and
/// accessibility. Only its paint changes; the timeline always occupies 48 px.
class FullPlayerSeekBar extends StatelessWidget {
  const FullPlayerSeekBar({
    super.key,
    required this.style,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.peaks,
  });

  final ProgressBarStyle style;
  final double value;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final List<double>? peaks;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3.5,
        trackShape: FullPlayerSeekTrack(style: style, peaks: peaks),
        thumbShape: const MaterialPlayerThumb(),
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: FullPlayerVisuals.primaryText,
        inactiveTrackColor: FullPlayerVisuals.primaryText.withValues(
          alpha: .30,
        ),
        disabledActiveTrackColor: FullPlayerVisuals.tertiaryText,
        disabledInactiveTrackColor: FullPlayerVisuals.surface,
        thumbColor: FullPlayerVisuals.primaryText,
        disabledThumbColor: FullPlayerVisuals.tertiaryText,
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: (v) => '${(v * 100).round()}%',
      ),
    ),
  );
}

class FullPlayerSeekTrack extends SliderTrackShape with BaseSliderTrackShape {
  const FullPlayerSeekTrack({required this.style, this.peaks});

  final ProgressBarStyle style;
  final List<double>? peaks;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.width <= 0) return;
    final canvas = context.canvas;
    final rtl = textDirection == TextDirection.rtl;
    final x = thumbCenter.dx.clamp(rect.left, rect.right);
    final active = Color.lerp(
      sliderTheme.disabledActiveTrackColor,
      sliderTheme.activeTrackColor,
      enableAnimation.value,
    )!;
    final inactive = Color.lerp(
      sliderTheme.disabledInactiveTrackColor,
      sliderTheme.inactiveTrackColor,
      enableAnimation.value,
    )!;
    final samples = peaks;
    final hasWaveform =
        style == ProgressBarStyle.waveform &&
        samples != null &&
        samples.length > 1 &&
        samples.every((v) => v.isFinite && v >= 0);

    if (hasWaveform) {
      paintWaveformEnvelope(
        canvas,
        Rect.fromCenter(center: rect.center, width: rect.width, height: 34),
        peaks: samples,
        progress: (rtl ? rect.right - x : x - rect.left) / rect.width,
        active: active,
        inactive: inactive,
        rtl: rtl,
      );
      return;
    }

    final paint = Paint()
      ..strokeWidth = rect.height
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final playedStart = rtl ? rect.right : rect.left;
    final remainingEnd = rtl ? rect.left : rect.right;
    final sign = rtl ? -1.0 : 1.0;
    final playedEnd = (x - sign * 7).clamp(rect.left, rect.right);
    final remainingStart = (x + sign * 7).clamp(rect.left, rect.right);
    paint.color = inactive;
    canvas.drawLine(
      Offset(remainingStart, rect.center.dy),
      Offset(remainingEnd, rect.center.dy),
      paint,
    );
    paint.color = active;
    if (style == ProgressBarStyle.wavy) {
      final length = (playedEnd - playedStart).abs();
      final path = Path()..moveTo(playedStart, rect.center.dy);
      for (var d = 0.0; d <= length; d += 1) {
        // Taper at the handle so it stays visually separate from the wave.
        final amplitude = 4.0 * math.min(1.0, (length - d) / 8);
        path.lineTo(
          playedStart + sign * d,
          rect.center.dy + math.sin(d * math.pi / 18) * amplitude,
        );
      }
      canvas.drawPath(path, paint);
    } else {
      canvas.drawLine(
        Offset(playedStart, rect.center.dy),
        Offset(playedEnd, rect.center.dy),
        paint,
      );
    }
  }
}
