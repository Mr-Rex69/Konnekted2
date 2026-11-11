import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Artwork-derived surface tokens shared by the new full-player controls.
/// Never use the global accent color as the default play/pause surface.
@immutable
class FullPlayerVisuals {
  const FullPlayerVisuals({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.glow,
    required this.play,
  });

  final Color top, middle, bottom, glow, play;
  static const surface = Color(0x15FFFFFF);
  static const scrim = Color(0xFF000000);
  static const border = Color(0x24FFFFFF);
  static const selectedSurface = Color(0x36FFFFFF);
  static const primaryText = Color(0xFFF8F0EB);
  static const secondaryText = Color(0xD7F8F0EB);
  static const tertiaryText = Color(0xAEF8F0EB);

  /// Interpolate already-selected gradients, avoiding discontinuous hue
  /// changes when competing album swatches cross during a track transition.
  static FullPlayerVisuals lerp(
    FullPlayerVisuals from, FullPlayerVisuals to, double progress,
  ) => FullPlayerVisuals(
    top: Color.lerp(from.top, to.top, progress)!,
    middle: Color.lerp(from.middle, to.middle, progress)!,
    bottom: Color.lerp(from.bottom, to.bottom, progress)!,
    glow: Color.lerp(from.glow, to.glow, progress)!,
    play: Color.lerp(from.play, to.play, progress)!,
  );

  static FullPlayerVisuals fromPalette(List<Color> colors) {
    Color seed = colors.isNotEmpty ? colors.first : const Color(0xFF6A4141);
    var score = -1.0;
    for (final color in colors) {
      final hsl = HSLColor.fromColor(color);
      final brightness = color.computeLuminance();
      final next = brightness > .015 && brightness < .85
          ? hsl.saturation * (1.0 - (hsl.lightness - .43).abs())
          : -1.0;
      if (next > score) {
        score = next;
        seed = color;
      }
    }
    final base = HSLColor.fromColor(seed);
    final hue = base.hue >= 10 && base.hue <= 65
        ? math.max(0.0, base.hue - 7)
        : base.hue;
    // A black-and-white sleeve must stay neutral, never acquire red tint.
    final saturation = base.saturation < .08
        ? 0.0
        : math.max(.56, base.saturation).clamp(0.0, .86).toDouble();
    Color tone(double light, {double? sat}) =>
        HSLColor.fromAHSL(1, hue, sat ?? saturation, light).toColor();
    return FullPlayerVisuals(
      top: tone(.105),
      middle: tone(.255),
      bottom: tone(.31),
      glow: tone(.37),
      play: tone(.865, sat: saturation == 0 ? 0 : .23),
    );
  }
}
