import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/player/widgets/synced_lyrics_view.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/online_lyrics_service.dart';
import 'package:flick/services/player_service.dart';

/// Desktop remote lyrics: online lookup for the *desktop* song, not the
/// Android audio engine's previous local song. The same synchronized renderer
/// follows the remote clock and dispatches seeks to the remote transport.
class DesktopRemoteLyricsPanel extends ConsumerStatefulWidget {
  const DesktopRemoteLyricsPanel({
    super.key,
    required this.song,
    required this.onClose,
    this.fullPlayerTypography = false,
  });

  final Song song;
  final VoidCallback onClose;
  final bool fullPlayerTypography;

  @override
  ConsumerState<DesktopRemoteLyricsPanel> createState() =>
      _DesktopRemoteLyricsPanelState();
}

class _DesktopRemoteLyricsPanelState
    extends ConsumerState<DesktopRemoteLyricsPanel> {
  final LyricsService _service = LyricsService();
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  LyricsData? _lyrics;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final state = ref.read(playerProvider);
    _position.value = state.position;
    _playing.value = state.isPlaying;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant DesktopRemoteLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _position.value = ref.read(playerProvider).position;
      unawaited(_load());
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final request = ++_request;
    if (mounted) {
      setState(() {
        _loading = true;
        _lyrics = null;
      });
    }
    try {
      if (refresh) OnlineLyricsService.clearLookupCache();
      // Do not ask the Android file decoder to open a Windows/Linux song
      // path. Resolve the exact desktop track via Lokal's lyrics sources.
      final data = await _service.fetchOnlineLyrics(
        widget.song,
        stillCurrent: () => mounted && request == _request,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _lyrics = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_request;
    _position.dispose();
    _playing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playerProvider, (previous, next) {
      if (next.currentSong?.id != widget.song.id) return;
      _position.value = next.position;
      _playing.value = next.isPlaying;
    });
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                tooltip: lokalText('Back to player'),
                onPressed: widget.onClose,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                lokalText('Lyrics'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: lokalText('Refresh lyrics'),
                onPressed: () => unawaited(_load(refresh: true)),
                icon: const Icon(Icons.refresh, color: Colors.white70),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _lyrics == null || _lyrics!.lines.isEmpty
              ? Center(
                  child: Text(
                    lokalText('No lyrics available for this song'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                )
              : _lyrics!.isSynchronized
              ? SyncedLyricsView(
                  fullPlayerTypography: widget.fullPlayerTypography,
                  key: ValueKey('desktop-lyrics:${widget.song.id}'),
                  playerService: PlayerService(),
                  lyricsService: _service,
                  lyrics: _lyrics!,
                  positionNotifier: _position,
                  playingNotifier: _playing,
                  onSeek: (position) =>
                      ref.read(playerProvider.notifier).seek(position),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 80),
                  children: [
                    for (final line in _lyrics!.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          line.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
