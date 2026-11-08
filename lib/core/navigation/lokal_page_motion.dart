import 'package:flutter/material.dart';

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/lokal_performance_scope.dart';

/// Whether the system asks the app to avoid motion.
bool systemRequestsReducedMotion(BuildContext context) {
  final accessibility =
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
  return MediaQuery.disableAnimationsOf(context) ||
      accessibility.disableAnimations ||
      accessibility.reduceMotion;
}

/// A single, opacity-free shared-axis motion for all ordinary Lokal routes.
///
/// The old implementation nested Flutter's Android predictive-back builder
/// (which uses FadeForwards outside a gesture) *inside* our own fade, scale
/// and slide. At the start of a push the new page was transparent while the
/// old page had already shifted, exposing the navigator's dark background.
/// It also asked the GPU to composite multiple translucent full-screen layers.
///
/// Here the incoming route is opaque from its very first frame. The previous
/// route is kept mounted by Navigator and moves only a small distance in the
/// opposite direction. There is always overlap, so neither forward nor
/// reverse travel can reveal an unpainted strip of the underlying navigator.
/// Hero flights and specialized player/queue sheet routes remain separate.
class LokalPageMotion extends PageTransitionsBuilder {
  const LokalPageMotion();

  /// A fast, predictable motion profile; no long fade-in or black scrim.
  static const duration = Duration(milliseconds: 320);
  static const reverseDuration = Duration(milliseconds: 285);
  static const enterOffset = .34;
  // A pop must slide until the outgoing page is entirely past the edge,
  // rather than removing it after the same short push distance.
  static const exitOffset = 1.0;
  static const behindOffset = -.10;
  static const enterCurve = Cubic(.2, 0, 0, 1);
  static const backCurve = Cubic(.23, .65, .3, 1);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context) ||
        AppConstants.animationNormal == Duration.zero) {
      return child;
    }

    // The translation is directional. Do not introduce a second opacity
    // compositing pass or a scale that would expose the underlying backdrop.
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;

    final backgroundProgress = CurvedAnimation(
      parent: secondaryAnimation,
      curve: enterCurve,
      reverseCurve: backCurve,
    );

    final incoming = _ContinuousForegroundSlide(
      animation: animation,
      direction: direction,
      child: RepaintBoundary(child: child),
    );

    // Ultra Performance Mode avoids translating/rasterizing the old page at
    // all. Its full-size, opaque backdrop remains in place behind the new
    // route; the incoming slide remains reversible and never exposes black.
    if (LokalPerformanceScope.of(context)) return incoming;

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: Offset(behindOffset * direction, 0),
      ).animate(backgroundProgress),
      child: incoming,
    );
  }
}

/// Maintains the rendered position across a mid-flight push/Back reversal.
/// The entering path starts 34% offscreen, while pop finishes 100% offscreen.
/// Switching between those unequal travel distances without an anchor would
/// make a partially entered page jump when system Back is invoked.
class _ContinuousForegroundSlide extends StatefulWidget {
  const _ContinuousForegroundSlide({
    required this.animation,
    required this.direction,
    required this.child,
  });

  final Animation<double> animation;
  final double direction;
  final Widget child;

  @override
  State<_ContinuousForegroundSlide> createState() =>
      _ContinuousForegroundSlideState();
}

class _ContinuousForegroundSlideState
    extends State<_ContinuousForegroundSlide> {
  late AnimationStatus _phase;
  late double _startValue;
  late double _startOffset;

  @override
  void initState() {
    super.initState();
    _initialize();
    widget.animation.addStatusListener(_onStatus);
  }

  void _initialize() {
    _phase = widget.animation.status;
    _startValue =
        _phase == AnimationStatus.reverse || _phase == AnimationStatus.completed
        ? 1.0
        : 0.0;
    _startOffset =
        _phase == AnimationStatus.reverse || _phase == AnimationStatus.completed
        ? 0.0
        : LokalPageMotion.enterOffset;
  }

  @override
  void didUpdateWidget(covariant _ContinuousForegroundSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.animation, oldWidget.animation)) {
      oldWidget.animation.removeStatusListener(_onStatus);
      _initialize();
      widget.animation.addStatusListener(_onStatus);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == _phase) return;
    // Capture at the actual reversal, even if no frame is built before the
    // animation advances. Sampling in build alone loses that starting point.
    final value = widget.animation.value;
    final position = _offsetAt(value);
    _phase = status;
    _startValue = value;
    _startOffset = status == AnimationStatus.completed ? 0 : position;
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  double _offsetAt(double value) {
    final p = value.clamp(0.0, 1.0);
    if (_phase == AnimationStatus.completed) return 0.0;
    if (_phase == AnimationStatus.dismissed) return _startOffset;
    if (_phase == AnimationStatus.reverse) {
      final fraction = _startValue <= 0
          ? 1.0
          : ((_startValue - p) / _startValue).clamp(0.0, 1.0);
      return _startOffset +
          (LokalPageMotion.exitOffset - _startOffset) *
              LokalPageMotion.backCurve.transform(fraction);
    }
    final fraction = _startValue >= 1
        ? 1.0
        : ((p - _startValue) / (1 - _startValue)).clamp(0.0, 1.0);
    return _startOffset * (1 - LokalPageMotion.enterCurve.transform(fraction));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    child: widget.child,
    builder: (context, page) {
      final value = widget.animation.value;
      final status = widget.animation.status;
      if (status != _phase) {
        // Capture the old position at *this exact animation value* before
        // changing the target. A reverse/cancel at p=.45 stays at the same x.
        final position = _offsetAt(value);
        _phase = status;
        _startValue = value;
        _startOffset = position;
        if (status == AnimationStatus.completed) _startOffset = 0;
      }
      return FractionalTranslation(
        translation: Offset(_offsetAt(value) * widget.direction, 0),
        child: page!,
      );
    },
  );
}

/// A native Material route keeps Navigator, Hero and Android system Back
/// semantics, unlike an independently composited PageRouteBuilder.
/// Android's system Back still commits through the nested NavigatorPopHandler.
/// Gesture-progress rendering must be evaluated separately on device.
class LokalPageRoute<T> extends MaterialPageRoute<T> {
  LokalPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration =>
      AppConstants.animationNormal == Duration.zero
      ? Duration.zero
      : LokalPageMotion.duration;

  @override
  Duration get reverseTransitionDuration =>
      AppConstants.animationNormal == Duration.zero
      ? Duration.zero
      : LokalPageMotion.reverseDuration;
}
