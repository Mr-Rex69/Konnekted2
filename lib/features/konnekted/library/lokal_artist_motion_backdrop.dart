import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:flick/services/player_service.dart';
import 'package:flick/services/motion_art/motion_art_memory_pressure.dart';

/// A silent editorial HLS clip above an always-available static portrait.
///
/// Uses a separate decoder only on an active artist page. Respect reduced
/// motion and bit-perfect output suppression; it must not grab audio focus.
class LokalArtistMotionBackdrop extends StatelessWidget {
  const LokalArtistMotionBackdrop({
    super.key,
    required this.url,
    required this.fallback,
    required this.playbackActive,
    this.enabled = true,
  });

  final String url;
  final Widget fallback;
  final bool playbackActive;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: PlayerService().motionArtSuppressedNotifier,
    builder: (context, suppressed, _) {
      if (!enabled || suppressed || MediaQuery.disableAnimationsOf(context)) {
        return fallback;
      }
      return ValueListenableBuilder<bool>(
        valueListenable: MotionArtMemoryPressure.instance.suspended,
        builder: (context, suspendedForMemory, _) {
          if (suspendedForMemory) return fallback;
          return _ArtistVideoLayer(
            url: url,
            fallback: fallback,
            playbackActive: playbackActive,
          );
        },
      );
    },
  );
}

class _ArtistVideoLayer extends StatefulWidget {
  const _ArtistVideoLayer({
    required this.url,
    required this.fallback,
    required this.playbackActive,
  });
  final String url;
  final Widget fallback;
  final bool playbackActive;

  @override
  State<_ArtistVideoLayer> createState() => _ArtistVideoLayerState();
}

class _ArtistVideoLayerState extends State<_ArtistVideoLayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _visible = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _ArtistVideoLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      final previous = _controller;
      _controller = null;
      _ready = false;
      _visible = false;
      if (previous != null) unawaited(previous.dispose());
      unawaited(_load());
    } else if (oldWidget.playbackActive != widget.playbackActive) {
      unawaited(_syncPlayback());
    }
  }

  Future<void> _load() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    final controller = VideoPlayerController.networkUrl(
      uri,
      formatHint: VideoFormat.hls,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted || !identical(_controller, controller)) return;
      setState(() => _ready = true);
      await _syncPlayback();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_controller, controller)) {
          setState(() => _visible = true);
        }
      });
    } catch (_) {
      // A missing or unsupported Apple rendition must never hide the photo.
      if (identical(_controller, controller)) _controller = null;
      unawaited(controller.dispose());
    }
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (_foreground && widget.playbackActive) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {
      // Video playback is decorative, not required for navigation.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_syncPlayback());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = controller?.value.size;
    final hasFrame = _ready &&
        size != null &&
        size.width > 0 &&
        size.height > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.fallback,
        if (hasFrame)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 280),
            opacity: _visible ? 1 : 0,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: VideoPlayer(controller!),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
