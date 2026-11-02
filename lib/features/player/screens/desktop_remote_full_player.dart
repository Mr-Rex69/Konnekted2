import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
import 'package:flick/features/player/widgets/full_player_visuals.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
import 'package:flick/features/player/widgets/song_stage_carousel.dart';
import 'package:flick/features/player/screens/desktop_remote_lyrics_panel.dart';
import 'package:flick/features/queue/screens/queue_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/widgets/lokal/lokal_pull_to_dismiss.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flick/widgets/lokal/lokal_player_route.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flick/widgets/lokal/lokal_queue_reveal.dart';

/// Full player for the *remote* desktop transport, mounted within the normal
/// FullPlayerScreen route. Never reads PlayerService.currentSongNotifier:
/// that notifier still contains the last song played by the phone.
class DesktopRemoteFullPlayer extends ConsumerStatefulWidget {
  const DesktopRemoteFullPlayer({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<DesktopRemoteFullPlayer> createState() => _DesktopRemoteFullPlayerState();
}

class _DesktopRemoteFullPlayerState extends ConsumerState<DesktopRemoteFullPlayer>
    with SingleTickerProviderStateMixin {
  double? _seekDrag;
  double? _volumeDrag;
  bool _showLyrics = false;
  late final AnimationController _queueController = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 350),
  );
  late final LokalQueueRevealMotion _queueMotion =
      LokalQueueRevealMotion(_queueController);

  void _openQueue() {
    if (_showLyrics) setState(() => _showLyrics = false);
    _queueMotion.setOpen(true);
  }

  void _closeQueue() => _queueMotion.setOpen(false);

  Future<void> _remoteNext() =>
      ref.read(playerProvider.notifier).next();

  Future<void> _remotePrevious() =>
      ref.read(playerProvider.notifier).previousBySwipe();

  final ScrollController _contentScroll = ScrollController();
  bool _contentOverflows = false;
  bool _overflowCheckQueued = false;

  /// Measure the rendered extent after layout, including accessibility text
  /// scaling, rather than guessing from a fixed viewport-height threshold.
  void _checkContentOverflow() {
    if (_overflowCheckQueued) return;
    _overflowCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overflowCheckQueued = false;
      if (!mounted || !_contentScroll.hasClients) return;
      final overflows = _contentScroll.position.maxScrollExtent > 1;
      if (overflows != _contentOverflows) {
        setState(() => _contentOverflows = overflows);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkContentOverflow();
  }

  @override
  void dispose() {
    _contentScroll.dispose();
    _queueMotion.dispose();
    _queueController.dispose();
    super.dispose();
  }

  // When actual content overflows, downward overscroll at the top must still
  // transfer the gesture to the normal full-player dismissal spring.
  LokalPlayerRoute<dynamic>? _overscrollRoute;
  double _overscrollDistance = 0;

  bool _onCompactScroll(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      final route = LokalPlayerRoute.maybeOf(context);
      if (route != null) {
        if (_overscrollRoute == null) {
          route.startDrag();
          _overscrollRoute = route;
        }
        route.dragBy(-notification.overscroll);
      } else {
        _overscrollDistance += -notification.overscroll;
      }
    } else if (notification is ScrollEndNotification) {
      final route = _overscrollRoute;
      _overscrollRoute = null;
      route?.endDrag(0);
      if (route == null &&
          _overscrollDistance > MediaQuery.sizeOf(context).height * .25) {
        widget.onClose();
      }
      _overscrollDistance = 0;
    }
    return false; // Preserve ordinary scrolling and nested notifications.
  }

  Future<void> _command(Future<void> Function() command) async {
    try {
      if (!ref.read(lokalRemoteControllerProvider).controlsDesktop) return;
      await command();
    } catch (_) {
      if (mounted) {
        LokalToast.show(context, lokalText('Playback couldn’t be changed. Please try again.'));
      }
    }
  }

  String _clock(Duration duration) {
    final seconds = math.max(0, duration.inSeconds);
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(lokalRemoteControllerProvider);
    final player = ref.watch(playerProvider);
    final song = player.currentSong;
    final currentTrack = remote.snapshot?.currentTrack;
    // Match the local full player: remote control changes the transport,
    // not the listener's chosen artwork presentation.
    final fullCover = ref.watch(
      lokalAppearanceProvider.select((look) => look.fullscreenCover),
    );
    final playlist = remote.snapshot?.queue ?? const <LokalRemoteTrack>[];
    final currentIndex = remote.snapshot?.currentIndex ?? -1;
    final nextTrack = currentIndex >= 0 && currentIndex + 1 < playlist.length
        ? songFromDesktopRemoteTrack(playlist[currentIndex + 1],
            artworkServerId: remote.artworkServerId)
        : null;
    final previousTrack = currentIndex > 0 && currentIndex < playlist.length
        ? songFromDesktopRemoteTrack(playlist[currentIndex - 1],
            artworkServerId: remote.artworkServerId)
        : null;
    const ink = FullPlayerVisuals.primaryText;
    const secondary = FullPlayerVisuals.secondaryText;

    _queueMotion.travel = MediaQuery.sizeOf(context).height * .7;
    return PopScope(
      canPop: !_queueMotion.isOpen && !_showLyrics,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_queueMotion.isOpen) _closeQueue();
        else if (_showLyrics) setState(() => _showLyrics = false);
      },
      child: LokalPullToDismiss(
      onDismiss: widget.onClose,
      isBlocked: () => _queueMotion.isOpen || _showLyrics,
      onPullUpUpdate: _queueMotion.dragBy,
      onPullUpEnd: (velocity) => _queueMotion.release(velocity),
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0C0F),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF28272E), Color(0xFF17171C), Color(0xFF080809)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (fullCover && song != null)
                FullBleedArtworkFrame(
                  canvas: false,
                  dimOnExpand: false,
                  child: SongStageCarousel(
                    key: const ValueKey('desktop-cover-carousel-full'),
                    currentSong: song,
                    nextSong: nextTrack,
                    prevSong: previousTrack,
                    onNext: _remoteNext,
                    onPrevious: _remotePrevious,
                    buttonDissolve: true,
                    stageBuilder: (track) => PlayerArtworkImage(
                      key: ValueKey('remote-full-cover:${track.id}'),
                      song: track,
                      radius: 0,
                      decodeWidth: 2048,
                    ),
                  ),
                ),
              if (fullCover)
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33000000),
                          Color(0x08000000),
                          Color(0x20000000),
                          Color(0xB0000000),
                        ],
                        stops: [0, .28, .63, 1],
                      ),
                    ),
                  ),
                ),
              LokalPlayerChrome(
                enabled: fullCover,
                child: SafeArea(
                  child: LayoutBuilder(
              builder: (context, bounds) {
                // The local player's panel art is almost the full available
                // content width. The former .38 * viewport-height cap made
                // the remote sleeve visibly smaller and left dead space below
                // the controls. Prefer the same near-edge-to-edge footprint,
                // shrinking only on genuinely short screens; scroll metrics
                // still protect the seek/transport/volume rows.
                final artworkSize = math.min(
                  math.min(510.0, math.max(0.0, bounds.maxWidth - 48)),
                  math.max(160.0, bounds.maxHeight - 345),
                );
                final compact = bounds.maxHeight < 700;
                // Only let the inner scroll view claim vertical swipes
                // when the laid-out player is actually taller than the safe
                // viewport. Re-measure on viewport/content dimension changes.
                return NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    _checkContentOverflow();
                    return false;
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _contentOverflows
                        ? _onCompactScroll
                        : (_) => false,
                    child: SingleChildScrollView(
                      controller: _contentScroll,
                      physics: _contentOverflows
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 510),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: lokalText('Close'),
                                onPressed: widget.onClose,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: ink, size: 30),
                              ),
                              const Spacer(),
                              Column(
                                children: [
                                  Text(
                                    lokalText('CONTROLLING DESKTOP'),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: secondary),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(remote.desktopName, style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: lokalText('Queue'),
                                onPressed: _openQueue,
                                icon: const Icon(Icons.queue_music_rounded, color: ink),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          if (fullCover && song != null)
                            SizedBox(
                              key: const ValueKey('remote-full-cover-spacer'),
                              height: artworkSize,
                            )
                          else if (song != null)
                            LokalPlayerArtwork(
                              expandedRadius: 24,
                              child: SizedBox.square(
                                dimension: artworkSize,
                                child: SongStageCarousel(
                                  key: const ValueKey('desktop-cover-carousel'),
                                  currentSong: song,
                                  nextSong: nextTrack,
                                  prevSong: previousTrack,
                                  onNext: _remoteNext,
                                  onPrevious: _remotePrevious,
                                  buttonDissolve: true,
                                  stageBuilder: (track) => PlayerArtworkImage(
                                    key: ValueKey('desktop-cover:${track.id}'),
                                    song: track,
                                    decodeWidth: 1024,
                                    radius: 24,
                                  ),
                                ),
                              ),
                            )
                          else
                            SizedBox.square(
                              dimension: artworkSize,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(color: Color(0xFF222228), borderRadius: BorderRadius.all(Radius.circular(24))),
                                child: Icon(Icons.music_note_rounded, size: 84, color: secondary),
                              ),
                            ),
                          SizedBox(height: compact ? 14 : 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              song?.title ?? lokalText('No song playing on desktop'),
                              key: const ValueKey('desktop-full-player-title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  song?.artist ?? remote.desktopName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: secondary, fontSize: 16),
                                ),
                              ),
                              if (currentTrack != null)
                                IconButton(
                                  tooltip: lokalText('Favorite'),
                                  onPressed: () => _command(() async {
                                    await ref.read(lokalRemoteControllerProvider.notifier)
                                        .toggleFavorite('desktop:${currentTrack.id}');
                                  }),
                                  icon: Icon(
                                    currentTrack.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: currentTrack.liked ? const Color(0xFFF27CA6) : ink,
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: compact ? 6 : 10),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              activeTrackColor: ink,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: ink,
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: (_seekDrag ?? player.progress).clamp(0.0, 1.0).toDouble(),
                              onChangeStart: song == null ? null : (value) => setState(() => _seekDrag = value),
                              onChanged: song == null ? null : (value) => setState(() => _seekDrag = value),
                              onChangeEnd: song == null ? null : (value) {
                                setState(() => _seekDrag = null);
                                _command(() => ref.read(playerProvider.notifier).seek(
                                  Duration(milliseconds: (value * player.duration.inMilliseconds).round()),
                                ));
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_clock(_seekDrag == null
                                  ? player.position
                                  : Duration(milliseconds: (_seekDrag! * player.duration.inMilliseconds).round())),
                                style: const TextStyle(color: secondary, fontSize: 12)),
                              Text(_clock(player.duration), style: const TextStyle(color: secondary, fontSize: 12)),
                            ],
                          ),
                          SizedBox(height: compact ? 6 : 10),
                          PlayerTransportControls(
                            playing: player.isPlaying,
                            compact: false,
                            tallerButtons: true,
                            lyricsProgress: 0,
                            accent: const Color(0xFFF0EBE9),
                            onAccent: Colors.black,
                            onPrevious: song == null ? () {} : () => _command(() => ref.read(playerProvider.notifier).previous()),
                            onNext: song == null ? () {} : () => _command(() => ref.read(playerProvider.notifier).next()),
                            onPlayPause: song == null ? () {} : () => _command(() => ref.read(playerProvider.notifier).togglePlayPause()),
                          ),
                          SizedBox(height: compact ? 4 : 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: lokalText('Shuffle'),
                                onPressed: () => _command(() => ref.read(playerProvider.notifier).toggleShuffle()),
                                icon: Icon(Icons.shuffle_rounded,
                                  color: player.isShuffle ? ink : secondary),
                              ),
                              const SizedBox(width: 24),
                              IconButton(
                                tooltip: lokalText('Lyrics'),
                                onPressed: song == null ? null : () {
                                  _closeQueue();
                                  setState(() => _showLyrics = true);
                                },
                                icon: const Icon(Icons.lyrics_outlined, color: ink),
                              ),
                              const SizedBox(width: 24),
                              IconButton(
                                tooltip: lokalText('Repeat'),
                                onPressed: () {
                                  if (remote.controlsDesktop) ref.read(playerProvider.notifier).toggleLoopMode();
                                },
                                icon: Icon(
                                  player.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                  color: player.loopMode != LoopMode.off ? ink : secondary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 3 : 8),
                          Row(
                            children: [
                              const Icon(Icons.volume_down_rounded, color: secondary),
                              Expanded(
                                child: Slider(
                                  value: (_volumeDrag ?? remote.snapshot?.volume ?? 0.8).clamp(0.0, 1.0).toDouble(),
                                  activeColor: ink,
                                  inactiveColor: Colors.white24,
                                  onChanged: (v) => setState(() => _volumeDrag = v),
                                  onChangeEnd: (v) {
                                    setState(() => _volumeDrag = null);
                                    _command(() => ref.read(playerProvider.notifier).setVolume(v));
                                  },
                                ),
                              ),
                              const Icon(Icons.volume_up_rounded, color: secondary),
                            ],
                          ),
                          SizedBox(height: compact ? 2 : 8),
                        ],
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
            ],
          ),
        ),
      ),
    );
  }
}
