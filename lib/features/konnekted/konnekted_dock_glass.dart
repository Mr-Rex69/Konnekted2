import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';

// BitChord supplies the *interaction* physics. Apple's Music glass is much
// gentler optically: a small centre magnification, low-displacement bezel,
// almost neutral chroma and no strong refractive rainbow at rest. Applying
// BitChord's 24/24/1.0 lens wholesale yielded the user's vivid RGB artifacts.
const _dockGlassLens = LokalLens(
  height: 13,
  amount: 8,
  fraction: .5,
  depth: .18,
  dispersion: .10,
  magnification: .023,
  profile: LokalLensProfile.circular,
);

const _dockBlurRadius = 1.2;

// Apple's floating Music controls let the underlying content remain visible:
// the frost should barely soften detail, not turn the dock into opaque acrylic.
// Keep one small, clipped Gaussian pass for all three footer surfaces, including
// Performance Mode, without introducing any extra shader.
const _dockBackdropBlurSigma = 2.0;
const _dockPerformanceDarkTint = .28;
const _dockPerformanceLightTint = .40;

/// The same material for phone dock surfaces and the floating tablet player.
LokalGlass konnektedDockGlass(
  BuildContext context, {
  Key? key,
  required Widget child,
  double progress = 0,
  bool grouped = false,
}) => LokalGlass.capsule(
  key: key,
  grouped: grouped,
  lens: _dockGlassLens,
  liquidTintOpacity: lerpDouble(.09, .13, progress)!,
  liquidBlurRadius: _dockBlurRadius,
  singlePassLens: true,
  fallbackTintOpacity: lerpDouble(.16, .20, progress)!,
  fallbackBlurSigma: 2,
  backdropBlurSigma: _dockBackdropBlurSigma,
  performanceTintOpacity: context.lokal.isLight
      ? _dockPerformanceLightTint
      : _dockPerformanceDarkTint,
  pronouncedRim: true,
  rimStrength: .82,
  child: child,
);
