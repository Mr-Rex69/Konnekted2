import 'package:flick/core/utils/lokal_layout.dart';

import 'konnekted_tablet_footer.dart';
import 'konnekted_tablet_player_sidebar.dart';
import 'tablet_playback.dart';
import 'tablet_sidebar_preferences.dart';

import 'konnekted_tablet_workspace.dart';

import 'package:flick/services/artwork_gate.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';
import 'package:flick/l10n/l10n.dart';

import 'dart:async';

import 'package:flick/core/navigation/root_navigator.dart';
import 'package:flick/core/navigation/lokal_navigation_switcher.dart';
import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'package:flick/core/theme/adaptive_color_provider.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/core/utils/navigation_helper.dart';
import 'package:flick/features/flow/flow_screen.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/folders/screens/folders_screen.dart';
import 'package:flick/features/playlist_links/linked_playlists_screen.dart';
import 'package:flick/features/spotify/spotify_playlists_screen.dart';
import 'package:flick/features/discovery/youtube_music_playlists_screen.dart';
import 'package:flick/features/recap/screens/listening_recap_screen.dart';
import 'package:flick/features/search/screens/search_screen.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/album_color_provider.dart';
import 'package:flick/providers/navigation_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/widgets/lokal/lokal_player_route.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_destination.dart';
import 'konnekted_dock.dart';
import 'konnekted_home.dart';
import 'konnekted_library.dart';
import 'konnekted_runtime.dart';
import 'konnekted_you.dart';
import 'library/lokal_library_pages.dart';

/// A thresholded scroll-direction gate. The previous shell toggled the glass
/// dock on *every* tiny drag/overscroll, causing its spring and backdrop shader
/// to repeatedly reverse in the middle of a fold.
@visibleForTesting
class DockScrollHysteresis {
  DockScrollHysteresis({this.threshold = 24});

  final double threshold;
  double _pending = 0;

  bool? push(double delta, {required bool collapsed}) {
    if (!delta.isFinite || delta == 0) return null;
    final requested = delta > 0;
    if (requested == collapsed) {
      _pending = 0;
      return null;
    }
    if (_pending != 0 && _pending.sign != delta.sign) _pending = 0;
    _pending += delta;
    if (_pending.abs() < threshold) return null;
    _pending = 0;
    return requested;
  }

  void reset() => _pending = 0;
}

/// The post-onboarding entry point. Keep Flick's existing root navigator and
/// bootstrap; this shell owns the nested navigator and native shell lifecycle.
class KonnektedShell extends ConsumerStatefulWidget {
  const KonnektedShell({super.key, this.runtimeBuilder});

  /// Allows navigation tests to mount the shell without native services.
  @visibleForTesting
  final Widget Function(Widget child)? runtimeBuilder;

  @override
  ConsumerState<KonnektedShell> createState() => _KonnektedShellState();
}

class _KonnektedShellState extends ConsumerState<KonnektedShell>
    with ArtworkExtractionScrollGate {
  final _tab = ValueNotifier(KonnektedTab.listen);
  int _tabMotionDirection = 1;
  // Explicit bottom-bar Search taps, including reselecting an open Search tab.
  // The lazy Search page observes this without forcing a shell rebuild.
  final _searchFocusRequests = ValueNotifier<int>(0);
  final _dockCollapsed = ValueNotifier(false);
  final _dockScroll = DockScrollHysteresis();
  final _storage = PageStorageBucket();
  final _route = ValueNotifier<String?>(null);
  late final _sidebars = TabletSidebarPreferences();
  ValueNotifier<bool?> get _rightVisible => _sidebars.rightOpen;
  ValueNotifier<bool> get _leftVisible => _sidebars.leftOpen;
  final _panelTab = ValueNotifier(TabletPlayerTab.details);
  late final _routeObserver = _WorkspaceRouteObserver((name) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _route.value = name == '/' ? null : name ?? '@detail';
    });
  });
  DateTime? _lastBack;
  bool _nestedSystemBackHandled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_sidebars.ready);
    // Legacy screens return Flick's old indices. They are navigation requests,
    // not the indices of Konnekted's four destinations.
    ref.listenManual<int>(navigationIndexProvider, (_, index) {
      if (index < 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _legacyNavigate(index);
        ref.read(navigationIndexProvider.notifier).setIndex(-1);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navigationIndexProvider.notifier).setIndex(-1);
    });
  }

  void _select(KonnektedTab tab) {
    LokalPerformanceAdvisor.noteNavigation(surface: 'tabs');
    AppHaptics.selection();
    nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (_tab.value != tab) {
      // Follow the dock's physical left-to-right order, not the enum order:
      // Search is to the right of Library and You, despite being declared
      // before Library in KonnektedTab.
      _tabMotionDirection =
          KonnektedTab.dockOrder.indexOf(tab) >
              KonnektedTab.dockOrder.indexOf(_tab.value)
          ? 1
          : -1;
      _tab.value = tab;
    }
    _dockScroll.reset();
    _dockCollapsed.value = false;
    if (tab == KonnektedTab.explore) _searchFocusRequests.value++;
  }

  /// Only a meaningful *accumulated* user drag changes the footer's state.
  /// Do not also react to UserScrollNotification: those direction changes can
  /// arrive between minute drag/overscroll deltas and ping-pong the spring.
  /// Ballistic activity continues without changing the explicit user intent.
  bool _onScroll(ScrollNotification n) {
    onScrollNotification(n);
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification ||
        n is OverscrollNotification ||
        (n is UserScrollNotification && n.direction != ScrollDirection.idle)) {
      LokalPerformanceAdvisor.noteScroll(
        surface: switch (_tab.value) {
          KonnektedTab.listen => 'Home',
          KonnektedTab.library => 'Library',
          KonnektedTab.settings => 'You',
          KonnektedTab.explore => 'Search',
        },
      );
    }

    if (n is ScrollEndNotification ||
        (n is UserScrollNotification && n.direction == ScrollDirection.idle)) {
      _dockScroll.reset();
      return false;
    }
    double? delta;
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      delta = n.scrollDelta;
    } else if (n is OverscrollNotification && n.dragDetails != null) {
      delta = n.overscroll;
    }
    if (delta != null) {
      final next = _dockScroll.push(delta, collapsed: _dockCollapsed.value);
      if (next != null) _dockCollapsed.value = next;
    }
    return false;
  }

  void _legacyNavigate(int index) {
    if (index == 0) {
      _select(KonnektedTab.listen);
    } else if (index == 2) {
      _select(KonnektedTab.settings);
    } else {
      final destination = switch (index) {
        1 => KonnektedDestination.songs,
        3 => KonnektedDestination.albums,
        4 => KonnektedDestination.artists,
        5 => KonnektedDestination.folders,
        6 => KonnektedDestination.playlists,
        7 => KonnektedDestination.favorites,
        8 => KonnektedDestination.search,
        _ => null,
      };
      if (destination != null) {
        var found = false;
        nestedNavigatorKey.currentState?.popUntil((route) {
          found = route.settings.name == '/konnekted/${destination.name}';
          return found || route.isFirst;
        });
        if (!found) _navigate(destination);
      }
    }
  }

  void _navigate(KonnektedDestination destination) {
    LokalPerformanceAdvisor.noteNavigation();
    if (destination == KonnektedDestination.queue) {
      unawaited(
        NavigationHelper.navigateToQueue<void>(
          context,
          onOpenPlayer: _openPlayer,
        ),
      );
      return;
    }
    final navigator = nestedNavigatorKey.currentState;
    if (navigator == null) return;
    if (destination.isSettings) {
      unawaited(
        navigator.push<void>(
          lokalSettingsRoute(
            context,
            group: destination.settingsGroup,
            section: destination.settingsSection,
            aboutDataOnly: destination.aboutDataOnly,
          ),
        ),
      );
      return;
    }
    // Material routes now use LokalPageMotion, including native Android
    // predictive back. A custom PageRouteBuilder here previously bypassed
    // that theme and left explicit Back and gesture Back looking different.
    unawaited(
      navigator.push<void>(
        LokalPageRoute<void>(
          settings: RouteSettings(name: '/konnekted/${destination.name}'),
          builder: (_) => _destination(destination),
        ),
      ),
    );
  }

  Widget _destination(KonnektedDestination destination) =>
      lokalLibraryPage(destination.name) ??
      switch (destination.name) {
        'flow' => const FlowScreen(),
        'search' => const SearchScreen(),
        'folders' => const FoldersScreen(),
        'recap' => const ListeningRecapScreen(),
        'linkedPlaylists' => const LinkedPlaylistsScreen(),
        'spotifyPlaylists' => SpotifyPlaylistsScreen(onPlay: _play),
        'youtubeMusicPlaylists' => YoutubeMusicPlaylistsScreen(onPlay: _play),
        'settings' => lokalSettingsPage(
          group: destination.settingsGroup,
          section: destination.settingsSection,
          aboutDataOnly: destination.aboutDataOnly,
        ),
        _ => const SizedBox.shrink(),
      };

  /// The mini player, for where Now Playing rises from and sinks back to.
  final _miniPlayerKey = GlobalKey();
  final _miniArtworkKey = GlobalKey();
  final _playerPageKey = GlobalKey();

  Rect? _miniArtworkRect() {
    final box = _miniArtworkKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Now Playing while a finger pulls it up out of the mini player.
  LokalPlayerPull? _pull;

  /// The mini player's top edge on screen, or null when it isn't showing.
  double? _miniPlayerTop() {
    final box = _miniPlayerKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  static const _playerHero = 'konnekted-player-art';

  Future<void> _openPlayer({double? from, bool initialLyrics = false}) async {
    if (initialLyrics && _pull != null) {
      _pull!.cancel();
      _pull = null;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    if (!initialLyrics && from == null && _pull != null) {
      _pull!.open();
      return;
    }
    final result = await NavigationHelper.navigateToFullPlayer(
      context,
      heroTag: _playerHero,
      startTop: _miniPlayerTop,
      initialProgress: from,
      sourceArtwork: _miniArtworkRect,
      playerKey: _playerPageKey,
      initialLyrics: initialLyrics,
    );
    if (result != null && mounted) _legacyNavigate(result);
  }

  void _pullPlayerStart() {
    if (_pull != null) {
      _pull!.resume();
      return;
    }
    _pull = NavigationHelper.pullFullPlayer(
      context,
      heroTag: _playerHero,
      startTop: _miniPlayerTop,
      sourceArtwork: _miniArtworkRect,
      playerKey: _playerPageKey,
      onClosed: () => _pull = null,
      onOpen: (progress) {
        _pull = null;
        if (mounted) unawaited(_openPlayer(from: progress));
      },
    );
  }

  void _pullPlayerEnd(double velocityDown) {
    _pull?.end(velocityDown);
  }

  Future<void> _play(Song song, List<Song> songs) async {
    try {
      await ref.read(playerProvider.notifier).play(song, playlist: songs);
    } catch (_) {
      if (!mounted) return;
      LokalToast.show(
        context,
        lokalText(
          'Couldn’t play this song. Check that its file or server is available.',
        ),
      );
    }
  }

  // Only the child navigator dismisses child routes. This prevents a
  // committed system-back gesture from also switching the root tab.
  void _popNestedRoute() {
    final navigator = nestedNavigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return;
    _nestedSystemBackHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nestedSystemBackHandled = false;
    });
    navigator.pop();
  }

  void _back(bool didPop, Object? result) {
    if (didPop || _nestedSystemBackHandled) return;
    if (_overlayPlayerOpen) {
      _rightVisible.value = false;
      return;
    }
    // Child Back is owned by NavigatorPopHandler; this callback is for
    // switching tabs / double-back exit when the child is already at root.
    if (nestedNavigatorKey.currentState?.canPop() == true) return;
    if (_tab.value != KonnektedTab.listen) {
      _select(KonnektedTab.listen);
    } else {
      final now = DateTime.now();
      if (_lastBack != null &&
          now.difference(_lastBack!) < const Duration(seconds: 2)) {
        SystemNavigator.pop();
      } else {
        _lastBack = now;
        LokalToast.show(
          context,
          lokalText('Press back again to exit'),
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  bool get _rightOpen =>
      _rightVisible.value ??
      (MediaQuery.sizeOf(context).width >= 1000 &&
          (ref.read(currentSongProvider) != null ||
              ref.read(radioPlayerProvider).station != null));

  bool get _overlayPlayerOpen =>
      LokalLayout.usesSidebar(MediaQuery.sizeOf(context)) &&
      MediaQuery.sizeOf(context).width < 1000 &&
      _rightOpen;

  void _toggleRight() => _rightVisible.value = !_rightOpen;

  void _showPlayerPanel(TabletPlayerTab tab) {
    if (!LokalLayout.usesSidebar(MediaQuery.sizeOf(context))) {
      if (tab == TabletPlayerTab.queue) {
        _navigate(KonnektedDestination.queue);
      } else {
        unawaited(_openPlayer());
      }
      return;
    }
    final close = _rightOpen && _panelTab.value == tab;
    _panelTab.value = tab;
    _rightVisible.value = !close;
  }

  void _queueFromMiniPlayer() => _showPlayerPanel(TabletPlayerTab.queue);

  Widget _runtime(Widget child) =>
      widget.runtimeBuilder?.call(child) ??
      KonnektedRuntime(
        onOpenPlayer: _openPlayer,
        onOpenQueue: _queueFromMiniPlayer,
        child: child,
      );

  @override
  void dispose() {
    _pull?.cancel();
    disposeArtworkGate();
    _route.dispose();
    _sidebars.dispose();
    _panelTab.dispose();
    _tab.dispose();
    _searchFocusRequests.dispose();
    _dockCollapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artworkColor = ref.watch(albumDominantColorSyncProvider);
    final tint = Color.lerp(
      context.lokal.bg,
      artworkColor ?? context.lokal.accent,
      .13,
    )!;
    // The Lokal theme comes from MaterialApp; artwork only tints the backdrop.
    return AdaptiveColorProvider(
      backgroundColor: context.lokal.bg,
      albumDominantColor: artworkColor,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: _back,
        child: Scaffold(
          backgroundColor: context.lokal.bg,
          body: _runtime(
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [tint, context.lokal.bg],
                  stops: const [0, .55],
                ),
              ),
              // The dock floats over the content, so glass has something to
              // refract; pages get its height as bottom padding instead.
              child: Consumer(
                builder: (context, ref, _) {
                  final hasRadio = ref.watch(
                    radioPlayerProvider.select(
                      (state) => state.station != null,
                    ),
                  );
                  final hasSong =
                      hasRadio ||
                      ref.watch(
                        currentSongProvider.select((song) => song != null),
                      );
                  final miniPlayer = hasRadio
                      ? KonnektedRadioMiniPlayer(
                          key: _miniPlayerKey,
                          artworkKey: _miniArtworkKey,
                          onOpen: () => unawaited(_openPlayer()),
                          onQueue: () {
                            ref
                                .read(radioPlayerProvider.notifier)
                                .requestStationQueue();
                            unawaited(_openPlayer());
                          },
                          onPullUpStart: _pullPlayerStart,
                          onPullUpUpdate: (dy) => _pull?.dragBy(dy),
                          onPullUpEnd: _pullPlayerEnd,
                        )
                      : KonnektedMiniPlayer(
                          key: _miniPlayerKey,
                          artworkKey: _miniArtworkKey,
                          onOpen: _openPlayer,
                          onPullUpStart: _pullPlayerStart,
                          onPullUpUpdate: (dy) => _pull?.dragBy(dy),
                          onPullUpEnd: _pullPlayerEnd,
                          onQueue: _queueFromMiniPlayer,
                        );
                  return ListenableBuilder(
                    listenable: Listenable.merge([
                      _tab,
                      _dockCollapsed,
                      _route,
                      _rightVisible,
                      _leftVisible,
                      _panelTab,
                    ]),
                    builder: (context, _) => KonnektedTabletWorkspace(
                      selected: _tab.value,
                      route: _route.value,
                      onSelect: _select,
                      onNavigate: (destination) {
                        // Sidebar links are peers, rather than an ever-growing
                        // stack of Library pages. Detail pushes still use Back.
                        nestedNavigatorKey.currentState?.popUntil(
                          (route) => route.isFirst,
                        );
                        _navigate(destination);
                      },
                      hasPlayer: hasSong,
                      playerCollapsed: _dockCollapsed.value,
                      leftOpen: _leftVisible.value,
                      rightOpen: _rightOpen,
                      onToggleLeft: () =>
                          _leftVisible.value = !_leftVisible.value,
                      onToggleRight: _toggleRight,
                      player: KonnektedTabletFooter(
                        key: _miniPlayerKey,
                        artworkKey: _miniArtworkKey,
                        collapsed: _dockCollapsed.value,
                        onExpand: () => _dockCollapsed.value = false,
                        onOpenPlayer: _openPlayer,
                        onOpenPanel: _showPlayerPanel,
                      ),
                      playerSidebar: KonnektedTabletPlayerSidebar(
                        onOpenLyrics: () => _openPlayer(initialLyrics: true),
                        active:
                            LokalLayout.usesSidebar(
                              MediaQuery.sizeOf(context),
                            ) &&
                            _rightOpen,
                        tab: _panelTab.value,
                        onTabChanged: (tab) => _panelTab.value = tab,
                        onClose: () => _rightVisible.value = false,
                        onOpenPlayer: _openPlayer,
                      ),
                      mobileDock: KonnektedDock(
                        selected: _tab.value,
                        onSelect: _select,
                        hasMiniPlayer: hasSong,
                        collapsed: _dockCollapsed.value,
                        onExpand: () => _dockCollapsed.value = false,
                        miniPlayer: miniPlayer,
                      ),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: RepaintBoundary(
                          child: NavigatorPopHandler<void>(
                            enabled: !_overlayPlayerOpen,
                            onPopWithResult: (_) => _popNestedRoute(),
                            child: Navigator(
                              key: nestedNavigatorKey,
                              observers: [_routeObserver],
                              onGenerateRoute: (_) => MaterialPageRoute<void>(
                                settings: const RouteSettings(name: '/'),
                                builder: (_) => PageStorage(
                                  bucket: _storage,
                                  child: ValueListenableBuilder<KonnektedTab>(
                                    valueListenable: _tab,
                                    builder: (_, tab, _) =>
                                        LokalNavigationSwitcher(
                                          direction: _tabMotionDirection,
                                          retainVisitedTabs: true,
                                          child: KeyedSubtree(
                                            key: ValueKey(tab),
                                            child: switch (tab) {
                                              KonnektedTab.listen =>
                                                KonnektedHome(
                                                  onNavigate: _navigate,
                                                  onPlay: _play,
                                                ),
                                              KonnektedTab.explore =>
                                                SearchScreen(
                                                  footerFocusRequests:
                                                      _searchFocusRequests,
                                                ),
                                              KonnektedTab.library =>
                                                KonnektedLibrary(
                                                  onNavigate: _navigate,
                                                ),
                                              KonnektedTab.settings =>
                                                KonnektedYou(
                                                  onNavigate: _navigate,
                                                ),
                                            },
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceRouteObserver extends NavigatorObserver {
  _WorkspaceRouteObserver(this.onChanged);
  final ValueChanged<String?> onChanged;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged(route.settings.name);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged(previousRoute?.settings.name);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      onChanged(newRoute?.settings.name);
}
