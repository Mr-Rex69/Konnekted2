import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'konnekted_dock_glass.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/link/lokal_devices_card.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/features/player/widgets/android_output_chooser.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/features/link/lokal_desktop_link_screen.dart';
import 'package:flick/services/player_volume_control.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';

import 'tablet_playback.dart';

Widget _foldControl(Widget child, double progress, {bool reverse = false}) {
  final visible = reverse ? progress : 1 - progress;
  return ClipRect(
    child: Align(
      widthFactor: visible,
      heightFactor: 1,
      child: ExcludeSemantics(
        excluding: visible < .5,
        child: IgnorePointer(
          ignoring: visible < .5,
          child: Opacity(opacity: visible, child: child),
        ),
      ),
    ),
  );
}

/// A floating glass player that folds into one compact row while browsing.
class KonnektedTabletFooter extends ConsumerWidget {
  const KonnektedTabletFooter({
    super.key,
    required this.onOpenPlayer,
    required this.onOpenPanel,
    this.artworkKey,
    this.collapsed = false,
    this.onExpand,
  });
  final VoidCallback onOpenPlayer;
  final ValueChanged<TabletPlayerTab> onOpenPanel;
  final Key? artworkKey;
  final bool collapsed;
  final VoidCallback? onExpand;

  static const compactBreakpoint = 600.0;
  static const expandedHeight = 80.0;
  static const collapsedHeight = 56.0;
  static double reservedHeight({
    required bool collapsed,
    double systemInset = 0,
  }) =>
      (collapsed ? collapsedHeight : expandedHeight) +
      math.max(12, systemInset) +
      8;

  void _openOutput(BuildContext context, TabletPlayback playback) {
    if (playback.remote) {
      unawaited(
        Navigator.of(context, rootNavigator: true).push(
          LokalPageRoute<void>(builder: (_) => const LokalDesktopLinkScreen()),
        ),
      );
    } else if (Platform.isAndroid) {
      unawaited(openAndroidOutputChooser(context));
    } else {
      unawaited(
        Navigator.of(
          context,
          rootNavigator: true,
        ).push(lokalSettingsRoute(context, group: LokalSettingsGroup.output)),
      );
    }
  }

  void _openVolume(BuildContext context, TabletPlayback playback) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(lokalText('Volume')),
                TabletVolumeControl(playback: playback),
                if (playback.remote) const LokalOutputPill(),
                ListTile(
                  leading: const Icon(Icons.speaker_rounded),
                  title: Text(lokalText('Output')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openOutput(context, playback);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = TabletPlayback.watch(ref);
    final song = playback.song;
    if (song == null) return const SizedBox.shrink();
    final t = context.lokal;
    final player = ref.read(playerProvider.notifier);
    final flags = ref.watch(
      playerProvider.select((s) => (s.isPlaying, s.isShuffle, s.loopMode)),
    );
    final playing = playback.isRadio ? playback.radio!.playing : flags.$1;
    Future<void> command(Future<void> Function() action) =>
        tabletPlaybackAction(context, action);
    Widget identity(double progress, bool wide) => Row(
      children: [
        InkWell(
          onTap: onOpenPlayer,
          borderRadius: BorderRadius.circular(8),
          child: Hero(
            tag: 'konnekted-player-art',
            createRectTween: (begin, end) =>
                LokalArtworkRectTween(begin: begin, end: end),
            child: SizedBox.square(
              key: artworkKey,
              dimension: lerpDouble(56, 40, progress)!,
              child: PlayerArtworkImage(
                song: song,
                radius: 8,
                decodeWidth: 160,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onOpenPlayer,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                    shadows: [
                      Shadow(color: t.bg.withValues(alpha: .8), blurRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: t.text.withValues(alpha: .85),
                    shadows: [
                      Shadow(color: t.bg.withValues(alpha: .8), blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (wide) _foldControl(TabletLikeButton(playback: playback), progress),
      ],
    );
    final playButton = IconButton.filled(
      tooltip: playing ? l10n.pause : l10n.play,
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      onPressed: () => unawaited(
        command(
          playback.isRadio
              ? ref.read(radioPlayerProvider.notifier).toggle
              : player.togglePlayPause,
        ),
      ),
    );
    final nextButton = IconButton(
      tooltip: lokalText('Next'),
      icon: const Icon(Icons.skip_next_rounded),
      onPressed: () => unawaited(
        command(
          playback.isRadio
              ? ref.read(radioPlayerProvider.notifier).nextStation
              : player.next,
        ),
      ),
    );
    final previousButton = IconButton(
      tooltip: lokalText('Previous'),
      icon: const Icon(Icons.skip_previous_rounded),
      onPressed: () => unawaited(
        command(
          playback.isRadio
              ? ref.read(radioPlayerProvider.notifier).previousStation
              : player.previous,
        ),
      ),
    );
    final shuffleButton = IconButton(
      tooltip: lokalText(flags.$2 ? 'Shuffle on' : 'Shuffle off'),
      onPressed: playback.isRadio
          ? null
          : () => unawaited(command(player.toggleShuffle)),
      icon: Icon(
        Icons.shuffle_rounded,
        size: 18,
        color: flags.$2 && !playback.isRadio ? t.accent : t.muted,
      ),
    );
    final repeatButton = IconButton(
      tooltip: lokalText(
        flags.$3 == LoopMode.off
            ? 'Repeat off'
            : flags.$3 == LoopMode.one
            ? 'Repeat one'
            : 'Repeat all',
      ),
      onPressed: playback.isRadio ? null : player.toggleLoopMode,
      icon: Icon(
        flags.$3 == LoopMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        size: 18,
        color: flags.$3 != LoopMode.off && !playback.isRadio
            ? t.accent
            : t.muted,
      ),
    );
    Widget transport() => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        shuffleButton,
        previousButton,
        playButton,
        nextButton,
        repeatButton,
      ],
    );
    final timeline = playback.isRadio
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: t.accent),
                const SizedBox(width: 8),
                Text(
                  lokalText('LIVE'),
                  style: TextStyle(
                    color: t.accent,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Divider(color: t.border)),
                const SizedBox(width: 12),
                Text(
                  playback.radio!.loading
                      ? lokalText('Connecting')
                      : playback.radio!.error != null
                      ? lokalText('Stream error')
                      : playing
                      ? lokalText('On air')
                      : l10n.pause,
                  style: TextStyle(fontSize: 10, color: t.muted),
                ),
              ],
            ),
          )
        : Consumer(
            builder: (context, ref, _) => TabletSeekBar(
              key: ValueKey('tablet-seek:${song.id}'),
              position: ref.watch(positionProvider),
              duration: ref.watch(durationProvider),
              buffering: ref.watch(playerProvider.select((s) => s.isBuffering)),
              onSeek: (position) => command(
                () => ref.read(playerProvider.notifier).seek(position),
              ),
            ),
          );
    final fullscreenButton = IconButton(
      tooltip: lokalText('Full screen'),
      icon: const Icon(Icons.fullscreen_rounded, size: 20),
      onPressed: onOpenPlayer,
    );
    Widget utilities(
      bool wide,
      double progress, {
      bool showPanelButton = true,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (wide) ...[
          _foldControl(
            IconButton(
              tooltip: l10n.lyrics,
              icon: const Icon(Icons.lyrics_outlined, size: 20),
              onPressed: () => onOpenPanel(TabletPlayerTab.lyrics),
            ),
            progress,
          ),
          _foldControl(
            IconButton(
              tooltip: l10n.queue,
              icon: const Icon(Icons.queue_music_rounded, size: 20),
              onPressed: () => onOpenPanel(TabletPlayerTab.queue),
            ),
            progress,
          ),
        ],
        if (showPanelButton)
          IconButton(
            tooltip: lokalText('Now playing'),
            icon: const Icon(Icons.view_sidebar_outlined, size: 20),
            onPressed: () => onOpenPanel(TabletPlayerTab.details),
          ),
        if (wide)
          _foldControl(
            IconButton(
              tooltip: lokalText('Volume'),
              icon: const Icon(Icons.volume_up_rounded, size: 20),
              onPressed: () => _openVolume(context, playback),
            ),
            progress,
          ),
        fullscreenButton,
      ],
    );
    final footer = LayoutBuilder(
      builder: (context, bounds) => TweenAnimationBuilder<double>(
        tween: Tween(
          end: collapsed || bounds.maxWidth < compactBreakpoint ? 1 : 0,
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        builder: (context, progress, _) {
          final width = lerpDouble(
            math.min(bounds.maxWidth, 1200),
            math.min(bounds.maxWidth, 760),
            progress,
          )!;
          final folded = progress >= .5;
          final wide = bounds.maxWidth >= 1000;
          final timelineHeight = 24 * (1 - progress);
          final micro = bounds.maxWidth < 440;
          // Equal side lanes keep Play and the timeline at the pill's centre,
          // including when either sidebar changes the available pane width.
          // The centre grows only after allowing readable identity/action lanes.
          final centreWidth = math.min(
            448.0,
            // 16 dp outer padding, 8 dp gaps, and a 200 dp target per side.
            math.max(220.0, width - 2 * 16 - 2 * 8 - 2 * 200),
          );
          return Center(
            heightFactor: 1,
            child: SizedBox(
              width: width,
              height: micro
                  ? collapsedHeight
                  : lerpDouble(expandedHeight, collapsedHeight, progress),
              child: konnektedDockGlass(
                context,
                key: const ValueKey('tablet-footer-glass'),
                progress: progress,
                child: Material(
                  type: MaterialType.transparency,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(44, 44),
                          maximumSize: const Size(44, 44),
                          padding: const EdgeInsets.all(8),
                          visualDensity: VisualDensity.standard,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: micro ? 8 : 16,
                          vertical: 6,
                        ),
                        child: micro
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  if (bounds.maxWidth >= 308) shuffleButton,
                                  if (bounds.maxWidth >= 220) previousButton,
                                  playButton,
                                  if (bounds.maxWidth >= 220) nextButton,
                                  if (bounds.maxWidth >= 308) repeatButton,
                                  if (bounds.maxWidth >= 112) fullscreenButton,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: identity(progress, wide)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: centreWidth,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        transport(),
                                        SizedBox(
                                          height: timelineHeight,
                                          child: ClipRect(
                                            child: OverflowBox(
                                              alignment: Alignment.topCenter,
                                              minHeight: 24,
                                              maxHeight: 24,
                                              child: ExcludeSemantics(
                                                excluding: folded,
                                                child: IgnorePointer(
                                                  ignoring: folded,
                                                  child: Opacity(
                                                    opacity: 1 - progress,
                                                    child: Center(
                                                      child: ConstrainedBox(
                                                        // Match desktop's max-w-md
                                                        // timeline, including labels.
                                                        constraints:
                                                            const BoxConstraints(
                                                              maxWidth: 448,
                                                            ),
                                                        child: timeline,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: utilities(
                                        wide,
                                        progress,
                                        showPanelButton: width >= 448,
                                      ),
                                    ),
                                  ),
                                ],
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
    );
    return GestureDetector(
      onVerticalDragUpdate: collapsed && onExpand != null
          ? (details) {
              if (details.delta.dy > 0) onExpand!();
            }
          : null,
      child: footer,
    );
  }
}

/// Route-aware local volume; remote and live radio keep their own transport.
/// Creating this control must never mirror system gain into exclusive USB.
class TabletVolumeControl extends ConsumerStatefulWidget {
  const TabletVolumeControl({super.key, required this.playback});
  final TabletPlayback playback;
  @override
  ConsumerState<TabletVolumeControl> createState() =>
      _TabletVolumeControlState();
}

class _TabletVolumeControlState extends ConsumerState<TabletVolumeControl> {
  PlayerVolumeControl? _local;
  double _beforeMute = .5;
  @override
  void dispose() {
    _local?.dispose();
    super.dispose();
  }

  Widget _slider(
    BuildContext context,
    double value,
    double max,
    bool available,
    Future<void> Function(double) set,
  ) => Row(
    children: [
      IconButton(
        tooltip: lokalText(value > 0 ? 'Mute' : 'Unmute'),
        icon: Icon(
          value > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          size: 18,
        ),
        onPressed: !available
            ? null
            : () {
                if (value > 0) _beforeMute = value;
                unawaited(
                  tabletPlaybackAction(
                    context,
                    () => set(value > 0 ? 0 : _beforeMute.clamp(0, max)),
                  ),
                );
              },
      ),
      Expanded(
        child: Slider(
          key: const ValueKey('tablet-volume'),
          value: value.clamp(0, max),
          max: max,
          onChanged: !available
              ? null
              : (value) =>
                    unawaited(tabletPlaybackAction(context, () => set(value))),
          semanticFormatterCallback: (value) =>
              '${(value / max * 100).round()}%',
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.playback.remote) {
      final volume = ref.watch(
        lokalRemoteControllerProvider.select((s) => s.snapshot?.volume ?? 0),
      );
      return _slider(
        context,
        volume,
        1,
        true,
        ref.read(playerProvider.notifier).setVolume,
      );
    }
    if (widget.playback.isRadio) {
      final radio = ref.read(radioPlayerProvider.notifier);
      return ValueListenableBuilder<double>(
        valueListenable: radio.volume,
        builder: (context, volume, _) =>
            _slider(context, volume, 1, true, radio.setVolume),
      );
    }
    final control = _local ??= PlayerVolumeControl(
      ref.read(playerServiceProvider),
    );
    return ListenableBuilder(
      listenable: control,
      builder: (context, _) => _slider(
        context,
        control.value,
        control.max,
        control.available,
        control.set,
      ),
    );
  }
}
