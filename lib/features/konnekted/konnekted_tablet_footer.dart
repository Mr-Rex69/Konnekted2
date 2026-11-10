import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/link/lokal_devices_card.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/features/player/widgets/sleep_timer_bottom_sheet.dart';
import 'package:flick/features/player/widgets/speed_bottom_sheet.dart';
import 'package:flick/features/player/widgets/pitch_bottom_sheet.dart';
import 'package:flick/features/settings/screens/equalizer_screen.dart';
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

/// Desktop composition: track identity, centered transport/timeline and
/// utilities. No glass capsule and no scrolling-dependent collapse.
class KonnektedTabletFooter extends ConsumerWidget {
  const KonnektedTabletFooter({
    super.key,
    required this.onOpenPlayer,
    required this.onOpenPanel,
    this.artworkKey,
  });
  final VoidCallback onOpenPlayer;
  final ValueChanged<TabletPlayerTab> onOpenPanel;
  final Key? artworkKey;

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
    final identity = Row(
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
              dimension: 48,
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: t.muted),
                ),
              ],
            ),
          ),
        ),
        TabletLikeButton(playback: playback),
      ],
    );
    Widget transport({bool compact = false}) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          IconButton(
            tooltip: lokalText(flags.$2 ? 'Shuffle on' : 'Shuffle off'),
            onPressed: playback.isRadio
                ? null
                : () => unawaited(command(player.toggleShuffle)),
            icon: Icon(
              Icons.shuffle_rounded,
              size: 18,
              color: flags.$2 && !playback.isRadio ? t.accent : t.muted,
            ),
          ),
        IconButton(
          tooltip: lokalText('Previous'),
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: () => unawaited(
            command(
              playback.isRadio
                  ? ref.read(radioPlayerProvider.notifier).previousStation
                  : player.previous,
            ),
          ),
        ),
        IconButton.filled(
          tooltip: playing ? l10n.pause : l10n.play,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: () => unawaited(
            command(
              playback.isRadio
                  ? ref.read(radioPlayerProvider.notifier).toggle
                  : player.togglePlayPause,
            ),
          ),
        ),
        IconButton(
          tooltip: lokalText('Next'),
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: () => unawaited(
            command(
              playback.isRadio
                  ? ref.read(radioPlayerProvider.notifier).nextStation
                  : player.next,
            ),
          ),
        ),
        if (!compact)
          IconButton(
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
          ),
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
    final utilities = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.lyrics,
          icon: const Icon(Icons.lyrics_outlined, size: 20),
          onPressed: () => onOpenPanel(TabletPlayerTab.lyrics),
        ),
        IconButton(
          tooltip: l10n.queue,
          icon: const Icon(Icons.queue_music_rounded, size: 20),
          onPressed: () => onOpenPanel(TabletPlayerTab.queue),
        ),
        IconButton(
          tooltip: lokalText('Now playing'),
          icon: const Icon(Icons.view_sidebar_outlined, size: 20),
          onPressed: () => onOpenPanel(TabletPlayerTab.details),
        ),
        IconButton(
          tooltip: lokalText('Full screen'),
          onPressed: onOpenPlayer,
          icon: const Icon(Icons.open_in_full_rounded, size: 19),
        ),
        IconButton(
          tooltip: lokalText('Output'),
          icon: const Icon(Icons.speaker_rounded, size: 19),
          onPressed: () {
            if (playback.remote) {
              unawaited(
                Navigator.of(context, rootNavigator: true).push(
                  LokalPageRoute<void>(
                    builder: (_) => const LokalDesktopLinkScreen(),
                  ),
                ),
              );
            } else if (Platform.isAndroid) {
              unawaited(openAndroidOutputChooser(context));
            } else {
              unawaited(
                Navigator.of(context, rootNavigator: true).push(
                  lokalSettingsRoute(context, group: LokalSettingsGroup.output),
                ),
              );
            }
          },
        ),
        PopupMenuButton<String>(
          tooltip: lokalText('Playback options'),
          icon: const Icon(Icons.more_horiz_rounded, size: 20),
          onSelected: (action) {
            final service = ref.read(playerServiceProvider);
            switch (action) {
              case 'fullscreen':
                onOpenPlayer();
              case 'sleep':
                unawaited(SleepTimerBottomSheet.show(context, service));
              case 'speed':
                unawaited(SpeedBottomSheet.show(context, service));
              case 'pitch':
                unawaited(PitchBottomSheet.show(context, service));
              case 'eq':
                unawaited(
                  Navigator.of(context, rootNavigator: true).push(
                    LokalPageRoute<void>(
                      builder: (_) => const EqualizerScreen(),
                    ),
                  ),
                );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'fullscreen',
              child: Text(lokalText('Full screen')),
            ),
            if (!playback.isRadio && !playback.remote) ...[
              PopupMenuItem(value: 'sleep', child: Text(l10n.sleepTimer)),
              PopupMenuItem(value: 'speed', child: Text(l10n.speedUp)),
              PopupMenuItem(value: 'pitch', child: Text(l10n.pitch)),
              PopupMenuItem(value: 'eq', child: Text(l10n.equalizer)),
            ],
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1100;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 3, child: identity),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [transport(), timeline],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          utilities,
                          SizedBox(
                            width: 220,
                            child: TabletVolumeControl(playback: playback),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 12),
                        transport(),
                      ],
                    ),
                    timeline,
                    Row(
                      children: [
                        SizedBox(
                          width: 200,
                          child: TabletVolumeControl(playback: playback),
                        ),
                        if (playback.remote)
                          const Expanded(child: LokalOutputPill())
                        else
                          const Spacer(),
                        utilities,
                      ],
                    ),
                  ],
                ),
        );
      },
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
