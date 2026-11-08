import 'package:flutter/material.dart';

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/lokal_performance_scope.dart';

/// An edge-to-edge push between the four main tabs.
///
/// The former AnimatedSwitcher painted the new tab *over* the old one. Even
/// with larger translations the old surface remained visibly ghosted behind
/// the incoming content. This implementation gives both screens a single,
/// synchronized position on a horizontal strip: their edges touch but NEVER
/// overlap, so there is no translucent layer, crossfade or dark gap.
///
/// Only one outgoing tab is visible during the animation. The main shell
/// optionally retains three already-visited tabs offstage to reduce re-entry
/// rebuilds without eagerly mounting every destination.
class LokalNavigationSwitcher extends StatefulWidget {
  const LokalNavigationSwitcher({
    super.key,
    required this.child,
    this.direction = 1,
    this.retainVisitedTabs = false,
    this.efficientMotion = false,
    this.instantNavigation = false,
  });

  /// Each destination must carry its stable identity key.
  final Widget child;

  /// +1 for moving to a tab on the right; -1 for a tab on the left.
  final int direction;

  /// Lazily retain at most three visited tab trees for instant return visits.
  /// No disk persistence, eager build, or long-lived cache of every route.
  /// Defaults off for generic switches; the main shell explicitly opts in.
  final bool retainVisitedTabs;

  /// Lightweight shell navigation: only move the incoming cached page a
  /// small distance. The previous whole-screen adjacent slide rasterized
  /// both the departing Library/You page and the incoming one at once.
  final bool efficientMotion;

  /// Keep already-visited tabs in the offstage cache but replace the visible
  /// page immediately. No two-page raster, full-screen translation, or
  /// temporary unpainted strip. The footer indicator handles tab feedback.
  final bool instantNavigation;

  static const efficientDuration = Duration(milliseconds: 180);
  static const enterDuration = Duration(milliseconds: 330);
  static const curve = Cubic(.2, 0, 0, 1);

  @override
  State<LokalNavigationSwitcher> createState() =>
      _LokalNavigationSwitcherState();
}

class _LokalNavigationSwitcherState extends State<LokalNavigationSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  Widget? _outgoing;
  int _travel = 1;
  final Map<Key, Widget> _visited = {};

  void _remember(Widget child) {
    final key = child.key;
    if (key == null) return;
    _visited.remove(key);
    _visited[key] = child;
    // Do not evict an outgoing tree while its transition is still visible.
    while (_visited.length > 3) {
      final protected = {_outgoing?.key, widget.child.key};
      final old = _visited.keys.firstWhere(
        (key) => !protected.contains(key),
        orElse: () => _visited.keys.first,
      );
      if (protected.contains(old)) break;
      _visited.remove(old);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.retainVisitedTabs) _remember(widget.child);
    _progress = AnimationController(
      vsync: this,
      duration: _useEfficientMotion
          ? LokalNavigationSwitcher.efficientDuration
          : LokalNavigationSwitcher.enterDuration,
      value: 1,
    )..addStatusListener(_onAnimationStatus);
  }

  // Single-page rendering needs the retained offstage cache. If callers
  // request efficient motion without retention, preserve the original
  // generic two-page transition instead of dereferencing a null _outgoing.
  bool get _useEfficientMotion =>
      widget.efficientMotion &&
      widget.retainVisitedTabs &&
      widget.child.key != null;

  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      AppConstants.animationNormal == Duration.zero ||
      LokalPerformanceScope.of(context);

  @override
  void didUpdateWidget(covariant LokalNavigationSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.retainVisitedTabs) _remember(widget.child);
    if (oldWidget.efficientMotion != widget.efficientMotion ||
        oldWidget.retainVisitedTabs != widget.retainVisitedTabs ||
        (oldWidget.child.key == null) != (widget.child.key == null)) {
      _progress.duration = _useEfficientMotion
          ? LokalNavigationSwitcher.efficientDuration
          : LokalNavigationSwitcher.enterDuration;
    }
    if (oldWidget.child.key == widget.child.key) return;

    _travel = widget.direction < 0 ? -1 : 1;
    if (_reduceMotion || widget.instantNavigation) {
      _outgoing = null;
      _progress.value = 1;
    } else if (_useEfficientMotion) {
      // No outgoing page is painted during the animation. The old page
      // stays alive in the bounded Offstage cache but consumes zero raster
      // work while Library or You comes in.
      _outgoing = null;
      _progress.forward(from: 0);
    } else {
      // Generic callers retain the original adjacent full-screen push.
      _outgoing = oldWidget.child;
      _progress.forward(from: 0);
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null && mounted) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void dispose() {
    _progress
      ..removeStatusListener(_onAnimationStatus)
      ..dispose();
    super.dispose();
  }

  Widget _retainedScene(double direction, bool animating) {
    final current = widget.child.key;
    final exiting = _useEfficientMotion
        ? null
        : animating
        ? _outgoing?.key
        : null;
    final travel = _useEfficientMotion ? .045 : 1.0;
    // Put the incoming surface last so it paints in front, while the
    // outgoing screen occupies the adjacent viewport region.
    final ordered = [
      ..._visited.keys.where((key) => key != current && key != exiting),
      if (exiting != null && exiting != current) exiting,
      if (current != null) current,
    ];
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final key in ordered)
            AnimatedBuilder(
              key: ValueKey(key),
              // Hidden cached tabs retain their State but do not subscribe
              // to 120-Hz translation ticks or rebuild their layout.
              animation: (key == current || key == exiting)
                  ? _progress
                  : const AlwaysStoppedAnimation<double>(1),
              child: RepaintBoundary(
                child: TickerMode(
                  enabled: key == current,
                  child: ExcludeFocus(
                    excluding: key != current,
                    child: _visited[key]!,
                  ),
                ),
              ),
              builder: (context, page) {
                final isCurrent = key == current;
                final isExiting = key == exiting;
                final progress = animating
                    ? LokalNavigationSwitcher.curve.transform(_progress.value)
                    : 1.0;
                return Offstage(
                  offstage: !isCurrent && !isExiting,
                  child: IgnorePointer(
                    ignoring: !isCurrent,
                    child: FractionalTranslation(
                      translation: Offset(
                        isCurrent
                            ? direction * travel * (1 - progress)
                            : isExiting
                            ? -direction * travel * progress
                            : 0,
                        0,
                      ),
                      child: page!,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion;
    final animating =
        !reduceMotion &&
        !widget.instantNavigation &&
        (_useEfficientMotion ? _progress.isAnimating : _outgoing != null);
    final direction =
        (Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0) *
        _travel;

    if (widget.retainVisitedTabs && widget.child.key != null) {
      return _retainedScene(direction, animating);
    }

    // Keep this exact Stack/AnimatedBuilder ancestry even when idle.
    // Reparenting a KeyedSubtree from a bare child to a different wrapper
    // on every navigation would dispose/recreate heavy Home state.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (animating)
            AnimatedBuilder(
              key: ValueKey(_outgoing!.key),
              animation: _progress,
              child: _outgoing,
              builder: (context, outgoing) {
                final progress = LokalNavigationSwitcher.curve.transform(
                  _progress.value,
                );
                return IgnorePointer(
                  ignoring: true,
                  child: ExcludeSemantics(
                    child: TickerMode(
                      enabled: false,
                      child: FractionalTranslation(
                        translation: Offset(-direction * progress, 0),
                        child: RepaintBoundary(child: outgoing!),
                      ),
                    ),
                  ),
                );
              },
            ),
          AnimatedBuilder(
            key: ValueKey(widget.child.key),
            animation: _progress,
            child: widget.child,
            builder: (context, incoming) {
              final progress = animating
                  ? LokalNavigationSwitcher.curve.transform(_progress.value)
                  : 1.0;
              // Keep the same ancestry when this page becomes outgoing.
              // Changing wrapper types would recreate its entire state tree.
              return IgnorePointer(
                ignoring: false,
                child: ExcludeSemantics(
                  excluding: false,
                  child: TickerMode(
                    enabled: true,
                    child: FractionalTranslation(
                      translation: Offset(direction * (1 - progress), 0),
                      child: RepaintBoundary(child: incoming!),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
