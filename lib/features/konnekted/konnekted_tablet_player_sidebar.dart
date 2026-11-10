import 'dart:async';

import 'package:path/path.dart' as path;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flick/features/internet_radio/radio_now_playing_page.dart'
    show openRadioCurrentAlbum;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/folders/screens/folders_screen.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/music_videos/music_video_providers.dart';
import 'package:flick/features/music_videos/music_videos_page.dart';
import 'package:flick/features/player/screens/desktop_remote_lyrics_panel.dart';
import 'package:flick/features/player/widgets/artist_credit_links.dart';
import 'package:flick/features/player/widgets/inline_lyrics_panel.dart';
import 'package:flick/features/player/widgets/motion_art_widget.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/features/player/widgets/song_metadata_sheet.dart';
import 'package:flick/features/queue/screens/queue_screen.dart';
import 'package:flick/features/songs/widgets/metadata_editor_bottom_sheet.dart';
import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/features/internet_radio/station_favorites.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_like_burst.dart';

import 'konnekted_data.dart';
import 'library/lokal_navigation.dart';
import 'library/lokal_radio.dart';
import 'tablet_playback.dart';

/// Desktop's Details/Lyrics/Queue hierarchy, with independently selectable
/// Details/Lyrics cards beneath the artwork. The sidebar never builds a
/// visualizer, and uses the existing media/lyrics/queue services unchanged.
class KonnektedTabletPlayerSidebar extends ConsumerStatefulWidget {
  const KonnektedTabletPlayerSidebar({
    super.key,
    required this.active,
    required this.tab,
    required this.onTabChanged,
    required this.onClose,
    required this.onOpenPlayer,
    this.onOpenLyrics,
    this.lyricsBuilder,
  });
  final bool active;
  final TabletPlayerTab tab;
  final ValueChanged<TabletPlayerTab> onTabChanged;
  final VoidCallback onClose, onOpenPlayer;
  final VoidCallback? onOpenLyrics;
  @visibleForTesting
  final Widget Function(Song song, bool remote, bool active)? lyricsBuilder;

  @override
  ConsumerState<KonnektedTabletPlayerSidebar> createState() =>
      _KonnektedTabletPlayerSidebarState();
}

class _KonnektedTabletPlayerSidebarState
    extends ConsumerState<KonnektedTabletPlayerSidebar> {
  TabletCoverCard _coverCard = TabletCoverCard.details;
  bool _combinedCards = false;
  bool _visited = false;
  bool _lyricsVisited = false;
  bool _queueVisited = false;
  final _lyricsKey = GlobalKey();
  final _detailsScroll = ScrollController();
  final _lyricsService = LyricsService();
  int _likeBurst = 0;
  String? _displaySongId;
  String? _videoLookupId;
  bool _likeBusy = false;

  @override
  void dispose() {
    _detailsScroll.dispose();
    super.dispose();
  }

  void _fullscreenLyrics() => (widget.onOpenLyrics ?? widget.onOpenPlayer)();

  Future<void> _showMore(Song song, TabletPlayback playback) async {
    if (playback.isRadio) {
      await _radioMenu(song, playback);
      return;
    }
    final current = ValueNotifier<Song?>(song);
    final container = ProviderScope.containerOf(context, listen: false);
    void update() {
      if (mounted) current.value = TabletPlayback.read(ref).song;
    }

    final music = container.listen(playerProvider, (_, _) => update());
    final radio = container.listen(radioPlayerProvider, (_, _) => update());
    try {
      await SongActionsBottomSheet.show(
        context,
        song,
        nowPlaying: true,
        playbackSong: current,
        hideMediaActions: playback.isRadio,
        extras: [
          if (song.artist.trim().isNotEmpty)
            LokalSongMenuAction(
              icon: Icons.radio_rounded,
              label: lokalText('Start artist radio'),
              onTap: () =>
                  unawaited(startLokalRadio(context, artist: song.artist)),
            ),
          if (!playback.isRadio &&
              !playback.remote &&
              song.filePath?.isNotEmpty == true)
            LokalSongMenuAction(
              icon: Icons.folder_open_rounded,
              label: lokalText('Open folder in Library'),
              onTap: () {
                final tree = song.folderUri;
                unawaited(
                  pushLokalPage(
                    context,
                    tree?.isNotEmpty == true
                        ? FolderBrowserScreen(
                            folderUri: tree!,
                            displayName: lokalText('Folders'),
                            prefix:
                                song.relativeFolderPath?.replaceAll(
                                  '\\',
                                  '/',
                                ) ??
                                '',
                          )
                        : FolderBrowserScreen(
                            folderUri: path.dirname(song.filePath!),
                            displayName: path.basename(
                              path.dirname(song.filePath!),
                            ),
                          ),
                  ),
                );
              },
            ),
        ],
      );
    } finally {
      music.close();
      radio.close();
      current.dispose();
    }
  }

  Future<void> _openAlbum(Song song, TabletPlayback playback) =>
      playback.isRadio
      ? openRadioCurrentAlbum(
          context,
          ref,
          playback.radio?.trackMetadata?.title ?? '',
          playback.radio?.trackMetadata?.artist ?? '',
        )
      : openLokalAlbumForSong(context, song);

  Future<void> _radioMenu(Song song, TabletPlayback playback) async {
    final station = playback.radio!.station!;
    final liked = ref.read(stationFavoritesProvider).containsKey(station.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                station.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final (id, icon, label) in [
              (
                'like',
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                liked ? 'Unfavorite station' : 'Favorite station',
              ),
              ('album', Icons.album_rounded, 'Go to album'),
              ('artist', Icons.person_search_rounded, 'Go to artist'),
              ('copy', Icons.copy_rounded, 'Copy current song'),
              ('url', Icons.link_rounded, 'Copy station URL'),
              ('share', Icons.share_rounded, 'Share station'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(lokalText(label)),
                onTap: () => Navigator.of(context).pop(id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'like':
        await ref.read(stationFavoritesProvider.notifier).toggle(station);
      case 'album':
        await _openAlbum(song, playback);
      case 'artist':
        await openLokalArtist(context, name: song.artist, song: song);
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: '${song.artist} — ${song.title}'),
        );
      case 'url':
        await Clipboard.setData(ClipboardData(text: station.url));
      case 'share':
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            text: '${station.title}\n${station.url}',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active) _visited = true;
    if (!_visited) return const SizedBox.shrink();
    final playback = TabletPlayback.watch(ref);
    final song = playback.song;
    if (_displaySongId != song?.id) {
      _displaySongId = song?.id;
      _likeBurst = 0;
    }
    if (widget.active &&
        song != null &&
        !playback.isRadio &&
        !playback.remote &&
        ref.watch(musicVideosEnabledProvider) &&
        _videoLookupId != song.id) {
      _videoLookupId = song.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.active &&
            ref.read(currentSongProvider)?.id == song.id) {
          unawaited(
            ref
                .read(musicVideoIndexProvider.notifier)
                .find(song)
                .catchError((Object _) => null),
          );
        }
      });
    }
    final t = context.lokal;
    final showLyrics =
        widget.tab == TabletPlayerTab.lyrics ||
        widget.tab == TabletPlayerTab.details &&
            (_combinedCards || _coverCard == TabletCoverCard.lyrics);
    if (widget.active && showLyrics) _lyricsVisited = true;
    if (widget.active && widget.tab == TabletPlayerTab.queue) {
      _queueVisited = true;
    }
    final lyrics = _lyricsVisited && song != null
        ? KeyedSubtree(
            key: _lyricsKey,
            child: playback.lyricsSong == null
                ? Center(
                    child: Text(
                      lokalText('Waiting for track information'),
                      style: TextStyle(color: t.muted),
                    ),
                  )
                : _lyricSurface(
                    playback.lyricsSong!,
                    playback.remote,
                    widget.active && showLyrics,
                  ),
          )
        : const SizedBox.shrink();
    final details = song == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.album_outlined, size: 56, color: t.muted2),
                  const SizedBox(height: 20),
                  Text(
                    lokalText('Nothing playing'),
                    style: TextStyle(fontSize: 22, color: t.text),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lokalText('Choose something from your library.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted, height: 1.5),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            controller: _detailsScroll,
            key: const PageStorageKey('tablet-player-details'),
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _artwork(song, playback),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => unawaited(_openAlbum(song, playback)),
                            child: Text(
                              song.title,
                              style: TextStyle(
                                color: t.text,
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                            ),
                          ),
                        ),
                        _likeButton(playback),
                        IconButton(
                          tooltip: lokalText('Song actions'),
                          icon: const Icon(Icons.more_horiz_rounded, size: 21),
                          onPressed: () => _showMore(song, playback),
                        ),
                      ],
                    ),
                    ArtistCreditLinks(
                      credit: song.artist,
                      style: TextStyle(color: t.muted, fontSize: 13),
                      onArtistTap: (name) => unawaited(
                        openLokalArtist(context, name: name, song: song),
                      ),
                    ),
                    if (!playback.remote && !playback.isRadio)
                      _PlaybackContext(song: song),
                    if (playback.remote)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          lokalText('Controlling desktop'),
                          style: LokalTheme.label(t, color: t.accent),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _actions(song, playback),
                    const SizedBox(height: 16),
                    _coverCardToggle(),
                    const SizedBox(height: 12),
                    if (_combinedCards || _coverCard == TabletCoverCard.details)
                      _metadata(song, playback),
                    if (widget.tab == TabletPlayerTab.details && showLyrics)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(height: 420, child: lyrics),
                      ),
                  ],
                ),
              ),
            ],
          );
    return SafeArea(
      left: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                for (final tab in TabletPlayerTab.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Semantics(
                        selected: widget.tab == tab,
                        child: TextButton(
                          key: ValueKey('player-sidebar-tab-${tab.name}'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 10,
                            ),
                            foregroundColor: widget.tab == tab
                                ? t.accent
                                : t.muted,
                            backgroundColor: widget.tab == tab
                                ? t.accentSoft
                                : t.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => widget.onTabChanged(tab),
                          child: Text(
                            lokalText(switch (tab) {
                              TabletPlayerTab.details => 'Details',
                              TabletPlayerTab.lyrics => 'Lyrics',
                              TabletPlayerTab.queue => 'Queue',
                            }),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('close-player-sidebar'),
                  tooltip: lokalText('Hide player sidebar'),
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.chevron_right_rounded, size: 21),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: widget.tab != TabletPlayerTab.details,
                  child: TickerMode(
                    enabled:
                        widget.active && widget.tab == TabletPlayerTab.details,
                    child: details,
                  ),
                ),
                if (widget.tab == TabletPlayerTab.lyrics)
                  Positioned.fill(
                    child: song == null
                        ? Center(child: Text(lokalText('Nothing playing')))
                        : lyrics,
                  ),
                if (_lyricsVisited && !showLyrics)
                  Offstage(child: SizedBox(height: 420, child: lyrics)),
                if (_queueVisited)
                  Positioned.fill(
                    child: Offstage(
                      offstage: widget.tab != TabletPlayerTab.queue,
                      child: TickerMode(
                        enabled:
                            widget.active &&
                            widget.tab == TabletPlayerTab.queue,
                        child: playback.isRadio
                            ? const _StationQueue()
                            : QueueList(embedded: true, themed: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lyricSurface(Song song, bool remote, bool active) {
    final dark = LokalTokens.resolve(LokalThemeId.dark).copyWith(
      accent: context.lokal.accent,
      accentDim: context.lokal.accentDim,
    );
    return Theme(
      data: LokalTheme.build(dark),
      child: ColoredBox(
        color: dark.surface,
        child:
            widget.lyricsBuilder?.call(song, remote, active) ??
            (remote
                ? DesktopRemoteLyricsPanel(
                    fullPlayerTypography: true,
                    key: ValueKey('tablet-remote-lyrics:${song.id}'),
                    song: song,
                    onClose: () => widget.onTabChanged(TabletPlayerTab.details),
                  )
                : InlineLyricsPanel(
                    key: ValueKey('tablet-local-lyrics:${song.id}'),
                    playerService: ref.read(playerServiceProvider),
                    lyricsService: _lyricsService,
                    song: song,
                    active: active,
                    compactControls: true,
                  )),
      ),
    );
  }

  Widget _artwork(Song song, TabletPlayback playback) {
    final prefs = ref.watch(appPreferencesProvider);
    final disabled = ref
        .watch(movingCoverSettingsProvider)
        .disabledSongs
        .contains(movingCoverSongKey(song));
    final motion =
        prefs.animatedAlbumArt && prefs.animationsEnabled && !disabled;
    final playing = playback.isRadio
        ? playback.radio!.playing
        : ref.watch(isPlayingProvider);
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey('sidebar-artwork'),
            onTap: widget.onOpenPlayer,
            onDoubleTap: () => unawaited(_like(playback)),
            onLongPress: () => _showMore(song, playback),
            child: MotionArtView(
              sharedPlaybackKey: 'player:${song.id}',
              title: song.title,
              artist: song.artist,
              album: song.album,
              duration: song.duration,
              enabled:
                  motion &&
                  widget.active &&
                  widget.tab == TabletPlayerTab.details,
              playbackActive: playing && widget.active,
              fallback: PlayerArtworkImage(
                song: song,
                radius: 0,
                decodeWidth: 900,
              ),
            ),
          ),
          if (_likeBurst > 0)
            Center(
              child: LokalLikeBurst(
                key: ValueKey('${song.id}:$_likeBurst'),
                color: context.lokal.accent,
                size: 60,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _like(TabletPlayback playback) async {
    final song = playback.song;
    if (song == null || _likeBusy) return;
    setState(() => _likeBusy = true);
    try {
      final station = playback.radio?.station;
      final bool liked;
      if (station != null) {
        final before = ref
            .read(stationFavoritesProvider)
            .containsKey(station.id);
        await ref.read(stationFavoritesProvider.notifier).toggle(station);
        liked = !before;
      } else {
        liked = await ref
            .read(favoritesProvider.notifier)
            .toggleFavorite(song.id, song: song);
      }
      if (mounted &&
          liked &&
          (playback.isRadio
                  ? 'radio:${ref.read(radioPlayerProvider).station?.id}'
                  : ref.read(currentSongProvider)?.id) ==
              song.id) {
        setState(() => _likeBurst++);
      }
    } catch (_) {
      if (mounted) {
        LokalToast.show(
          context,
          lokalText('Could not update this song’s like.'),
        );
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  Widget _likeButton(TabletPlayback playback) {
    final station = playback.radio?.station;
    final liked = station != null
        ? ref.watch(stationFavoritesProvider).containsKey(station.id)
        : ref.watch(favoritesProvider).value?.isFavorite(playback.song!.id) ==
              true;
    return IconButton(
      key: const ValueKey('sidebar-like'),
      tooltip: lokalText(liked ? 'Unlike' : 'Like'),
      onPressed: _likeBusy ? null : () => unawaited(_like(playback)),
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? context.lokal.accent : context.lokal.muted,
        size: 20,
      ),
    );
  }

  Widget _actions(Song song, TabletPlayback playback) {
    final settings = ref.watch(movingCoverSettingsProvider);
    final off = settings.disabledSongs.contains(movingCoverSongKey(song));
    final videos =
        !playback.isRadio &&
        !playback.remote &&
        ref.watch(musicVideosEnabledProvider);
    final video = videos
        ? ref.watch(musicVideoIndexProvider).videoFor(song.id)
        : null;
    return LokalGlass(
      staticSurface: true,
      shadow: false,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Expanded(
            child: IconButton(
              tooltip: lokalText('Full screen'),
              onPressed: widget.onOpenPlayer,
              icon: const Icon(Icons.open_in_full_rounded, size: 20),
            ),
          ),
          Expanded(
            child: IconButton(
              tooltip: lokalText('Lyrics, full screen'),
              onPressed: _fullscreenLyrics,
              icon: const Icon(Icons.lyrics_outlined, size: 20),
            ),
          ),
          if (video != null)
            Expanded(
              child: IconButton(
                tooltip: lokalText('Music video'),
                onPressed: () => unawaited(watchMusicVideo(context, song)),
                icon: const Icon(Icons.smart_display_outlined, size: 20),
              ),
            ),
          Expanded(
            child: IconButton(
              key: const ValueKey('sidebar-motion-toggle'),
              tooltip: lokalText(
                off ? 'Show moving artwork' : 'Hide moving artwork',
              ),
              isSelected: !off,
              onPressed: () => unawaited(
                ref
                    .read(movingCoverSettingsProvider.notifier)
                    .setSongEnabled(movingCoverSongKey(song), off),
              ),
              icon: Icon(
                off ? Icons.image_outlined : Icons.motion_photos_on_outlined,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverCardToggle() => Row(
    children: [
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const ValueKey('below-cover-details'),
              label: Text(
                lokalText('Details'),
                style: const TextStyle(
                  fontFamily: LokalTheme.sans,
                  fontSize: 12,
                ),
              ),
              selected: _combinedCards || _coverCard == TabletCoverCard.details,
              onSelected: (_) => setState(() {
                _combinedCards = false;
                _coverCard = TabletCoverCard.details;
              }),
            ),
            ChoiceChip(
              key: const ValueKey('below-cover-lyrics'),
              label: Text(
                lokalText('Lyrics'),
                style: const TextStyle(
                  fontFamily: LokalTheme.sans,
                  fontSize: 12,
                ),
              ),
              selected: _combinedCards || _coverCard == TabletCoverCard.lyrics,
              onSelected: (_) => setState(() {
                _combinedCards = false;
                _coverCard = TabletCoverCard.lyrics;
              }),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey('combine-sidebar-cards'),
        tooltip: lokalText(
          _combinedCards
              ? 'Separate details and lyrics'
              : 'Details and lyrics together',
        ),
        isSelected: _combinedCards,
        onPressed: () => setState(() => _combinedCards = !_combinedCards),
        icon: Icon(
          _combinedCards
              ? Icons.splitscreen_rounded
              : Icons.view_agenda_outlined,
          size: 20,
        ),
      ),
    ],
  );

  Widget _metadata(Song song, TabletPlayback playback) {
    final t = context.lokal;
    final editable =
        !playback.isRadio &&
        !playback.remote &&
        !song.isExternal &&
        !song.isNetworkSource &&
        !song.isPending &&
        song.filePath?.isNotEmpty == true &&
        song.startOffsetMs == null;
    Widget row(String label, String? value, {VoidCallback? onTap}) =>
        value == null || value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    lokalText(label).toUpperCase(),
                    style: LokalTheme.label(t, size: 9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: onTap == null
                      ? SelectableText(
                          value,
                          style: TextStyle(fontSize: 12, color: t.text),
                        )
                      : InkWell(
                          onTap: onTap,
                          child: Text(
                            value,
                            style: TextStyle(fontSize: 12, color: t.text),
                          ),
                        ),
                ),
              ],
            ),
          );
    return Container(
      key: const ValueKey('sidebar-metadata'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            'Album',
            song.album,
            onTap: () => unawaited(_openAlbum(song, playback)),
          ),
          if (song.albumArtist != song.artist)
            row(
              'Alb. Artist',
              song.albumArtist,
              onTap: () => unawaited(
                openLokalArtist(context, name: song.albumArtist, song: song),
              ),
            ),
          row('Year', song.year?.toString()),
          row(
            'Genre',
            song.genre ??
                (editable
                    ? lokalText('Add a genre…')
                    : playback.radio?.station?.genre),
            onTap: editable
                ? () => unawaited(MetadataEditorBottomSheet.show(context, song))
                : null,
          ),
          row('Track #', song.trackNumber?.toString()),
          row('Format', song.fileType),
          row(
            'Quality',
            [
              if (song.resolution?.isNotEmpty == true) song.resolution!,
              if (song.bitDepth != null) '${song.bitDepth} bit',
              if (song.sampleRate != null) '${song.sampleRate! / 1000} kHz',
            ].join(' · '),
          ),
          if (playback.radio?.station?.bitrate case final int bitrate
              when bitrate > 0)
            row('Bitrate', '$bitrate kbps'),
          if (!playback.isRadio && !playback.remote) _StoredBitrate(song: song),
          row('Source', metadataSourceLabel(song)),
          if (!playback.isRadio && !playback.remote) _PlayCount(song: song),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => unawaited(SongMetadataSheet.show(context, song)),
              child: Text(lokalText('All metadata')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read the scanner's persisted measurement for this exact recording. Never
/// infer compressed bitrate from PCM resolution, duration or file size.
class _StoredBitrate extends ConsumerStatefulWidget {
  const _StoredBitrate({required this.song});
  final Song song;
  @override
  ConsumerState<_StoredBitrate> createState() => _StoredBitrateState();
}

class _StoredBitrateState extends ConsumerState<_StoredBitrate> {
  late Future<int?> _bitrate = _load();
  Future<int?> _load() async {
    final id = int.tryParse(widget.song.id);
    if (id == null || widget.song.filePath?.isNotEmpty != true) return null;
    try {
      final row = await ref
          .read(songRepositoryProvider)
          .isar
          .songEntitys
          .get(id);
      return row?.filePath == widget.song.filePath ? row?.bitrate : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant _StoredBitrate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.filePath != widget.song.filePath) {
      _bitrate = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int?>(
    future: _bitrate,
    builder: (context, snapshot) => snapshot.data == null || snapshot.data! <= 0
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    lokalText('Bitrate').toUpperCase(),
                    style: LokalTheme.label(context.lokal, size: 9),
                  ),
                ),
                Text(
                  '${snapshot.data} kbps',
                  style: TextStyle(fontSize: 12, color: context.lokal.text),
                ),
              ],
            ),
          ),
  );
}

class _PlayCount extends ConsumerWidget {
  const _PlayCount({required this.song});
  final Song song;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<Map<String, int>>(
        future: ref.watch(konnektedHistoryRepositoryProvider).getPlayCounts(),
        builder: (context, snapshot) => snapshot.hasData
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        lokalText('Plays').toUpperCase(),
                        style: LokalTheme.label(context.lokal, size: 9),
                      ),
                    ),
                    Text(
                      '${snapshot.data![song.id] ?? 0}',
                      style: TextStyle(fontSize: 12, color: context.lokal.text),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      );
}

class _PlaybackContext extends ConsumerWidget {
  const _PlaybackContext({required this.song});
  final Song song;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ValueListenableBuilder<PlaybackContext>(
        valueListenable: ref
            .read(playerServiceProvider)
            .playbackContextNotifier,
        builder: (context, playback, _) =>
            playback.sourceName?.isNotEmpty != true
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  onTap: () {
                    if (playback.source == PlaybackSource.album) {
                      unawaited(openLokalAlbumForSong(context, song));
                    } else if (playback.source == PlaybackSource.artist)
                      unawaited(openLokalArtist(context, song: song));
                    else if (playback.source == PlaybackSource.playlist &&
                        playback.sourceId != null)
                      unawaited(openLokalPlaylist(context, playback.sourceId!));
                    else if (playback.source == PlaybackSource.folder)
                      unawaited(pushLokalPage(context, const FoldersScreen()));
                  },
                  child: Text(
                    '${lokalText('Playing from')} · ${playback.sourceName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LokalTheme.label(context.lokal, size: 10),
                  ),
                ),
              ),
      );
}

class _StationQueue extends ConsumerWidget {
  const _StationQueue();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioPlayerProvider);
    final player = ref.read(radioPlayerProvider.notifier);
    final stations = player.stationQueue;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (final station in stations)
          ListTile(
            selected: radio.station?.id == station.id,
            leading: const Icon(Icons.radio_rounded),
            title: Text(station.title),
            subtitle: Text(
              [
                station.codec,
                if (station.bitrate > 0) '${station.bitrate} kbps',
              ].join(' · '),
            ),
            onTap: () => unawaited(
              tabletPlaybackAction(context, () => player.play(station)),
            ),
          ),
      ],
    );
  }
}
