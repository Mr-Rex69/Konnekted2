import 'dart:async';

import 'full_player_seek_bar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/models/song.dart';
import 'package:flick/models/progress_bar_style.dart';
import 'package:flick/features/player/widgets/line_seek_bar.dart';
import 'package:flick/features/player/widgets/waveform_seek_bar.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/providers/full_player_waveform_provider.dart';

class WaveformLayer extends StatefulWidget {
  final PlayerService playerService;
  final ValueNotifier<Duration> positionNotifier;
  final Song? currentSong;
  final ProgressBarStyle? styleOverride;
  final bool targetStyle;

  const WaveformLayer({
    super.key,
    required this.playerService,
    required this.positionNotifier,
    required this.currentSong,
    this.styleOverride,
    this.targetStyle = false,
  });

  @override
  State<WaveformLayer> createState() => _WaveformLayerState();
}

class _WaveformLayerState extends State<WaveformLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _appearController;
  late final Animation<double> _appearAnimation;
  String? _lastSongId;

  @override
  void initState() {
    super.initState();
    _lastSongId = widget.currentSong?.id;
    _appearController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _appearAnimation = CurvedAnimation(
      parent: _appearController,
      curve: Curves.easeOutCubic,
    );
    _appearController.forward();
  }

  @override
  void didUpdateWidget(covariant WaveformLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSong?.id != _lastSongId) {
      _lastSongId = widget.currentSong?.id;
      _appearController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _appearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final ProgressBarStyle style =
            widget.styleOverride ?? ref.watch(progressBarStyleProvider);
        final song = widget.currentSong;
        final peaks = style == ProgressBarStyle.waveform && song != null
            ? ref.watch(fullPlayerWaveformProvider(song)).asData?.value
            : null;
        return AnimatedBuilder(
          animation: _appearAnimation,
          builder: (context, _) {
            final t = _appearAnimation.value;
            return ValueListenableBuilder<Duration>(
              valueListenable: widget.playerService.durationNotifier,
              builder: (context, engineDuration, _) {
                final duration = engineDuration.inMilliseconds > 0
                    ? engineDuration
                    : (widget.currentSong?.duration ?? Duration.zero);

                if (duration.inMilliseconds == 0) {
                  return const SizedBox();
                }

                return ValueListenableBuilder<Duration>(
                  valueListenable: widget.positionNotifier,
                  builder: (context, position, _) {
                    final songId = widget.currentSong?.id;
                    final seekBar = switch (style) {
                      ProgressBarStyle.wavy => _WavyLayerSeekBar(
                        key: ValueKey(widget.currentSong?.id),
                        value:
                            (position.inMilliseconds / duration.inMilliseconds)
                                .clamp(0.0, 1.0),
                        onSeek: (value) {
                          if (!mounted || widget.currentSong?.id != songId) {
                            return;
                          }
                          final target = Duration(
                            milliseconds: (value * duration.inMilliseconds)
                                .round(),
                          );
                          widget.positionNotifier.value = target;
                          unawaited(widget.playerService.seek(target));
                        },
                      ),
                      ProgressBarStyle.line => LineSeekBar(
                        position: position,
                        duration: duration,
                        appearProgress: t,
                        onChanged: (newPos) {
                          widget.positionNotifier.value = newPos;
                          unawaited(widget.playerService.seek(newPos));
                        },
                        targetStyle: widget.targetStyle,
                      ),
                      ProgressBarStyle.waveform => WaveformSeekBar(
                        key: ValueKey(widget.currentSong?.id),
                        barCount: 60,
                        position: position,
                        duration: duration,
                        appearProgress: t,
                        cachedPeaks: peaks,
                        onChanged: (newPos) {
                          if (!mounted || widget.currentSong?.id != songId)
                            return;
                          widget.positionNotifier.value = newPos;
                          unawaited(widget.playerService.seek(newPos));
                        },
                      ),
                    };
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RepaintBoundary(child: seekBar),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Extracted player controls widget to reduce nesting and improve performance

/// Drag state belongs to the keyed Wavy subtree. Changing song or style
/// disposes its gesture and preview together, so neither can affect a new track.
class _WavyLayerSeekBar extends StatefulWidget {
  const _WavyLayerSeekBar({
    super.key,
    required this.value,
    required this.onSeek,
  });
  final double value;
  final ValueChanged<double> onSeek;
  @override
  State<_WavyLayerSeekBar> createState() => _WavyLayerSeekBarState();
}

class _WavyLayerSeekBarState extends State<_WavyLayerSeekBar> {
  double? _drag;
  @override
  Widget build(BuildContext context) => FullPlayerSeekBar(
    style: ProgressBarStyle.wavy,
    value: _drag ?? widget.value,
    onChangeStart: (value) => setState(() => _drag = value),
    onChanged: (value) => setState(() => _drag = value),
    onChangeEnd: (value) {
      setState(() => _drag = null);
      widget.onSeek(value);
    },
  );
}
