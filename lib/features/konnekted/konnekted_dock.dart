import 'dart:async';
import 'package:flick/features/player/widgets/motion_art_widget.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/l10n/l10n.dart';

import '../link/lokal_devices_card.dart';

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/common/overflow_marquee_title.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_home.dart';

enum KonnektedTab {
  listen('Home', Icons.home_rounded),
  explore('Search', Icons.search_rounded),
  library('Library', Icons.library_music_rounded),
  settings('You', Icons.person_rounded);

  const KonnektedTab(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The tabs inside the capsule; [explore] is the separate search circle,
  /// as in Apple Music on iOS 26.
  static const capsule = [listen, library, settings];
}

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

/// All selected Home/Library/You icons recoil left as the bar folds.
@visibleForTesting
double dockSelectedLeftBounce(double progress) {
  final t = progress.clamp(0.0, 1.0);
  final wave = math.sin(math.pi * t);
  return -7.0 * wave * wave;
}

class KonnektedDock extends StatefulWidget {
  const KonnektedDock({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.miniPlayer,
    this.hasMiniPlayer = true,
    this.collapsed = false,
    this.onExpand,
  });

  final KonnektedTab selected;
  final ValueChanged<KonnektedTab> onSelect;
  final Widget miniPlayer;

  /// Whether [miniPlayer] has a song to show; without one the dock is a
  /// single row and never collapses.
  final bool hasMiniPlayer;
  final bool collapsed;

  /// Tapping the shrunken tab capsule asks for the full dock back.
  final VoidCallback? onExpand;

  // BitChord's fully folded row is 48dp, not a 58dp row with fewer labels.
  // The separate 14dp gaps and 28dp screen gutters make the whole footer
  // visibly compact while its controls follow the same layout spring.
  static const barHeight = 58.0;
  static const miniHeight = 58.0;
  static const collapsedHeight = 48.0;
  static const inlineSpacing = 14.0;
  static const inlineInset = 14.0;
  static const gap = 8.0;
  static const _margin = EdgeInsets.fromLTRB(14, 6, 14, 8);

  /// The dock's full height over a screen whose bottom inset is
  /// [systemInset], for content padding.
  static double reservedHeight({
    required bool hasMiniPlayer,
    double systemInset = 0,
  }) =>
      math.max(systemInset, _margin.bottom) +
      _margin.top +
      barHeight +
      (hasMiniPlayer ? miniHeight + gap : 0);

  @override
  State<KonnektedDock> createState() => _KonnektedDockState();
}

class _KonnektedDockState extends State<KonnektedDock>
    with SingleTickerProviderStateMixin {
  late final _collapse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: _wantsCollapse ? 1 : 0,
  );

  bool _miniPressed = false;

  bool get _wantsCollapse => widget.collapsed && widget.hasMiniPlayer;

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    // A softer critically-near-damped spring feels continuous rather than
    // snapping the two floating surfaces into their final positions.
    stiffness: 255,
    ratio: .90,
  );

  @override
  void didUpdateWidget(KonnektedDock old) {
    super.didUpdateWidget(old);
    final target = _wantsCollapse ? 1.0 : 0.0;
    if (old.collapsed == widget.collapsed &&
        old.hasMiniPlayer == widget.hasMiniPlayer)
      return;
    if (target == _collapse.value && !_collapse.isAnimating) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _collapse.value = target;
    } else {
      // Start the reverse on this frame rather than carrying momentum away
      // from the user's new direction. Continuing folds keep their velocity.
      _collapse.animateWith(
        SpringSimulation(
          _spring,
          _collapse.value,
          target,
          _collapse.velocity * (target - _collapse.value) > 0
              ? _collapse.velocity
              : 0,
          // Without this the spring rests a hair short of 0 and the folded
          // layer stays on top of the tabs, swallowing their taps.
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _collapse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: KonnektedDock._margin,
    // Fixed-height chrome, like iOS: text grows up to a point, and the full
    // player carries large text beyond it.
    child: MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: _collapse,
              builder: (context, _) => _layout(constraints.maxWidth),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _layout(double width) {
    const bar = KonnektedDock.barHeight;
    const mini = KonnektedDock.miniHeight;
    const compact = KonnektedDock.collapsedHeight;
    const inlineGap = KonnektedDock.inlineSpacing;
    const inset = KonnektedDock.inlineInset;
    const gap = KonnektedDock.gap;
    // Use the physical spring's travel directly. Feeding its value through
    // another easeInOutCubic made the icons stop/start twice and obscured the
    // spring's response on rapid direction reversals.
    final t = _collapse.value.clamp(0.0, 1.0);
    final hasMini = widget.hasMiniPlayer;
    final top = hasMini ? mini + gap : 0.0;

    final tabsOpen = Rect.fromLTWH(0, top, width - bar - gap, bar);
    final tabsShut = const Rect.fromLTWH(inset, 0, compact, compact);
    final searchOpen = Rect.fromLTWH(width - bar, top, bar, bar);
    final searchShut = Rect.fromLTWH(
      width - inset - compact, 0, compact, compact,
    );
    final miniOpen = Rect.fromLTWH(0, 0, width, mini);
    final miniShut = Rect.fromLTWH(
      inset + compact + inlineGap,
      0,
      math.max(80.0, width - 2 * (inset + compact + inlineGap)),
      compact,
    );

    return SizedBox(
      height: lerpDouble(top + bar, compact, t),
      // Its own ink layer, so tap ripples draw on the glass rather than on
      // the page underneath, where the glass would blur them.
      child: Material(
        type: MaterialType.transparency,
        // One backdrop capture for all three pieces of frosted glass.
        child: BackdropGroup(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (hasMini)
                Positioned.fromRect(
                  rect: Rect.lerp(miniOpen, miniShut, t)!,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (!_miniPressed) setState(() => _miniPressed = true);
                    },
                    onPointerUp: (_) {
                      if (_miniPressed) setState(() => _miniPressed = false);
                    },
                    onPointerCancel: (_) {
                      if (_miniPressed) setState(() => _miniPressed = false);
                    },
                    child: AnimatedScale(
                      key: const ValueKey('dock-mini-press'),
                      scale: _miniPressed &&
                              !MediaQuery.disableAnimationsOf(context)
                          ? 1.035
                          : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutBack,
                      child: LokalGlass.capsule(
                    key: const ValueKey('dock-mini-glass'),
                    grouped: true,
                    lens: _dockGlassLens,
                    liquidTintOpacity: lerpDouble(.09, .13, t)!,
                    liquidBlurRadius: _dockBlurRadius,
                    singlePassLens: true,
                    fallbackTintOpacity: lerpDouble(.16, .20, t)!,
                    fallbackBlurSigma: 2,
                    pronouncedRim: true,
                    rimStrength: .82,
                    child: KonnektedMiniPlayerScope(
                      collapsed: t >= 1,
                      progress: t,
                      child: widget.miniPlayer,
                    ),
                      ),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: Rect.lerp(tabsOpen, tabsShut, t)!,
                // The Home bubble flexes *with* the dock spring. It doesn't
                // continue bouncing after the mini player has docked.
                child: Transform.translate(
                  key: const ValueKey('dock-home-bounce'),
                  offset: Offset(
                    hasMini && !MediaQuery.disableAnimationsOf(context)
                        ? dockSelectedLeftBounce(t)
                        : 0,
                    0,
                  ),
                  child: _TabCapsule(
                    width: tabsOpen.width,
                    collapse: t,
                    selected: widget.selected,
                    onSelect: widget.onSelect,
                    onExpand: widget.onExpand,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: Rect.lerp(searchOpen, searchShut, t)!,
                child: _SearchCircle(
                  selected: widget.selected == KonnektedTab.explore,
                  collapse: t,
                  onTap: () => widget.onSelect(KonnektedTab.explore),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells the mini player whether it sits tucked between the circles.
class KonnektedMiniPlayerScope extends InheritedWidget {
  const KonnektedMiniPlayerScope({
    super.key,
    required this.collapsed,
    this.progress,
    required super.child,
  });

  /// Legacy compact state. Actual dock transitions use continuous progress.
  final bool collapsed;

  /// 0 = two-row accessory, 1 = inline with the minimized tab bar.
  /// Null preserves callers that only pass [collapsed] (including tests).
  final double? progress;

  static double progressOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<KonnektedMiniPlayerScope>();
    return (scope?.progress ?? (scope?.collapsed == true ? 1.0 : 0.0))
        .clamp(0.0, 1.0);
  }

  static bool collapsedOf(BuildContext context) =>
      progressOf(context) >= 1;

  @override
  bool updateShouldNotify(KonnektedMiniPlayerScope old) =>
      collapsed != old.collapsed || progress != old.progress;
}

class _TabCapsule extends StatefulWidget {
  const _TabCapsule({
    required this.width,
    required this.collapse,
    required this.selected,
    required this.onSelect,
    required this.onExpand,
  });

  /// The open capsule's width; the tabs keep it while the capsule shrinks.
  final double width;
  final double collapse;
  final KonnektedTab selected;
  final ValueChanged<KonnektedTab> onSelect;
  final VoidCallback? onExpand;

  @override
  State<_TabCapsule> createState() => _TabCapsuleState();
}

class _TabCapsuleState extends State<_TabCapsule>
    with SingleTickerProviderStateMixin {
  // BitChord keeps the selected glass travelling on its own physical spring
  // and preserves velocity when the user retargets a tab before it settles.
  late final AnimationController _selectionPosition;
  late KonnektedTab _lastCapsuleTab;

  @override
  void initState() {
    super.initState();
    _lastCapsuleTab = KonnektedTab.capsule.contains(widget.selected)
        ? widget.selected
        : KonnektedTab.listen;
    _selectionPosition = AnimationController.unbounded(
      vsync: this,
      value: KonnektedTab.capsule.indexOf(_lastCapsuleTab).toDouble(),
    );
  }

  @override
  void didUpdateWidget(_TabCapsule old) {
    super.didUpdateWidget(old);
    final newIndex = KonnektedTab.capsule.indexOf(widget.selected);
    if (old.selected == widget.selected || newIndex < 0) return;
    _lastCapsuleTab = widget.selected;
    if (MediaQuery.disableAnimationsOf(context)) {
      _selectionPosition.value = newIndex.toDouble();
      return;
    }
    _selectionPosition.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 620, damping: 48),
        _selectionPosition.value,
        newIndex.toDouble(),
        _selectionPosition.velocity,
        snapToEnd: true,
      ),
    );
  }

  @override
  void dispose() {
    _selectionPosition.dispose();
    super.dispose();
  }

  static const _tabs = KonnektedTab.capsule;
  static const _inset = 4.0;

  /// The lens follows a dragging finger, like iOS 26's tab bar.
  double? _dragX;
  int? _dragIndex;
  bool _pressed = false;

  double get _slot => (widget.width - 2 * _inset) / _tabs.length;

  int _indexAt(double x) =>
      ((x - _inset) / _slot).floor().clamp(0, _tabs.length - 1);

  void _drag(double x) {
    final index = _indexAt(x);
    if (index != _dragIndex) {
      HapticFeedback.selectionClick();
      _dragIndex = index;
    }
    setState(() => _dragX = x);
  }

  void _endDrag() {
    final index = _dragIndex;
    final position = _dragX == null
        ? null
        : ((_dragX! - _inset) / _slot - .5)
            .clamp(0.0, (_tabs.length - 1).toDouble());
    // Hand the exact finger position and velocity to the same spring
    // responsible for a tapped selection. This avoids an end-drag jump back
    // to the old tab before the selected pill takes off again.
    if (position != null) _selectionPosition.value = position;
    setState(() {
      _dragX = null;
      _dragIndex = null;
    });
    if (index != null && _tabs[index] != widget.selected) {
      widget.onSelect(_tabs[index]);
    } else if (position != null) {
      _selectionPosition.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 620, damping: 48),
          _selectionPosition.value,
          _tabs.indexOf(_lastCapsuleTab).toDouble(),
          0,
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selectedIndex = _tabs.indexOf(widget.selected);
    final shown = _lastCapsuleTab;
    final open = 1 - widget.collapse;

    // The whole lens responds to touch like BitChord's material, squashing
    // gently before the lift. Search stays a separate, non-bouncing sphere.
    return AnimatedBuilder(
      animation: _selectionPosition,
      builder: (context, _) {
        final lensLeft = _dragX != null
            ? (_dragX! - _slot / 2).clamp(_inset, widget.width - _inset - _slot)
            : _inset + _slot *
                _selectionPosition.value.clamp(
                  0.0, (_tabs.length - 1).toDouble(),
                );
        return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_pressed) setState(() => _pressed = true);
      },
      onPointerUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      child: AnimatedScale(
      key: const ValueKey('dock-home-press'),
      scale: reduceMotion ? 1 :
          _dragX != null ? 1 + 16 / widget.width :
          _pressed ? .975 : 1,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutBack,
      child: LokalGlass.capsule(
        key: const ValueKey('dock-tab-glass'),
        grouped: true,
        lens: _dockGlassLens,
        liquidTintOpacity: lerpDouble(.09, .13, widget.collapse)!,
        liquidBlurRadius: _dockBlurRadius,
        singlePassLens: true,
        fallbackTintOpacity: lerpDouble(.16, .20, widget.collapse)!,
        fallbackBlurSigma: 2,
        pronouncedRim: true,
        rimStrength: .82,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Keep the whole expanded subtree mounted at both endpoints.
            // Unmounting it on the final frame flashes a new backdrop/lens
            // hierarchy and can read as a one-frame collapse jitter.
            IgnorePointer(
                ignoring: widget.collapse > .5,
                child: Opacity(
                  opacity: Curves.easeIn.transform(open),
                  child: ExcludeSemantics(
                    excluding: widget.collapse > .5,
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: widget.width,
                      maxWidth: widget.width,
                      child: GestureDetector(
                        onHorizontalDragStart: (d) => _drag(d.localPosition.dx),
                        onHorizontalDragUpdate: (d) =>
                            _drag(d.localPosition.dx),
                        onHorizontalDragEnd: (_) => _endDrag(),
                        onHorizontalDragCancel: _endDrag,
                        child: Stack(
                          children: [
                            Positioned(
                              left: lensLeft,
                              top: _inset,
                              bottom: _inset,
                              width: _slot,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: selectedIndex < 0 && _dragX == null
                                    ? 0
                                    : 1,
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 200),
                                  scale: _dragX != null && !reduceMotion
                                      ? 1.08
                                      : 1,
                                  child: _Lens(
                                    color: t.accent,
                                    active: _dragX != null && !reduceMotion,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(_inset),
                              child: Row(
                                children: [
                                  for (final (i, tab) in _tabs.indexed)
                                    Expanded(
                                      child: _TabButton(
                                        tab: tab,
                                        selected: _dragIndex != null
                                            ? i == _dragIndex
                                            : tab == widget.selected,
                                        hideIcon: tab == shown,
                                        onTap: () => widget.onSelect(tab),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // One moving selection indicator; no second
                            // expensive refractive layer over the tab row.
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            IgnorePointer(
                ignoring: widget.collapse <= .5,
                child: Opacity(
                  opacity: Curves.easeOut.transform(widget.collapse),
                  child: ExcludeSemantics(
                    excluding: widget.collapse <= .5,
                    child: Semantics(
                      button: true,
                      label: lokalText(
                        "Show tabs. {arg0}",
                        args: {'arg0': shown.label},
                      ),
                      onTap: widget.onExpand,
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: widget.onExpand,
                        customBorder: const CircleBorder(),
                        // The glyph is drawn once, outside this fading
                        // layout, so it physically moves from the selected
                        // expanded tab into the compact Home bubble.
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            // BitChord uses a shared element for the selected glyph: unlike
            // a crossfade between two separate icons, this is always one
            // drawable. Its centre follows the capsule as it shrinks and the
            // icon grows from the expanded 22dp to a readable compact ~28dp.
            Builder(
                builder: (context) {
                  final tabIndex = _selectionPosition.value
                      .clamp(0.0, (_tabs.length - 1).toDouble());
                  final visualWidth = lerpDouble(
                    widget.width,
                    KonnektedDock.collapsedHeight,
                    widget.collapse,
                  )!;
                  final fromX = _inset + _slot * (tabIndex + .5);
                  final centreX = lerpDouble(
                    fromX,
                    visualWidth * .5,
                    widget.collapse,
                  )!;
                  final centreY = lerpDouble(
                    22,
                    KonnektedDock.collapsedHeight * .5,
                    widget.collapse,
                  )!;
                  return Positioned(
                    left: centreX - 11,
                    top: centreY - 11,
                    width: 22,
                    height: 22,
                    child: IgnorePointer(
                      child: Transform.scale(
                        key: const ValueKey('dock-shared-selected-icon'),
                        // Keep the house glyph steady. The dock already
                        // shrinks 58→48dp, so enlarging the icon another 20%
                        // and crossfading a second copy added noisy motion
                        // without improving its visibility.
                        scale: 1.08,
                        child: Icon(
                          shown.icon,
                          color: t.accent,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      ),
      );
      },
    );
  }
}

/// The selection lens: a brighter pane of glass under the current tab.
/// Static selected-tab highlight; the parent capsule already refracts.
class _Lens extends StatelessWidget {
  const _Lens({super.key, required this.color, this.active = false});

  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final light = context.lokal.isLight;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: light ? .44 : .24),
            width: .9,
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: active ? .24 : .19),
            color.withValues(alpha: active ? .13 : .09),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.hideIcon = false,
  });

  final KonnektedTab tab;
  final bool selected;
  final VoidCallback onTap;
  /// The selected glyph has a persistent counterpart that moves inline.
  final bool hideIcon;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.lokal.accent : context.lokal.text;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      onTap: onTap,
      child: Tooltip(
        message: tab.label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The shared selected glyph owns the active icon. Leave an
                // identically sized slot without painting an invisible copy
                // or animating another icon beneath it on every dock frame.
                if (hideIcon)
                  const SizedBox(width: 22, height: 22)
                else
                  Icon(
                    tab.icon,
                    size: 22,
                    color: color,
                    shadows: [
                      Shadow(
                        color: context.lokal.isLight
                            ? Colors.white.withValues(alpha: .75)
                            : Colors.black.withValues(alpha: .85),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                const SizedBox(height: 2),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                    shadows: [
                      Shadow(
                        color: context.lokal.isLight
                            ? Colors.white.withValues(alpha: .85)
                            : Colors.black.withValues(alpha: .88),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchCircle extends StatelessWidget {
  const _SearchCircle({
    required this.selected,
    required this.collapse,
    required this.onTap,
  });

  final bool selected;
  final double collapse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    const tab = KonnektedTab.explore;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      onTap: onTap,
      child: Tooltip(
        message: tab.label,
        excludeFromSemantics: true,
        child: LokalGlass.capsule(
          key: const ValueKey('dock-search-glass'),
          grouped: true,
          lens: _dockGlassLens,
          liquidTintOpacity: lerpDouble(.09, .13, collapse)!,
          liquidBlurRadius: _dockBlurRadius,
          singlePassLens: true,
          fallbackTintOpacity: lerpDouble(.16, .20, collapse)!,
          fallbackBlurSigma: 2,
          pronouncedRim: true,
          rimStrength: .82,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selected ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _Lens(
                    color: t.accent,
                  ),
                ),
              ),
              InkWell(
                onTap: onTap,
                excludeFromSemantics: true,
                customBorder: const CircleBorder(),
                child: Icon(
                  tab.icon,
                  size: lerpDouble(26, 23, collapse)!,
                  color: selected ? t.accent : t.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Only the transport adapter subscribes to playback. Position ticks rebuild a
/// three-pixel progress strip, not the home shelves or the navigator.
/// The station mini player uses radio state rather than the local-song
/// provider. It remains visible when navigating away from Stations.
class KonnektedRadioMiniPlayer extends ConsumerWidget {
  const KonnektedRadioMiniPlayer({
    super.key,
    required this.onOpen,
    required this.onQueue,
    this.artworkKey,
    this.onPullUpStart,
    this.onPullUpUpdate,
    this.onPullUpEnd,
  });

  final VoidCallback onOpen;
  final VoidCallback onQueue;
  final Key? artworkKey;
  final VoidCallback? onPullUpStart;
  final ValueChanged<double>? onPullUpUpdate;
  final ValueChanged<double>? onPullUpEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioPlayerProvider);
    final station = radio.station;
    if (station == null) return const SizedBox.shrink();
    final title = radio.trackMetadata?.title ??
        radio.nowPlaying ?? station.title;
    final performer = radio.trackMetadata?.artist.isNotEmpty == true
        ? radio.trackMetadata!.artist : station.title;
    final quality = station.lossless
        ? 'Lossless' : station.bitrate.toString() + ' kbps';
    // Exactly the same mini-player component, artwork Hero, hit regions,
    // marquee, next button and upward pull used by ordinary songs.
    // Only its callbacks and track model are adapted to a live station.
    final display = Song(
      id: 'radio:' + station.id,
      title: title,
      artist: performer + ' · ' + quality,
      albumArt: radio.trackMetadata?.cover ?? station.icon,
      fileType: 'Stream',
      duration: Duration.zero,
    );
    return KonnektedMiniPlayerContent(
      song: display,
      artworkKey: artworkKey,
      isPlaying: radio.playing,
      onOpen: onOpen,
      onQueue: onQueue,
      onPullUpStart: onPullUpStart,
      onPullUpUpdate: onPullUpUpdate,
      onPullUpEnd: onPullUpEnd,
      onPlayPause: () => unawaited(
        ref.read(radioPlayerProvider.notifier).toggle()),
      onNext: () => unawaited(
        ref.read(radioPlayerProvider.notifier).nextStation()),
      onPrevious: () => unawaited(
        ref.read(radioPlayerProvider.notifier).previousStation()),
      // Live broadcasts are not seekable; never invent track progress.
      progress: const SizedBox.shrink(),
    );
  }
}

class KonnektedMiniPlayer extends ConsumerWidget {
  const KonnektedMiniPlayer({
    super.key,
    required this.onOpen,
    required this.onQueue,
    this.onPullUpStart,
    this.onPullUpUpdate,
    this.onPullUpEnd,
    this.artworkKey,
  });

  final Key? artworkKey;
  final VoidCallback onOpen;
  final VoidCallback onQueue;

  /// A finger pulls the mini player up into Now Playing: see
  /// [KonnektedMiniPlayerContent.onPullUpStart].
  final VoidCallback? onPullUpStart;
  final ValueChanged<double>? onPullUpUpdate;
  final ValueChanged<double>? onPullUpEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    return KonnektedMiniPlayerContent(
      song: song,
      artworkKey: artworkKey,
      isPlaying: ref.watch(isPlayingProvider),
      onOpen: onOpen,
      onQueue: onQueue,
      onPullUpStart: onPullUpStart,
      onPullUpUpdate: onPullUpUpdate,
      onPullUpEnd: onPullUpEnd,
      onPlayPause: () {
        AppHaptics.doublePulse();
        _transport(context, () => ref.read(playerProvider.notifier).togglePlayPause());
      },
      onNext: () {
        AppHaptics.triplePulse();
        _transport(context, () => ref.read(playerProvider.notifier).next());
      },
      onPrevious: () {
        AppHaptics.triplePulse();
        _transport(context, () => ref.read(playerProvider.notifier).previous());
      },
      progress: Consumer(
        builder: (context, ref, _) {
          final value = ref.watch(progressProvider);
          return LinearProgressIndicator(
            value: value.isFinite ? value.clamp(0.0, 1.0) : 0,
            minHeight: 2,
            backgroundColor: Colors.white.withValues(alpha: .06),
            color: context.lokal.accent,
            semanticsLabel: 'Track progress',
          );
        },
      ),
    );
  }

  Future<void> _transport(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        LokalToast.show(
          context,
          lokalText('Playback couldn’t be changed. Please try again.'),
        );
      }
    }
  }
}

class KonnektedMiniPlayerContent extends StatelessWidget {
  const KonnektedMiniPlayerContent({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onOpen,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onQueue,
    required this.progress,
    this.onPullUpStart,
    this.onPullUpUpdate,
    this.onPullUpEnd,
    this.artworkKey,
  });

  final Song song;
  final bool isPlaying;
  final Key? artworkKey;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onQueue;
  final Widget progress;

  /// A drag that starts upward on the mini player opens Now Playing under
  /// the finger: this starts it, [onPullUpUpdate] follows each movement
  /// (logical px, positive down, as the sheet moves) and [onPullUpEnd] gets
  /// the release velocity (logical px/s, positive down).
  final VoidCallback? onPullUpStart;
  final ValueChanged<double>? onPullUpUpdate;
  final ValueChanged<double>? onPullUpEnd;

  /// Shared with the full player's artwork, so it grows into Now Playing.
  static const heroTag = 'konnekted-player-art';

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (onPullUpStart == null) return body;
    return _PullUp(
      onStart: onPullUpStart!,
      onUpdate: onPullUpUpdate,
      onEnd: onPullUpEnd,
      onPrevious: onPrevious,
      onNext: onNext,
      child: body,
    );
  }

  Widget _body(BuildContext context) {
    final collapse = KonnektedMiniPlayerScope.progressOf(context);
    // BitChord keeps both title and artist in the narrow accessory. Lokal
    // previously deleted the artist and made the compact player look empty.
    const artistReveal = 1.0;
    final queueReveal = 1 - Curves.easeInOutCubic.transform(
      ((collapse - .18) / .70).clamp(0.0, 1.0),
    );
    final nextReveal = 1 - Curves.easeInOutCubic.transform(
      (collapse / .56).clamp(0.0, 1.0),
    );
    return Stack(
      children: [
        // Glass remains clear, but text needs stable contrast when a bright
        // playlist mosaic scrolls beneath it. This *localized*, feathered
        // scrim protects the title/artist lane without filling the whole
        // capsule with opaque tint or obscuring the album thumbnail.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, .17, .55, 1],
                  colors: [
                    Colors.transparent,
                    (context.lokal.isLight ? Colors.white : Colors.black)
                        .withValues(alpha: .31),
                    (context.lokal.isLight ? Colors.white : Colors.black)
                        .withValues(alpha: .38),
                    (context.lokal.isLight ? Colors.white : Colors.black)
                        .withValues(alpha: .23),
                  ],
                ),
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // The width actively shrinks while collapsing. Check the
            // *expanded* width when deciding whether Next can appear, so
            // it doesn't pop away when crossing 360 logical pixels mid-flight.
            final expandedWidth = constraints.maxWidth +
                2 * (
                  KonnektedDock.inlineInset +
                  KonnektedDock.collapsedHeight +
                  KonnektedDock.inlineSpacing
                ) * collapse;
            final compactAtRest = expandedWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 23;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                lerpDouble(12, 9, collapse)!,
                lerpDouble(4, 0, collapse)!,
                lerpDouble(4, 2, collapse)!,
                lerpDouble(4, 0, collapse)!,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: lokalText(
                        "Open player for {arg0} by {arg1}. Lyrics and playback controls.",
                        args: {'arg0': song.title, 'arg1': song.artist},
                      ),
                      onTap: onOpen,
                      child: InkWell(
                        onTap: onOpen,
                        excludeFromSemantics: true,
                        customBorder: const StadiumBorder(),
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              Hero(
                                tag: heroTag,
                                // The artwork travels directly between the
                                // two real layouts, like BitChord's docked art.
                                createRectTween: (begin, end) =>
                                    LokalArtworkRectTween(begin: begin, end: end),
                                flightShuttleBuilder: _flight,
                                child: SizedBox(
                                  key: artworkKey,
                                  width: lerpDouble(40, 31, collapse)!,
                                  height: lerpDouble(40, 31, collapse)!,
                                  child: _MiniMotionArtwork(
                                    song: song,
                                    playing: isPlaying,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Match the other mini-player layouts:
                                    // only pan if the title exceeds the space
                                    // left by artwork and playback controls.
                                    // A song ID key restarts at the beginning
                                    // instead of inheriting the old scroll.
                                    OverflowMarqueeTitle(
                                      key: ValueKey('dock-mini-title:${song.id}'),
                                      title: song.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: context.lokal.text,
                                        shadows: [
                                          Shadow(
                                            color: context.lokal.isLight
                                                ? Colors.white.withValues(alpha: .85)
                                                : Colors.black.withValues(alpha: .80),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (artistReveal > .001)
                                      ClipRect(
                                        child: Align(
                                          alignment: Alignment.topLeft,
                                          heightFactor: artistReveal,
                                          child: Opacity(
                                            opacity: artistReveal,
                                            child: Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      song.artist,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Color.lerp(
                                                          context.lokal.muted,
                                                          context.lokal.text,
                                                          .75,
                                                        ),
                                                        shadows: [
                                                          Shadow(
                                                            color: context.lokal.isLight
                                                                ? Colors.white.withValues(alpha: .8)
                                                                : Colors.black.withValues(alpha: .8),
                                                            blurRadius: 4,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: ClipRect(
                                                      child: Align(
                                                        alignment: Alignment.centerLeft,
                                                        widthFactor: 1 - collapse,
                                                        child: Opacity(
                                                          opacity: 1 - collapse,
                                                          child: const LokalOutputPill(),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isPlaying ? lokalText('Pause') : lokalText('Play'),
                    onPressed: onPlayPause,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: lerpDouble(29, 24, collapse)!,
                      color: context.lokal.text,
                      shadows: [
                        Shadow(
                          color: context.lokal.isLight
                              ? Colors.white.withValues(alpha: .75)
                              : Colors.black.withValues(alpha: .75),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  if (!compactAtRest)
                    _collapsingControl(
                      reveal: nextReveal,
                      tooltip: lokalText('Next track'),
                      onPressed: onNext,
                      icon: Icons.skip_next_rounded,
                    ),
                  _collapsingControl(
                    reveal: queueReveal,
                    tooltip: lokalText('Open queue'),
                    onPressed: onQueue,
                    icon: Icons.queue_music_rounded,
                    iconSize: 22,
                  ),
                ],
              ),
            );
          },
        ),
        Positioned(left: 24, right: 24, bottom: 0, child: progress),
      ],
    );
  }

  /// Compress an action continuously with the glass rather than removing it
  /// at the halfway point. Disabled taps/semantics prevent hidden controls
  /// intercepting gestures in the collapsed player.
  Widget _collapsingControl({
    required double reveal,
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
    double iconSize = 24,
  }) {
    // Preserve the control subtree throughout the fold. Switching to a
    // SizedBox at reveal=0 recreated the icon button during direction changes.
    return IgnorePointer(
      ignoring: reveal < .85,
      child: ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: reveal,
          child: Opacity(
            opacity: reveal,
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }

  /// Rounds the artwork from the mini player's circle to the normal
  /// full player's actual 20 px corner radius, in both directions.
  Widget _flight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => ClipRRect(
      borderRadius: BorderRadius.circular(
        lerpDouble(21, 20, Curves.easeInOutCubic.transform(animation.value))!,
      ),
      child: child,
    ),
    child: _MiniMotionArtwork(song: song, playing: isPlaying, flight: true),
  );
}

/// Hands a drag that starts upward over to Now Playing; one that starts
/// downward is left alone.
class _PullUp extends StatefulWidget {
  const _PullUp({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onPrevious,
    required this.onNext,
    required this.child,
  });

  final VoidCallback onStart;
  final ValueChanged<double>? onUpdate;
  final ValueChanged<double>? onEnd;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;

  @override
  State<_PullUp> createState() => _PullUpState();
}

class _PullUpState extends State<_PullUp> {
  /// Whether this drag opened Now Playing (null: no direction yet).
  bool? _pulling;
  double _horizontalDelta = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onVerticalDragStart: (_) => _pulling = null,
    onVerticalDragUpdate: (d) {
      if (_pulling == null) {
        _pulling = d.delta.dy < 0;
        if (_pulling!) widget.onStart();
      }
      if (_pulling!) widget.onUpdate?.call(d.delta.dy);
    },
    onVerticalDragEnd: (d) {
      if (_pulling ?? false) widget.onEnd?.call(d.primaryVelocity ?? 0);
      _pulling = null;
    },
    onVerticalDragCancel: () {
      if (_pulling ?? false) widget.onEnd?.call(0);
      _pulling = null;
    },
    onHorizontalDragStart: (_) => _horizontalDelta = 0,
    onHorizontalDragUpdate: (d) => _horizontalDelta += d.delta.dx,
    onHorizontalDragEnd: (d) {
      final velocity = d.primaryVelocity ?? 0;
      final direction = velocity.abs() >= 500 ? velocity : _horizontalDelta;
      _horizontalDelta = 0;
      if (direction <= -48) {
        widget.onNext();
      } else if (direction >= 48) {
        widget.onPrevious();
      }
    },
    onHorizontalDragCancel: () => _horizontalDelta = 0,
    child: widget.child,
  );
}

class _MiniMotionArtwork extends ConsumerWidget {
  const _MiniMotionArtwork({
    required this.song,
    required this.playing,
    this.flight = false,
  });
  final bool flight;
  final Song song;
  final bool playing;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final enabled =
        prefs.animatedAlbumArt &&
        prefs.animationsEnabled &&
        song.filePath != null &&
        !song.isPending &&
        !ref
            .watch(movingCoverSettingsProvider)
            .disabledSongs
            .contains(movingCoverSongKey(song));
    final still = flight
        ? CachedImageWidget(
            imagePath: song.albumArt,
            audioSourcePath: song.filePath,
            fit: BoxFit.cover,
            placeholder: ColoredBox(color: context.lokal.surface3),
            errorWidget: ColoredBox(color: context.lokal.surface3),
          )
        : KonnektedArtwork(song: song, size: 42, radius: 21);
    if (!enabled) return still;
    final art = MotionArtView(
      sharedPlaybackKey: 'player:${song.id}',
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      playbackActive: playing,
      borderRadius: flight ? null : BorderRadius.circular(21),
      fallback: still,
    );
    return flight ? art : ClipOval(child: art);
  }
}
