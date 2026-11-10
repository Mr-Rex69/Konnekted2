import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/utils/lokal_layout.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';

import 'konnekted_destination.dart';
import 'konnekted_dock.dart';

/// A stable navigator slot across rotation, split view and panel changes.
/// Only the chrome changes; the active page and its scroll state stay mounted.
class KonnektedTabletWorkspace extends StatelessWidget {
  const KonnektedTabletWorkspace({
    super.key,
    required this.child,
    required this.mobileDock,
    required this.player,
    required this.hasPlayer,
    required this.selected,
    required this.route,
    required this.onSelect,
    required this.onNavigate,
    required this.queue,
    required this.queueOpen,
    required this.onToggleQueue,
    this.supportsQueuePanel = true,
  });

  final Widget child, mobileDock, player, queue;
  final bool hasPlayer, queueOpen;
  final bool supportsQueuePanel;
  final KonnektedTab selected;
  final String? route;
  final ValueChanged<KonnektedTab> onSelect;
  final ValueChanged<KonnektedDestination> onNavigate;
  final VoidCallback onToggleQueue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      // Keyboard insets shrink the body, not the window's navigation mode.
      final tablet = LokalLayout.usesSidebar(
        Size(size.width, MediaQuery.sizeOf(context).height),
      );
      final canShowQueue = tablet && supportsQueuePanel && size.width >= 1180;
      final showQueue = canShowQueue && hasPlayer && queueOpen;
      final extended = size.width >= (showQueue ? 1280 : 1000);
      final t = context.lokal;
      final media = MediaQuery.of(context);
      return LokalContentScope(
        tablet: tablet,
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tablet)
                    SizedBox(
                      width: (extended ? 216 : 80) + media.padding.left,
                      child: _Sidebar(
                        extended: extended,
                        selected: selected,
                        route: route,
                        onSelect: onSelect,
                        onNavigate: onNavigate,
                      ),
                    ),
                  Expanded(
                    key: const ValueKey('workspace-content'),
                    child: LayoutBuilder(
                      builder: (context, pane) => LokalContentScope(
                        tablet: tablet,
                        child: MediaQuery(
                          data: media.copyWith(
                            size: pane.biggest,
                            padding: media.padding.copyWith(
                              left: tablet ? 0 : media.padding.left,
                              right: showQueue ? 0 : media.padding.right,
                              bottom: tablet
                                  ? (hasPlayer ? 0 : media.padding.bottom)
                                  : KonnektedDock.reservedHeight(
                                      hasMiniPlayer: hasPlayer,
                                      systemInset: media.padding.bottom,
                                    ),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              child,
                              if (!tablet)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: mobileDock,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showQueue)
                    Container(
                      key: const ValueKey('tablet-queue-panel'),
                      width: 320,
                      decoration: BoxDecoration(
                        color: t.surface,
                        border: Border(left: BorderSide(color: t.border)),
                      ),
                      child: SafeArea(
                        left: false,
                        bottom: false,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                tooltip: lokalText('Close'),
                                onPressed: onToggleQueue,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ),
                            Expanded(child: queue),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (tablet && hasPlayer)
              Container(
                key: const ValueKey('tablet-player-bar'),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: player,
                  ),
                ),
              ),
          ],
        ),
      );
    },
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final tab in [
                    KonnektedTab.listen,
                    KonnektedTab.explore,
                    KonnektedTab.library,
                  ])
                    _item(
                      context,
                      tab.localizedLabel,
                      tab.icon,
                      active: route == null && selected == tab,
                      onTap: () => onSelect(tab),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 22,
                    ),
                    child: extended
                        ? Text(
                            lokalText('Library').toUpperCase(),
                            style: LokalTheme.label(t),
                          )
                        : Divider(color: t.border),
                  ),
                  for (final (label, icon, destination) in shortcuts)
                    _item(
                      context,
                      lokalText(label),
                      icon,
                      active: route == '/konnekted/${destination.name}',
                      onTap: () => onNavigate(destination),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                children: [
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
