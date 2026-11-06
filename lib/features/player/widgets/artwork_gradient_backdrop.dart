import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'full_player_visuals.dart';

/// Artwork palette, painted directly: no second artwork decode, image blur,
/// backdrop capture, rotation texture or saveLayer on the slide-up path.
class ArtworkGradientBackdrop extends ConsumerStatefulWidget {
  const ArtworkGradientBackdrop({
    super.key,
    required this.colors,
    this.vibrant = false,
  }) : assert(colors.length > 0);
  final List<Color> colors;
  /// Higher-chroma, top-to-bottom ambient color reserved for the full player.
  final bool vibrant;
  @override
  ConsumerState<ArtworkGradientBackdrop> createState() =>
      _ArtworkGradientBackdropState();
}

class _ArtworkGradientBackdropState
    extends ConsumerState<ArtworkGradientBackdrop>
    with TickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
    value: .5,
  );
  late final _palette = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
    value: 1,
  );
  late List<Color> _from = widget.colors;
  late FullPlayerVisuals _visualFrom =
      FullPlayerVisuals.fromPalette(widget.colors);
  late FullPlayerVisuals _visualTo = _visualFrom;

  FullPlayerVisuals get _currentVisual => FullPlayerVisuals.lerp(
    _visualFrom, _visualTo,
    Curves.easeInOut.transform(_palette.value),
  );
  Animation<double>? _route;
  bool _reduceMotion = false;
  bool _performance = true;
  Color _color(int index) => Color.lerp(
    _from[index % _from.length],
    widget.colors[index % widget.colors.length],
    Curves.easeInOut.transform(_palette.value),
  )!;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final route = ModalRoute.of(context)?.animation;
    if (!identical(route, _route)) {
      _route?.removeStatusListener(_routeChanged);
      _route = route;
      route?.addStatusListener(_routeChanged);
    }
    _configure();
  }

  void _routeChanged(AnimationStatus _) => _configure();
  void _configure() {
    final settled =
        _route == null || _route!.status == AnimationStatus.completed;
    // The vibrant palette is only an immediate fallback behind the artwork
    // mesh. Its painter does not use the drift phase, so never drive an
    // unnecessary second animation beneath the active blur.
    if (widget.vibrant || _performance || _reduceMotion || !settled) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ArtworkGradientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.colors, widget.colors)) {
      // Blend fully resolved surface colors, not intermediate palettes.
      // Re-selecting the 'most saturated' swatch every paint caused abrupt
      // hue jumps as the swatches crossed during next/previous transitions.
      _visualFrom = _currentVisual;
      _visualTo = FullPlayerVisuals.fromPalette(widget.colors);
      final t = Curves.easeInOut.transform(_palette.value);
      _from = List.generate(
        3,
        (i) => Color.lerp(
          _from[i % _from.length],
          oldWidget.colors[i % oldWidget.colors.length],
          t,
        )!,
      );
      if (_reduceMotion) {
        _palette.value = 1;
      } else {
        _palette.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_routeChanged);
    _drift.dispose();
    _palette.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _performance = ref.watch(
      lokalAppearanceProvider.select(
        (appearance) => appearance.performanceMode,
      ),
    );
    _configure();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PalettePainter(
          Listenable.merge([_drift, _palette]),
          _color,
          () => _drift.value,
          vibrant: widget.vibrant,
          visuals: () => _currentVisual,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _PalettePainter extends CustomPainter {
  _PalettePainter(Listenable repaint, this.color, this.phase, {
    required this.vibrant,
    required this.visuals,
  }) : super(repaint: repaint);
  final Color Function(int) color;
  final double Function() phase;
  final bool vibrant;
  final FullPlayerVisuals Function() visuals;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (vibrant) {
      final theme = visuals();
      // A dark, legible header and a stronger artwork-colored lower half.
      // Static shader paints: no texture blur or additional image decode.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.top, theme.middle, theme.bottom],
            stops: const [0, .53, 1],
          ).createShader(rect),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(.9, 1),
            radius: 1.15,
            colors: [theme.glow.withValues(alpha: .58),
              theme.glow.withValues(alpha: 0)],
          ).createShader(rect),
      );
      return;
    }
    canvas.drawRect(
      rect,
      Paint()..color = Color.lerp(color(0), Colors.black, .58)!,
    );
    final t = math.sin(phase() * math.pi - math.pi / 2);
    for (var i = 0; i < 3; i++) {
      final center = Alignment(
        i == 1 ? .7 - t * .15 : -.7 + t * .2,
        i == 2 ? .8 : -.6 + i * .65,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: center,
            radius: 1.15,
            colors: [
              color(i).withValues(alpha: .55),
              color(i).withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_PalettePainter oldDelegate) => true;
}
