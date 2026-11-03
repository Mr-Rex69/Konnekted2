import 'dart:async';
import 'dart:math' as math;

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/library/lokal_navigation.dart';
import 'package:flick/features/konnekted/library/lokal_music_detail_page.dart';
import 'package:flick/services/global_catalogue_search.dart';
import 'package:flick/services/android_audio_device_service.dart';
import 'package:flick/features/internet_radio/internet_radio_page.dart';
import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/internet_radio/station_favorites.dart';
import 'package:flick/features/player/widgets/artwork_gradient_backdrop.dart';
import 'package:flick/features/player/widgets/artwork_mesh_blur_backdrop.dart';
import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
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

String _radioIdentity(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Live radio metadata has no album ID. Only a complete artist/title match
/// with a single identifiable release may navigate directly to an album.
@visibleForTesting
Song? radioMatchingLocalAlbum(
  Iterable<Song> library, {
  required String title,
  required String artist,
}) {
  if (title.trim().isEmpty || artist.trim().isEmpty) return null;
  final rows = library.where((song) =>
      _radioIdentity(song.title) == _radioIdentity(title) &&
      _radioIdentity(song.artist) == _radioIdentity(artist) &&
      (song.album?.trim().isNotEmpty ?? false)).toList();
  if (rows.isEmpty ||
      rows.map((s) => _radioIdentity(s.album!)).toSet().length != 1) {
    return null;
  }
  return rows.first;
}

@visibleForTesting
GlobalCatalogueSong? radioMatchingCatalogueAlbum(
  Iterable<GlobalCatalogueSong> rows, {
  required String title,
  required String artist,
}) {
  if (title.trim().isEmpty || artist.trim().isEmpty) return null;
  final exact = rows.where((row) =>
      _radioIdentity(row.title) == _radioIdentity(title) &&
      _radioIdentity(row.artist) == _radioIdentity(artist) &&
      row.album.trim().isNotEmpty).toList();
  if (exact.isEmpty ||
      exact.map((s) => _radioIdentity(s.album)).toSet().length != 1) {
    return null;
  }
  return exact.first;
}

/// Use Android's live media-route snapshot, not the ordinary music engine's
/// stale diagnostics while a separate radio stream is playing.
@visibleForTesting
String radioOutputRouteLabel(AndroidPlaybackDeviceInfo route) {
  switch ((route.routeType ?? '').toLowerCase()) {
    case 'internal':
    case 'speaker':
      return 'Speaker';
    case 'wired':
      return route.routeLabel?.trim().isNotEmpty == true
          ? route.routeLabel!.trim() : 'Wired headphones';
    case 'bluetooth':
      return route.routeLabel?.trim().isNotEmpty == true
          ? route.routeLabel!.trim() : 'Bluetooth audio';
    case 'usb':
    case 'dock':
      return route.routeLabel?.trim().isNotEmpty == true
          ? route.routeLabel!.trim() : 'USB audio';
    default:
      return route.routeLabel?.trim().isNotEmpty == true
          ? route.routeLabel!.trim() : 'Audio output';
  }
}

@visibleForTesting
IconData radioOutputRouteIcon(AndroidPlaybackDeviceInfo route) {
  switch ((route.routeType ?? '').toLowerCase()) {
    case 'internal':
    case 'speaker':
      return Icons.speaker_rounded;
    case 'wired':
      return Icons.headphones_rounded;
    case 'bluetooth':
      return Icons.bluetooth_audio_rounded;
    case 'usb':
    case 'dock':
      return Icons.usb_rounded;
    default:
      return Icons.speaker_rounded;
  }
}

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
    unawaited(AndroidAudioDeviceService.instance.initialize());
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

  Future<void> _openCurrentAlbum(String title, String artist) async {
    final normalizedTitle = title.trim();
    final normalizedArtist = artist.trim();
    if (normalizedTitle.isEmpty || normalizedArtist.isEmpty) {
      _find('$normalizedArtist $normalizedTitle');
      return;
    }

    // Prefer a verified local recording, never create an album by guessing
    // from a station name or from a search result with a different artist.
    final local = ref.read(konnektedLibraryProvider).value ?? const <Song>[];
    final owned = radioMatchingLocalAlbum(
      local, title: normalizedTitle, artist: normalizedArtist,
    );
    if (owned != null) {
      await openLokalAlbumForSong(context, owned);
      return;
    }

    GlobalCatalogueSong? matched;
    try {
      final result = await const GlobalCatalogueSearchService()
          .search('$normalizedArtist $normalizedTitle', songsOnly: true)
          .timeout(const Duration(seconds: 9));
      matched = radioMatchingCatalogueAlbum(
        result.songs, title: normalizedTitle, artist: normalizedArtist,
      );
    } catch (_) {
      // A radio stream does not identify the album; never open an unrelated
      // release on timeout, invalid metadata, or ambiguous catalogue hits.
    }
    if (!mounted) return;
    if (matched == null) {
      _find('$normalizedArtist $normalizedTitle');
      return;
    }
    await pushLokalPage(
      context,
      LokalMusicDetailPage.album(
        title: matched.album,
        artist: matched.artist,
        localSongs: const [],
        initialOnline: true,
      ),
    );
  }

  Future<void> _chooseOutput() async {
    await openAndroidOutputChooser(context);
    // Android's route-change callback normally refreshes this as soon as
    // the user selects a device; also request an explicit snapshot.
    await AndroidAudioDeviceService.instance.refresh();
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
    final theme = context.lokal;
    final art = ref.read(radioPlayerProvider).trackMetadata?.cover ??
        station.icon;

    // Match the regular FullPlayer's song-actions sheet: surface color,
    // 24px rounded top, border, drag handle, artwork header and 50px rows.
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: theme.surface,
      barrierColor: Colors.black.withValues(
        alpha: theme.isLight ? .25 : .5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: theme.border),
      ),
      builder: (sheetContext) {
        final colors = sheetContext.lokal;
        void execute(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        final entries = <Widget>[
          if (songName.isNotEmpty)
            _RadioMenuRow(
              icon: Icons.album_outlined,
              label: 'Open current album',
              onTap: () => execute(
                () => unawaited(_openCurrentAlbum(songName, artistName)),
              ),
            ),
          if (artistName.isNotEmpty)
            _RadioMenuRow(
              icon: Icons.person_outline_rounded,
              label: 'Open artist',
              onTap: () => execute(
                () => unawaited(
                  openLokalArtist(context, name: artistName),
                ),
              ),
            ),
          if (songName.isNotEmpty)
            _RadioMenuRow(
              icon: Icons.search_rounded,
              label: 'Find current song',
              onTap: () => execute(() => _find(
                artistName.isEmpty ? songName :
                    '$artistName $songName',
              )),
            ),
          if (artistName.isNotEmpty)
            _RadioMenuRow(
              icon: Icons.person_search_rounded,
              label: 'Find artist',
              onTap: () => execute(() => _find(artistName)),
            ),
          _RadioMenuRow(
            icon: Icons.favorite_border_rounded,
            label: 'Favorite or unfavorite station',
            onTap: () => execute(() => unawaited(ref
                .read(stationFavoritesProvider.notifier).toggle(station))),
          ),
          _RadioMenuRow(
            icon: Icons.speaker_rounded,
            label: 'Audio output',
            onTap: () => execute(() => unawaited(_chooseOutput())),
          ),
          _RadioMenuRow(
            icon: Icons.ios_share_rounded,
            label: 'Share station',
            onTap: () => execute(
              () => unawaited(_shareStation(station)),
            ),
          ),
          if (songName.isNotEmpty)
            _RadioMenuRow(
              icon: Icons.copy_rounded,
              label: 'Copy current song',
              onTap: () => execute(() => _copy(
                artistName.isEmpty ? songName :
                    '$artistName — $songName',
              )),
            ),
          _RadioMenuRow(
            icon: Icons.link_rounded,
            label: 'Copy station URL',
            onTap: () => execute(() => _copy(station.url)),
          ),
          _RadioMenuRow(
            icon: Icons.explore_rounded,
            label: 'Browse stations',
            onTap: () => execute(() {
              Navigator.of(context).push<void>(PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => const InternetRadioPage(),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ));
            }),
          ),
        ];
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox.square(
                        dimension: 52,
                        child: art != null && art.startsWith('https://')
                            ? Image.network(
                                art,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.radio_rounded,
                                ),
                              )
                            : const ColoredBox(
                                color: Color(0xFF25242A),
                                child: Icon(Icons.radio_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            songName.isNotEmpty ? songName : station.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: LokalTheme.sans,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.text,
                            ),
                          ),
                          Text(
                            artistName.isNotEmpty
                                ? '$artistName · ${station.title}'
                                : _quality(station),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(
                    top: 6,
                    bottom: 12 + MediaQuery.paddingOf(sheetContext).bottom,
                  ),
                  children: entries,
                ),
              ),
            ],
          ),
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
    // A station favicon is often only 32–128 px. Stretching it edge-to-edge
    // in Full Cover looks pixelated; instead keep the ambient full player
    // background and display the station branding at a deliberate size.
    if (fullCover && url != null && url == station.icon) {
      return Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Image.network(url, fit: BoxFit.contain,
            cacheWidth: 480,
            errorBuilder: (_, _, _) => fallback),
        ),
      ));
    }
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
      stageBuilder: (entry) {
        final art = _art(entry, selected, fullCover: fullCover);
        // Exactly the still-art path used by FullPlayerScreen: a partial
        // banner with a feathered edge, never a viewport-stretched cover.
        if (!fullCover) return art;
        return FullBleedArtworkFrame(
          canvas: false,
          morphEnabled: entry.id == song.id,
          child: art,
        );
      },
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
              ? () => unawaited(
                  _openCurrentAlbum(name, hasArtist ? performer : ''),
                )
              : () => _showMore(station, null, null),
          borderRadius: BorderRadius.circular(8),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: FullPlayerVisuals.primaryText,
              fontSize: compact ? 23 : 29,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 5),
        InkWell(
          key: const ValueKey('radio-player-song-artist'),
          onTap: hasArtist
              ? () => unawaited(
                  openLokalArtist(context, name: performer),
                )
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Text(
            performer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: FullPlayerVisuals.secondaryText,
              fontSize: 16,
            ),
          ),
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
            if (fullCover)
              ArtworkMeshBlurBackdrop(
                song: song,
                preserveArtworkContrast: true,
              ),
            // Use the regular player's restrained control contrast, not the
            // opaque dark overlay that exposed a horizontal cover boundary.
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
                        Color(0x10000000),
                        Color(0x40000000),
                      ],
                      stops: [0, .28, .66, 1],
                    ),
                  ),
                ),
              ),
            if (fullCover)
              Positioned.fill(
                child: _carousel(
                  station, stationQueue, song,
                  fullCover: true,
                ),
              ),
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
                        Expanded(
                          child: Center(
                            child: ValueListenableBuilder<AndroidPlaybackDeviceInfo>(
                              valueListenable: AndroidAudioDeviceService
                                  .instance.deviceInfoNotifier,
                              builder: (context, output, _) => InkWell(
                                onTap: () => unawaited(_chooseOutput()),
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  constraints: const BoxConstraints(maxWidth: 204),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: .22),
                                    ),
                                    color: Colors.white.withValues(alpha: .08),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        radioOutputRouteIcon(output),
                                        size: 17,
                                        color: FullPlayerVisuals.primaryText,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          radioOutputRouteLabel(output),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: FullPlayerVisuals.primaryText,
                                            fontWeight: FontWeight.w500,
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

class _RadioMenuRow extends StatelessWidget {
  const _RadioMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.lokal;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: theme.muted),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: LokalTheme.sans,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: theme.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
