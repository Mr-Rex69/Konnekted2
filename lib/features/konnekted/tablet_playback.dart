import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/internet_radio/station_favorites.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';

/// Presentation snapshot only. Desktop control takes precedence over stale
/// local/radio state, just as it does in the full player.
class TabletPlayback {
  const TabletPlayback({required this.song, required this.remote, this.radio});
  final Song? song;
  final bool remote;
  final RadioPlayback? radio;
  bool get isRadio => radio?.station != null;

  /// A station remains one queue item while its current recording changes.
  /// Lyrics caches and renderers need the recording identity, not station ID.
  Song? get lyricsSong {
    final current = song;
    if (!isRadio || current == null) return current;
    final metadata = radio?.trackMetadata;
    if (metadata?.title.trim().isNotEmpty != true ||
        metadata?.artist.trim().isNotEmpty != true) {
      return null;
    }
    return current.copyWith(
      id: '${current.id}:${metadata!.artist}|${metadata.title}',
    );
  }

  static TabletPlayback watch(WidgetRef ref) {
    final remote = ref.watch(
      lokalRemoteControllerProvider.select((s) => s.controlsDesktop),
    );
    final radio = remote ? null : ref.watch(radioPlayerProvider);
    return _snapshot(ref.watch(currentSongProvider), remote, radio);
  }

  static TabletPlayback read(WidgetRef ref) {
    final remote = ref.read(lokalRemoteControllerProvider).controlsDesktop;
    return _snapshot(
      ref.read(currentSongProvider),
      remote,
      remote ? null : ref.read(radioPlayerProvider),
    );
  }

  static TabletPlayback _snapshot(
    Song? current,
    bool remote,
    RadioPlayback? radio,
  ) {
    final station = radio?.station;
    if (station == null) return TabletPlayback(song: current, remote: remote);
    final metadata = radio?.trackMetadata;
    return TabletPlayback(
      remote: false,
      radio: radio,
      song: Song(
        id: 'radio:${station.id}',
        title: metadata?.title.isNotEmpty == true
            ? metadata!.title
            : radio?.nowPlaying ?? station.title,
        artist: metadata?.artist.isNotEmpty == true
            ? metadata!.artist
            : station.title,
        albumArt: metadata?.cover ?? station.icon,
        duration: Duration.zero,
        fileType: station.codec,
        sourceDisplayName: station.title,
      ),
    );
  }
}

enum TabletPlayerTab { details, lyrics, queue }

enum TabletCoverCard { details, lyrics }

String tabletTime(Duration time) {
  final seconds = time.inSeconds.clamp(0, 999999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Future<void> tabletPlaybackAction(
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

class TabletLikeButton extends ConsumerStatefulWidget {
  const TabletLikeButton({super.key, required this.playback, this.onLiked});
  final TabletPlayback playback;
  final VoidCallback? onLiked;
  @override
  ConsumerState<TabletLikeButton> createState() => _TabletLikeButtonState();
}

class _TabletLikeButtonState extends ConsumerState<TabletLikeButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final song = widget.playback.song;
    if (song == null) return const SizedBox.shrink();
    final station = widget.playback.radio?.station;
    final liked = station != null
        ? ref.watch(stationFavoritesProvider).containsKey(station.id)
        : ref.watch(favoritesProvider).value?.isFavorite(song.id) == true;
    return IconButton(
      key: const ValueKey('tablet-like'),
      tooltip: lokalText(liked ? 'Unlike' : 'Like'),
      isSelected: liked,
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                if (station != null) {
                  await ref
                      .read(stationFavoritesProvider.notifier)
                      .toggle(station);
                } else {
                  await ref
                      .read(favoritesProvider.notifier)
                      .toggleFavorite(song.id, song: song);
                }
                if (mounted && !liked && widget.playback.song?.id == song.id) {
                  widget.onLiked?.call();
                }
              } catch (_) {
                if (context.mounted) {
                  LokalToast.show(
                    context,
                    lokalText('Could not update this song’s like.'),
                  );
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? context.lokal.accent : context.lokal.muted,
        size: 20,
      ),
    );
  }
}

/// Playback updates cannot move the thumb while a finger is dragging. The
/// native/remote seek is committed once, on release.
class TabletSeekBar extends StatefulWidget {
  const TabletSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.buffering = false,
  });
  final Duration position, duration;
  final Future<void> Function(Duration) onSeek;
  final bool buffering;
  @override
  State<TabletSeekBar> createState() => _TabletSeekBarState();
}

class _TabletSeekBarState extends State<TabletSeekBar> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final duration = widget.duration.inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (widget.position.inMilliseconds / duration).clamp(0.0, 1.0);
    final shown = Duration(
      milliseconds: ((_drag ?? progress) * duration).round(),
    );
    return Row(
      children: [
        Text(
          tabletTime(shown),
          style: TextStyle(fontSize: 10, color: context.lokal.muted),
        ),
        Expanded(
          child: SizedBox(
            height: 24,
            child: Slider(
              key: const ValueKey('tablet-seek'),
              value: _drag ?? progress,
              onChanged: duration <= 0
                  ? null
                  : (value) => setState(() => _drag = value),
              onChangeEnd: duration <= 0
                  ? null
                  : (value) async {
                      await widget.onSeek(
                        Duration(milliseconds: (value * duration).round()),
                      );
                      if (mounted) setState(() => _drag = null);
                    },
              semanticFormatterCallback: (value) => tabletTime(
                Duration(milliseconds: (value * duration).round()),
              ),
            ),
          ),
        ),
        if (widget.buffering)
          const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        else
          Text(
            tabletTime(widget.duration),
            style: TextStyle(fontSize: 10, color: context.lokal.muted),
          ),
      ],
    );
  }
}
