import 'package:flick/services/artwork_gate.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/l10n/l10n.dart';

import 'dart:async';

import 'package:flick/core/constants/app_constants.dart';
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
  final _storage = PageStorageBucket();
  DateTime? _lastBack;
  bool _nestedSystemBackHandled = false;

  @override
  void initState() {
    super.initState();
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
    AppHaptics.doublePulse();
    nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (_tab.value != tab) {
      // Match PixelPlayer's order-aware root navigation: Library -> Home
      // returns from the left, Home -> Library advances from the right.
      _tabMotionDirection = tab.index > _tab.value.index ? 1 : -1;
      _tab.value = tab;
    }
    _dockCollapsed.value = false;
    if (tab == KonnektedTab.explore) _searchFocusRequests.value++;
  }

  /// Follow the first non-zero user scroll delta, including overscroll at
  /// the top. Ballistic updates cannot undo a deliberate direction reversal.
  /// Horizontal shelves and the dock's own player gestures are outside this.
  bool _onScroll(ScrollNotification n) {
    onScrollNotification(n);
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification ||
        n is OverscrollNotification ||
        (n is UserScrollNotification && n.direction != ScrollDirection.idle)) {
      LokalPerformanceAdvisor.noteScroll();
    }
    double? delta;
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      delta = n.scrollDelta;
    } else if (n is OverscrollNotification && n.dragDetails != null) {
      delta = n.overscroll;
    } else if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse) _dockCollapsed.value = true;
      if (n.direction == ScrollDirection.forward) _dockCollapsed.value = false;
    }
    if (delta != null && delta != 0) _dockCollapsed.value = delta > 0;
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
      unawaited(NavigationHelper.navigateToQueue<void>(context, onOpenPlayer: _openPlayer));
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

  Future<void> _openPlayer({double? from}) async {
    if (from == null && _pull != null) {
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
        lokalText('Couldn’t play this song. Check that its file or server is available.'),
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

  Widget _runtime(Widget child) => widget.runtimeBuilder?.call(child) ??
      KonnektedRuntime(
        onOpenPlayer: _openPlayer,
        onOpenQueue: () => _navigate(KonnektedDestination.queue),
        child: child,
      );

  @override
  void dispose() {
    _pull?.cancel();
    disposeArtworkGate();
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
                  final hasRadio = ref.watch(radioPlayerProvider.select(
                    (state) => state.station != null,
                  ));
                  final hasSong = hasRadio || ref.watch(
                    currentSongProvider.select((song) => song != null),
                  );
                  final media = MediaQuery.of(context);
                  return Stack(
                    children: [
                      MediaQuery(
                        data: media.copyWith(
                          padding: media.padding.copyWith(
                            bottom: KonnektedDock.reservedHeight(
                              hasMiniPlayer: hasSong,
                              systemInset: media.padding.bottom,
                            ),
                          ),
                        ),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: RepaintBoundary(
                            child: NavigatorPopHandler<void>(
                              onPopWithResult: (_) => _popNestedRoute(),
                              child: Navigator(
                                key: nestedNavigatorKey,
                              onGenerateRoute: (_) => MaterialPageRoute<void>(
                                settings: const RouteSettings(name: '/'),
                                builder: (_) => PageStorage(
                                  bucket: _storage,
                                  child: ValueListenableBuilder<KonnektedTab>(
                                    valueListenable: _tab,
                                    builder: (_, tab, _) => LokalNavigationSwitcher(
                                      direction: _tabMotionDirection,
                                      // Keep only recently visited Home/Library/You
                                      // views alive for smooth return entries.
                                      retainVisitedTabs: true,
                                      child: KeyedSubtree(
                                        key: ValueKey(tab),
                                        child: switch (tab) {
                                          KonnektedTab.listen => KonnektedHome(
                                            onNavigate: _navigate,
                                            onPlay: _play,
                                          ),
                                          KonnektedTab.explore => SearchScreen(
                                            footerFocusRequests: _searchFocusRequests,
                                          ),
                                          KonnektedTab.library => KonnektedLibrary(
                                            onNavigate: _navigate,
                                          ),
                                          KonnektedTab.settings => KonnektedYou(
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
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ListenableBuilder(
                          listenable: Listenable.merge([_tab, _dockCollapsed]),
                          builder: (_, _) => KonnektedDock(
                            selected: _tab.value,
                            onSelect: _select,
                            hasMiniPlayer: hasSong,
                            collapsed: _dockCollapsed.value,
                            onExpand: () => _dockCollapsed.value = false,
                            miniPlayer: hasRadio
                                ? KonnektedRadioMiniPlayer(
                                    key: _miniPlayerKey,
                                    artworkKey: _miniArtworkKey,
                                    onOpen: () => unawaited(_openPlayer()),
                                    onQueue: () {
                                      ref.read(radioPlayerProvider.notifier)
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
                              onQueue: () =>
                                  _navigate(KonnektedDestination.queue),
                            ),
                          ),
                        ),
                      ),
                    ],
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
