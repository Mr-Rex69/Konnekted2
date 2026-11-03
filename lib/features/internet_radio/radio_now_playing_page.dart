import 'dart:async';
import 'dart:math' as math;

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/features/internet_radio/internet_radio_page.dart';
import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/internet_radio/station_favorites.dart';
import 'package:flick/features/player/widgets/artwork_gradient_backdrop.dart';
import 'package:flick/features/player/widgets/android_output_chooser.dart';
import 'package:flick/features/player/widgets/full_player_visuals.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';
import 'package:flick/features/player/widgets/song_stage_carousel.dart';
import 'package:flick/features/search/screens/search_screen.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flick/widgets/lokal/lokal_pull_to_dismiss.dart';
import 'package:flick/widgets/lokal/lokal_queue_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The live-radio transport shares FullPlayerScreen's player route, artwork
/// morph, dismissal spring and appearance settings with local/remote playback.
class RadioNowPlayingPage extends ConsumerStatefulWidget {
  const RadioNowPlayingPage({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  ConsumerState<RadioNowPlayingPage> createState() =>
      _RadioNowPlayingPageState();
}

class _RadioNowPlayingPageState extends ConsumerState<RadioNowPlayingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _queueController = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 350),
  );
  late final LokalQueueRevealMotion _queue = LokalQueueRevealMotion(
    _queueController,
  );

  @override
  void initState() {
    super.initState();
    _queue.addListener(_queueChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !ref.read(radioPlayerProvider.notifier)
              .consumeStationQueueRequest()) return;
      // An explicit queue tap should reveal the queue after the normal
      // mini→full spring settles, not compete with the artwork morph.
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null ||
          animation.status == AnimationStatus.completed) {
        _setQueueOpen(true);
        return;
      }
      late AnimationStatusListener listener;
      listener = (status) {
        if (status != AnimationStatus.completed &&
            status != AnimationStatus.dismissed) return;
        animation.removeStatusListener(listener);
        if (mounted && status == AnimationStatus.completed) {
          _setQueueOpen(true);
        }
      };
      animation.addStatusListener(listener);
    });
  }

  void _queueChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _queue.removeListener(_queueChanged);
    _queue.dispose();
    _queueController.dispose();
    super.dispose();
  }

  void _setQueueOpen(bool open) => _queue.setOpen(
    open, animate: !MediaQuery.disableAnimationsOf(context),
  );

  void _find(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    // Search returns to the live player. The radio session remains active.
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => SearchScreen(initialQuery: query),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 190),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  void _copy(String value) {
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _shareStation(RadioStation station) async {
    await SharePlus.instance.share(ShareParams(
      text: station.title + '\n' + station.url,
      subject: station.title + ' · Stations',
    ));
  }

  void _showMore(RadioStation station, String? artist, String? title) {
    final artistName = artist?.trim() ?? '';
    final songName = title?.trim() ?? '';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF232227),
      builder: (sheetContext) {
        void execute(VoidCallback action) {
          Navigator.pop(sheetContext);
          action();
        }
        return Theme(
          data: ThemeData.dark(useMaterial3: true),
          child: SafeArea(child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
          children: [
            ListTile(
              leading: const Icon(Icons.radio_rounded),
              title: Text(station.title, maxLines: 1,
                overflow: TextOverflow.ellipsis),
              subtitle: Text(_quality(station)),
            ),
            if (songName.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.search_rounded),
                title: const Text('Find current song'),
                onTap: () => execute(() => _find(
                  artistName.isEmpty ? songName :
                    artistName + ' ' + songName)),
              ),
            if (artistName.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_search_rounded),
                title: const Text('Find artist'),
                onTap: () => execute(() => _find(artistName)),
              ),
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded),
              title: const Text('Favorite or unfavorite station'),
              onTap: () => execute(() => unawaited(ref
                  .read(stationFavoritesProvider.notifier).toggle(station))),
            ),
            ListTile(
              leading: const Icon(Icons.speaker_rounded),
              title: const Text('Audio output'),
              onTap: () => execute(() =>
                  unawaited(openAndroidOutputChooser(context))),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Share station'),
              onTap: () => execute(() => unawaited(_shareStation(station))),
            ),
            if (songName.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy current song'),
                onTap: () => execute(() => _copy(
                  artistName.isEmpty ? songName :
                    artistName + ' — ' + songName)),
              ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Copy station URL'),
              onTap: () => execute(() => _copy(station.url)),
            ),
            ListTile(
              leading: const Icon(Icons.explore_rounded),
              title: const Text('Browse stations'),
              onTap: () => execute(() {
                Navigator.of(context).push<void>(PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => const InternetRadioPage(),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ));
              }),
            ),
          ],
        )),
        );
      },
    );
  }

  String _quality(RadioStation station) => station.lossless
      ? station.codec + ' · Lossless'
      : station.codec + ' · ' + station.bitrate.toString() + ' kbps';

  Song _song(RadioStation station, String? art,
      {String? title, String? artist}) => Song(
    id: 'radio:' + station.id,
    title: title ?? station.title,
    artist: artist ?? station.title,
    albumArt: art ?? station.icon,
    fileType: 'Stream',
    duration: Duration.zero,
  );

  Widget _art(Song song, RadioStation station, {required bool fullCover}) {
    final url = song.albumArt;
    final fallback = const ColoredBox(
      color: Color(0xFF25242A),
      child: Center(child: Icon(Icons.radio_rounded,
        size: 72, color: Colors.white54)),
    );
    final image = url?.isNotEmpty == true
        ? Image.network(url!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            cacheWidth: fullCover ? 1536 : 960,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback)
        : fallback;
    // Retain station identity in a small badge if live song artwork exists.
    if (song.id != 'radio:' + station.id ||
        station.icon == null || url == station.icon) return image;
    return Stack(fit: StackFit.expand, children: [
      image,
      Positioned(
        right: fullCover ? 22 : 8,
        bottom: fullCover ? 22 : 8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.network(station.icon!, fit: BoxFit.cover,
            width: fullCover ? 40 : 30, height: fullCover ? 40 : 30,
            errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      ),
    ]);
  }

  Widget _carousel(RadioStation selected, List<RadioStation> queue,
      Song song, {required bool fullCover}) {
    final index = queue.indexWhere((item) => item.id == selected.id);
    final hasAdjacent = index >= 0 && queue.length > 1;
    final next = hasAdjacent ? queue[(index + 1) % queue.length] : null;
    final previous = hasAdjacent
        ? queue[(index - 1 + queue.length) % queue.length] : null;
    return SongStageCarousel(
      key: const ValueKey('radio-stage-carousel'),
      currentSong: song,
      nextSong: next == null ? null : _song(next, next.icon),
      prevSong: previous == null ? null : _song(previous, previous.icon),
      enabled: hasAdjacent,
      buttonDissolve: true,
      maskOutgoingOnDissolve: fullCover,
      onNext: ref.read(radioPlayerProvider.notifier).nextStation,
      onPrevious: ref.read(radioPlayerProvider.notifier).previousStation,
      stageBuilder: (entry) => _art(entry, selected, fullCover: fullCover),
    );
  }

  Widget _songInfo(RadioStation station, String? title, String? artist,
      {required bool compact}) {
    final hasSong = title?.trim().isNotEmpty == true;
    final hasArtist = artist?.trim().isNotEmpty == true;
    final name = hasSong ? title! : station.title;
    final performer = hasArtist ? artist! :
        hasSong ? station.title : 'Live broadcast';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const ValueKey('radio-player-song-title'),
          onTap: hasSong
              ? () => _find(hasArtist ? performer + ' ' + name : name)
              : () => _showMore(station, null, null),
          child: Row(children: [
            Expanded(child: Text(name,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: FullPlayerVisuals.primaryText,
                fontSize: compact ? 23 : 29,
                fontWeight: FontWeight.w700),
            )),
            if (hasSong) const Icon(Icons.north_east_rounded,
              color: FullPlayerVisuals.secondaryText, size: 17),
          ]),
        ),
        const SizedBox(height: 5),
        InkWell(
          key: const ValueKey('radio-player-song-artist'),
          onTap: hasArtist ? () => _find(performer) : null,
          child: Row(children: [
            Expanded(child: Text(performer,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: FullPlayerVisuals.secondaryText, fontSize: 16),
            )),
            if (hasArtist) const Icon(Icons.north_east_rounded,
              color: FullPlayerVisuals.secondaryText, size: 15),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.circle, size: 7, color: Color(0xFFF0765B)),
          const SizedBox(width: 8),
          Expanded(child: Text(station.title + ' · LIVE',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: FullPlayerVisuals.primaryText, fontSize: 12,
              fontWeight: FontWeight.w700),
          )),
          const SizedBox(width: 10),
          Text(_quality(station), maxLines: 1,
            style: const TextStyle(
              color: FullPlayerVisuals.secondaryText, fontSize: 12),
          ),
        ]),
      ],
    );
  }

  Widget _queueOverlay(List<RadioStation> stations, RadioStation current) =>
      AnimatedBuilder(
        animation: _queueController,
        builder: (context, _) {
          final p = _queueController.value.clamp(0.0, 1.0).toDouble();
          if (p == 0 && !_queue.isOpen) return const SizedBox.shrink();
          return Positioned.fill(child: IgnorePointer(
            ignoring: !_queue.isOpen,
            child: Opacity(opacity: p,
              child: Transform.translate(
                offset: Offset(0, MediaQuery.sizeOf(context).height * .3 *
                  (1 - Curves.easeOutCubic.transform(p))),
                child: ColoredBox(
                  color: const Color(0xFF17161C),
                  child: SafeArea(child: Column(children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setQueueOpen(false),
                      onVerticalDragUpdate: (details) =>
                          _queue.dragBy(-details.delta.dy),
                      onVerticalDragEnd: (details) => _queue.release(
                        -(details.primaryVelocity ?? 0)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 12, 18),
                        child: Row(children: [
                          const Icon(Icons.queue_music_rounded,
                            color: Colors.white),
                          const SizedBox(width: 12),
                          const Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('STATIONS', style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                              Text('Choose the next live stream', style:
                                TextStyle(color: Colors.white60, fontSize: 12)),
                            ],
                          )),
                          IconButton(
                            tooltip: 'Return to player',
                            onPressed: () => _setQueueOpen(false),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.white),
                          ),
                        ]),
                      ),
                    ),
                    Expanded(child: ListView.builder(
                      itemCount: stations.length,
                      itemBuilder: (_, index) {
                        final item = stations[index];
                        final selected = item.id == current.id;
                        return ListTile(
                          selected: selected, selectedColor: Colors.white,
                          leading: SizedBox.square(dimension: 44,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: item.icon == null ?
                                const Icon(Icons.radio_rounded,
                                  color: Colors.white70) :
                                Image.network(item.icon!, fit: BoxFit.cover,
                                  cacheWidth: 132, errorBuilder: (_, _, _) =>
                                    const Icon(Icons.radio_rounded,
                                      color: Colors.white70)),
                            )),
                          title: Text(item.title, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white)),
                          subtitle: Text(_quality(item), style:
                            const TextStyle(color: Colors.white60,
                              fontSize: 12)),
                          trailing: Icon(selected ? Icons.graphic_eq_rounded :
                            Icons.play_arrow_rounded, color: Colors.white),
                          onTap: () {
                            _setQueueOpen(false);
                            if (!selected) {
                              unawaited(ref.read(radioPlayerProvider.notifier)
                                .play(item));
                            }
                          },
                        );
                      },
                    )),
                  ])),
                ),
              ),
            ),
          ));
        },
      );

  @override
  Widget build(BuildContext context) {
    final radio = ref.watch(radioPlayerProvider);
    final station = radio.station;
    if (station == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF141318),
        body: Center(child: Text('No station playing',
          style: TextStyle(color: Colors.white))),
      );
    }
    final fullCover = ref.watch(lokalAppearanceProvider.select(
      (appearance) => appearance.fullscreenCover,
    ));
    final artist = radio.trackMetadata?.artist;
    final title = radio.trackMetadata?.title ?? radio.nowPlaying;
    final artwork = radio.trackMetadata?.cover ?? station.icon;
    final playback = ref.read(radioPlayerProvider.notifier);
    final stationQueue = playback.stationQueue;
    final favorite = ref.watch(stationFavoritesProvider)
        .containsKey(station.id);
    final song = _song(station, artwork, title: title, artist: artist);
    final accent = HSLColor.fromColor(Theme.of(context).colorScheme.primary);
    final colors = [
      const Color(0xFF141318),
      accent.withSaturation(.28).withLightness(.23).toColor(),
      accent.withSaturation(.20).withLightness(.12).toColor(),
    ];
    _queue.travel = MediaQuery.sizeOf(context).height * .7;
    return PopScope(
      canPop: !_queue.engaged,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _queue.engaged) _setQueueOpen(false);
      },
      child: LokalPullToDismiss(
        onDismiss: widget.onClose,
        onPullUpUpdate: _queue.dragBy,
        onPullUpEnd: (velocity) => _queue.release(velocity,
          animate: !MediaQuery.disableAnimationsOf(context)),
        isBlocked: () => _queue.engaged,
        child: Scaffold(
          backgroundColor: const Color(0xFF141318),
          body: Stack(fit: StackFit.expand, children: [
            ArtworkGradientBackdrop(colors: colors, vibrant: true),
            if (fullCover) Positioned.fill(
              child: LokalPlayerArtwork(
                expandedRadius: 0,
                child: _carousel(station, stationQueue, song,
                  fullCover: true),
              ),
            ),
            if (fullCover)
              const IgnorePointer(child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000), Color(0x16000000),
                    Color(0x40000000), Color(0xB0000000),
                  ],
                  stops: [0, .3, .67, 1],
                )),
              )),
            LokalPlayerChrome(
              enabled: fullCover,
              child: SafeArea(
                child: LayoutBuilder(builder: (context, bounds) {
                  final compact = bounds.maxHeight < 710;
                  final artSize = math.min(
                    math.min(bounds.maxWidth - 44.0, 520.0),
                    math.max(160.0, bounds.maxHeight - 390.0),
                  );
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                    child: Column(children: [
                      SizedBox(height: 50, child: Row(children: [
                        IconButton(
                          key: const ValueKey('radio-player-back'),
                          tooltip: 'Close player',
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.chevron_left_rounded,
                            color: FullPlayerVisuals.primaryText, size: 27),
                        ),
                        Expanded(child: Center(
                          child: TextButton.icon(
                            onPressed: () => unawaited(
                                openAndroidOutputChooser(context)),
                            icon: const Icon(Icons.speaker_rounded,
                              size: 17,
                              color: FullPlayerVisuals.primaryText),
                            label: const Text('AUDIO OUTPUT',
                              style: TextStyle(fontSize: 12,
                                color: FullPlayerVisuals.primaryText,
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w600)),
                          ),
                        )),
                        IconButton(
                          key: const ValueKey('radio-player-more'),
                          tooltip: 'More options',
                          onPressed: () => _showMore(station, artist, title),
                          icon: const Icon(Icons.more_vert_rounded,
                            color: FullPlayerVisuals.primaryText),
                        ),
                      ])),
                      Expanded(child: fullCover
                          ? const SizedBox.expand()
                          : Center(child: SizedBox.square(
                            dimension: artSize,
                            child: LokalPlayerArtwork(
                              expandedRadius: 24,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: _carousel(station, stationQueue, song,
                                  fullCover: false),
                              ),
                            ),
                          )),
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      _songInfo(station, title, artist, compact: compact),
                      const SizedBox(height: 13),
                      Row(children: [
                        const Text('LIVE', style: TextStyle(
                          color: FullPlayerVisuals.primaryText,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2, fontSize: 10)),
                        const SizedBox(width: 12),
                        Expanded(child: Container(height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        )),
                        const SizedBox(width: 12),
                        Text(radio.error != null ? 'STREAM ERROR' :
                          radio.loading ? 'CONNECTING' :
                          radio.playing ? 'ON AIR' : 'PAUSED',
                          style: const TextStyle(
                            color: FullPlayerVisuals.secondaryText,
                            fontSize: 10)),
                      ]),
                      const SizedBox(height: 9),
                      if (radio.loading)
                        const SizedBox(height: 78,
                          child: Center(child: CircularProgressIndicator(
                            color: Colors.white)))
                      else
                        PlayerTransportControls(
                          playing: radio.playing,
                          compact: compact,
                          lyricsProgress: 0,
                          accent: FullPlayerVisuals.fromPalette(colors).play,
                          onAccent: Colors.black,
                          onPrevious: () => unawaited(
                            playback.previousStation()),
                          onNext: () => unawaited(
                            playback.nextStation()),
                          onPlayPause: () => unawaited(playback.toggle()),
                        ),
                      Row(children: [
                        IconButton(
                          tooltip: favorite ? 'Remove favorite station' :
                            'Favorite station',
                          onPressed: () => unawaited(ref.read(
                            stationFavoritesProvider.notifier).toggle(station)),
                          icon: Icon(favorite ? Icons.favorite_rounded :
                            Icons.favorite_border_rounded,
                            color: favorite ? Colors.white :
                                FullPlayerVisuals.secondaryText),
                        ),
                        const Spacer(),
                        IconButton(
                          key: const ValueKey('radio-player-queue'),
                          tooltip: 'Station queue',
                          onPressed: () => _setQueueOpen(true),
                          icon: const Icon(Icons.queue_music_rounded,
                            color: FullPlayerVisuals.primaryText),
                        ),
                        IconButton(
                          tooltip: 'Stop station',
                          onPressed: () {
                            unawaited(playback.stop());
                            widget.onClose();
                          },
                          icon: const Icon(Icons.stop_rounded,
                            color: FullPlayerVisuals.secondaryText),
                        ),
                      ]),
                      ValueListenableBuilder<double>(
                        valueListenable: playback.volume,
                        builder: (context, volume, _) => Row(children: [
                          const Icon(Icons.volume_down_rounded,
                            color: FullPlayerVisuals.secondaryText, size: 19),
                          Expanded(child: Slider(
                            value: volume.clamp(0.0, 1.0).toDouble(),
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            onChanged: (value) =>
                                unawaited(playback.setVolume(value)),
                          )),
                          const Icon(Icons.volume_up_rounded,
                            color: FullPlayerVisuals.secondaryText, size: 19),
                        ]),
                      ),
                      if (radio.error != null)
                        Text(radio.error!, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF3AB9B), fontSize: 12)),
                    ]),
                  );
                }),
              ),
            ),
            _queueOverlay(stationQueue, station),
          ]),
        ),
      ),
    );
  }
}
