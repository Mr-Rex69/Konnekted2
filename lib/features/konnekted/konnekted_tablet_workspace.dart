import 'dart:ui' show lerpDouble;

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/lokal_interaction.dart';

import 'konnekted_tablet_footer.dart';

import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/utils/lokal_layout.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';

import 'konnekted_destination.dart';
import 'konnekted_dock.dart';

/// A stable navigator slot across rotation, split view and panel changes.
/// Only the chrome changes; the active page and its scroll state stay mounted.
class KonnektedTabletWorkspace extends StatefulWidget {
  const KonnektedTabletWorkspace({
    super.key,
    required this.child,
    required this.mobileDock,
    required this.player,
    required this.playerSidebar,
    required this.hasPlayer,
    required this.selected,
    required this.route,
    required this.onSelect,
    required this.onNavigate,
    required this.leftOpen,
    required this.rightOpen,
    required this.onToggleLeft,
    required this.onToggleRight,
    this.playerCollapsed = false,
  });

  final Widget child, mobileDock, player, playerSidebar;
  final bool hasPlayer, leftOpen, rightOpen;
  final bool playerCollapsed;
  final KonnektedTab selected;
  final String? route;
  final ValueChanged<KonnektedTab> onSelect;
  final ValueChanged<KonnektedDestination> onNavigate;
  final VoidCallback onToggleLeft, onToggleRight;

  @override
  State<KonnektedTabletWorkspace> createState() =>
      _KonnektedTabletWorkspaceState();
}

class _KonnektedTabletWorkspaceState extends State<KonnektedTabletWorkspace>
    with TickerProviderStateMixin {
  final _panelKey = GlobalKey();
  double _panelWidth = 340;
  late final AnimationController _leftReveal;
  late final AnimationController _rightReveal;
  late final Listenable _sidebarMotion;

  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations ||
      AppConstants.animationNormal == Duration.zero;

  @override
  void initState() {
    super.initState();
    _leftReveal = AnimationController(
      vsync: this,
      duration: LokalMotion.enter,
      value: widget.leftOpen ? 1 : 0,
    );
    _rightReveal = AnimationController(
      vsync: this,
      duration: LokalMotion.enter,
      value: widget.rightOpen ? 1 : 0,
    );
    _sidebarMotion = Listenable.merge([_leftReveal, _rightReveal]);
  }

  void _reveal(AnimationController controller, bool open) {
    // Hiding is deliberately immediate. Only a newly revealed panel animates.
    if (!open || _reducedMotion) {
      controller.stop();
      controller.value = open ? 1 : 0;
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(KonnektedTabletWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftOpen != widget.leftOpen) {
      _reveal(_leftReveal, widget.leftOpen);
    }
    if (oldWidget.rightOpen != widget.rightOpen) {
      _reveal(_rightReveal, widget.rightOpen);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotion) {
      _leftReveal.value = widget.leftOpen ? 1 : 0;
      _rightReveal.value = widget.rightOpen ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _leftReveal.dispose();
    _rightReveal.dispose();
    super.dispose();
  }

  void _resize(double delta) =>
      setState(() => _panelWidth = (_panelWidth + delta).clamp(300, 420));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final media = MediaQuery.of(context);
      // A keyboard changes content height, never the window's chrome mode.
      final tablet = LokalLayout.usesSidebar(
        Size(size.width, media.size.height),
      );
      final docked = tablet && size.width >= 1000;
      final showRight = tablet && widget.rightOpen;
      // Keep navigation density stable while the opposite panel reveals.
      // Its labels must not snap into an icon rail halfway through the motion.
      final extended = size.width >= 1180;
      final fullLeftWidth = (extended ? 216.0 : 80.0) + media.padding.left;
      final rightWidth = _panelWidth.clamp(
        300.0,
        (size.width - 32).clamp(300.0, 420.0),
      );
      final t = context.lokal;
      final navigation = RepaintBoundary(
        child: TickerMode(
          enabled: tablet && widget.leftOpen,
          child: _Sidebar(
            extended: extended,
            selected: widget.selected,
            route: widget.route,
            onSelect: widget.onSelect,
            onNavigate: widget.onNavigate,
          ),
        ),
      );
      final panel = KeyedSubtree(
        key: _panelKey,
        child: RepaintBoundary(
          child: TickerMode(
            enabled: showRight,
            child: Container(
              key: const ValueKey('tablet-player-sidebar'),
              width: rightWidth,
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(left: BorderSide(color: t.border)),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, panelBounds) => MediaQuery(
                        data: media.copyWith(
                          size: panelBounds.biggest,
                          padding: media.padding.copyWith(
                            left: 0,
                            bottom: media.padding.bottom,
                          ),
                        ),
                        child: widget.playerSidebar,
                      ),
                    ),
                  ),
                  if (docked)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 8,
                      child: Semantics(
                        label: lokalText('Resize player sidebar'),
                        onIncrease: () => _resize(24),
                        onDecrease: () => _resize(-24),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: GestureDetector(
                            key: const ValueKey('resize-player-sidebar'),
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: (details) =>
                                _resize(-details.delta.dx),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return AnimatedBuilder(
        animation: _sidebarMotion,
        builder: (context, _) {
          final leftProgress = Curves.easeInOutCubic.transform(
            _leftReveal.value,
          );
          final rightProgress = Curves.easeInOutCubic.transform(
            _rightReveal.value,
          );
          final leftWidth = tablet && widget.leftOpen
              ? fullLeftWidth * leftProgress
              : 0.0;
          final rightExtent = showRight ? rightWidth * rightProgress : 0.0;
          final leftInset = (media.padding.left - leftWidth).clamp(
            0.0,
            media.padding.left,
          );
          final rightInset = (media.padding.right - rightExtent).clamp(
            0.0,
            media.padding.right,
          );
          final footerPaneWidth = size.width - leftWidth - rightExtent;
          // A continuous gutter avoids a small width snap at the compact breakpoint.
          final footerMargin = lerpDouble(
            8,
            16,
            ((footerPaneWidth - 360) / 80).clamp(0.0, 1.0),
          )!;
          final footerWidth =
              footerPaneWidth - footerMargin * 2 - leftInset - rightInset;
          final playerClearance = tablet && widget.hasPlayer
              ? KonnektedTabletFooter.reservedHeight(
                  collapsed:
                      widget.playerCollapsed ||
                      footerWidth < KonnektedTabletFooter.compactBreakpoint,
                  systemInset: media.padding.bottom,
                )
              : media.padding.bottom;
          return LokalContentScope(
            tablet: tablet,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (tablet)
                            Offstage(
                              offstage: !widget.leftOpen,
                              child: _SidebarReveal(
                                key: const ValueKey('tablet-navigation-reveal'),
                                width: fullLeftWidth,
                                progress: leftProgress,
                                alignment: Alignment.centerRight,
                                child: navigation,
                              ),
                            ),
                          Expanded(
                            key: const ValueKey('workspace-content'),
                            child: Column(
                              children: [
                                if (tablet)
                                  SafeArea(
                                    bottom: false,
                                    left: false,
                                    right: false,
                                    child: SizedBox(
                                      height: 44,
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: 8 + leftInset,
                                          right:
                                              8 +
                                              (docked
                                                  ? rightInset
                                                  : media.padding.right),
                                        ),
                                        child: Row(
                                          children: [
                                            IconButton(
                                              key: const ValueKey(
                                                'toggle-left-sidebar',
                                              ),
                                              tooltip: lokalText(
                                                widget.leftOpen
                                                    ? 'Hide navigation sidebar'
                                                    : 'Show navigation sidebar',
                                              ),
                                              isSelected: widget.leftOpen,
                                              onPressed: widget.onToggleLeft,
                                              icon: const Icon(
                                                Icons.menu_rounded,
                                                size: 21,
                                              ),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              key: const ValueKey(
                                                'tablet-header-search',
                                              ),
                                              tooltip: l10n.search,
                                              isSelected:
                                                  widget.selected ==
                                                      KonnektedTab.explore &&
                                                  widget.route == null,
                                              onPressed: () => widget.onSelect(
                                                KonnektedTab.explore,
                                              ),
                                              icon: const Icon(
                                                Icons.search_rounded,
                                                size: 21,
                                              ),
                                            ),
                                            IconButton(
                                              key: const ValueKey(
                                                'toggle-right-sidebar',
                                              ),
                                              tooltip: lokalText(
                                                showRight
                                                    ? 'Hide player sidebar'
                                                    : 'Show player sidebar',
                                              ),
                                              isSelected: showRight,
                                              onPressed: widget.onToggleRight,
                                              icon: Icon(
                                                showRight
                                                    ? Icons
                                                          .chevron_right_rounded
                                                    : Icons
                                                          .view_sidebar_outlined,
                                                size: 21,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  key: const ValueKey('workspace-page'),
                                  child: LayoutBuilder(
                                    builder: (context, pane) => MediaQuery(
                                      data: media.copyWith(
                                        size: pane.biggest,
                                        padding: media.padding.copyWith(
                                          top: tablet ? 0 : media.padding.top,
                                          left: tablet
                                              ? leftInset
                                              : media.padding.left,
                                          right: tablet && docked
                                              ? rightInset
                                              : media.padding.right,
                                          bottom: tablet
                                              ? playerClearance
                                              : KonnektedDock.reservedHeight(
                                                  hasMiniPlayer:
                                                      widget.hasPlayer,
                                                  systemInset:
                                                      media.padding.bottom,
                                                ),
                                        ),
                                      ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          widget.child,
                                          if (!tablet)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              // Page clearance is not a system
                                              // inset: the dock's SafeArea needs
                                              // the original window padding.
                                              child: MediaQuery(
                                                data: media,
                                                child: widget.mobileDock,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showRight && docked)
                            _SidebarReveal(
                              key: const ValueKey('tablet-player-reveal'),
                              width: rightWidth,
                              progress: rightProgress,
                              alignment: Alignment.centerLeft,
                              child: panel,
                            ),
                        ],
                      ),
                      if (!showRight) Offstage(child: panel),
                      if (showRight && !docked) ...[
                        Positioned.fill(
                          child: ModalBarrier(
                            color: t.bg.withValues(alpha: .45 * rightProgress),
                            dismissible: true,
                            onDismiss: widget.onToggleRight,
                            semanticsLabel: lokalText('Close player sidebar'),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          bottom: 0,
                          child: _SidebarReveal(
                            key: const ValueKey('tablet-player-reveal'),
                            width: rightWidth,
                            progress: rightProgress,
                            alignment: Alignment.centerLeft,
                            child: panel,
                          ),
                        ),
                      ],
                      if (tablet && widget.hasPlayer)
                        Positioned(
                          key: const ValueKey('tablet-player-bar'),
                          left: widget.leftOpen ? leftWidth : 0,
                          right: rightExtent,
                          bottom: 0,
                          child: SafeArea(
                            top: false,
                            left: false,
                            right: false,
                            minimum: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: footerMargin + leftInset,
                                right: footerMargin + rightInset,
                              ),
                              child: widget.player,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// The panel retains its final internal width while the slot slides open.
/// Only clipping/offset and the neighbouring pane extents change each frame.
class _SidebarReveal extends StatelessWidget {
  const _SidebarReveal({
    super.key,
    required this.width,
    required this.progress,
    required this.alignment,
    required this.child,
  });
  final double width, progress;
  final Alignment alignment;
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRect(
    child: SizedBox(
      width: width * progress,
      child: OverflowBox(
        alignment: alignment,
        minWidth: width,
        maxWidth: width,
        child: ExcludeSemantics(
          excluding: progress < 1,
          child: IgnorePointer(ignoring: progress < 1, child: child),
        ),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.extended,
    required this.selected,
    required this.route,
    required this.onSelect,
    required this.onNavigate,
  });
  final bool extended;
  final KonnektedTab selected;
  final String? route;
  final ValueChanged<KonnektedTab> onSelect;
  final ValueChanged<KonnektedDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final shortcuts = [
      ('Songs', Icons.music_note_rounded, KonnektedDestination.songs),
      ('Albums', Icons.album_rounded, KonnektedDestination.albums),
      ('Artists', Icons.mic_external_on_rounded, KonnektedDestination.artists),
      ('Playlists', Icons.queue_music_rounded, KonnektedDestination.playlists),
      ('Liked', Icons.favorite_rounded, KonnektedDestination.favorites),
      ('Folders', Icons.folder_rounded, KonnektedDestination.folders),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        right: false,
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 16, 28),
              child: Row(
                children: [
                  const LokalLogo(size: 32),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Lokal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.text,
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('tablet-navigation-list'),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final tab in [KonnektedTab.listen, KonnektedTab.library])
                    _item(
                      context,
                      tab.localizedLabel,
                      tab.icon,
                      active: route == null && selected == tab,
                      onTap: () => onSelect(tab),
                    ),
                  for (final (label, icon, destination) in shortcuts)
                    _item(
                      context,
                      lokalText(label),
                      icon,
                      active: route == '/konnekted/${destination.name}',
                      onTap: () => onNavigate(destination),
                    ),
                  _item(
                    context,
                    KonnektedTab.settings.localizedLabel,
                    Icons.person_rounded,
                    active: route == null && selected == KonnektedTab.settings,
                    onTap: () => onSelect(KonnektedTab.settings),
                  ),
                  _item(
                    context,
                    lokalText('Settings'),
                    Icons.settings_rounded,
                    active: route?.contains('settings') == true,
                    onTap: () => onNavigate(KonnektedDestination.settings),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String label,
    IconData icon, {
    required bool active,
    required VoidCallback onTap,
  }) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: Tooltip(
          message: extended ? '' : label,
          child: LokalGlass(
            staticSurface: true,
            shadow: false,
            tint: active
                ? Color.alphaBlend(t.accentSoft, t.surface)
                : t.surface,
            rimStrength: active ? .45 : 0,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: extended ? 14 : 0,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisAlignment: extended
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 23, color: active ? t.accent : t.muted),
                      if (extended) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: active ? t.text : t.muted,
                              fontSize: 14,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
