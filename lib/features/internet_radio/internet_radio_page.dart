import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'radio_browser.dart';
import 'radio_catalog.dart';
import 'radio_providers.dart';
import 'station_favorites.dart';
import 'station_metadata.dart';

const _countries = <String, String>{
  '': 'Worldwide',
  'FR': 'France',
  'US': 'United States',
  'GB': 'United Kingdom',
  'DE': 'Germany',
  'CA': 'Canada',
  'NL': 'Netherlands',
  'IT': 'Italy',
  'ES': 'Spain',
  'JP': 'Japan',
  'AU': 'Australia',
  'BR': 'Brazil',
  'BE': 'Belgium',
  'CH': 'Switzerland',
};
const _genres = [
  '', 'jazz', 'electronic', 'rock', 'classical',
  'hip hop', 'ambient', 'soul', 'pop', 'world',
];

bool _qualifies(RadioStation station) =>
    station.lossless ||
    (station.bitrate >= stationMinimumBitrate &&
        const {'MP3', 'AAC', 'AAC+', 'HE-AAC', 'OPUS', 'OGG', 'VORBIS'}
            .contains(station.codec.toUpperCase()));

/// Global, high-quality radio discovery with local favorites and one-tap play.
/// Only the selected stream is connected; the list does not probe audio URLs.
class InternetRadioPage extends ConsumerStatefulWidget {
  const InternetRadioPage({super.key});

  @override
  ConsumerState<InternetRadioPage> createState() => _InternetRadioPageState();
}

class _InternetRadioPageState extends ConsumerState<InternetRadioPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _country = '';
  String _genre = '';
  bool _favoritesOnly = false;
  bool _losslessOnly = false;
  bool _loading = false;
  bool _moreLoading = false;
  bool _hasMore = false;
  String? _error;
  int _nextOffset = 0;
  int _generation = 0;
  List<RadioStation> _stations = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(reset: true));
    });
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _moreLoading || !_hasMore)) return;
    final generation = ++_generation;
    setState(() {
      if (reset) {
        _stations = const [];
        _nextOffset = 0;
        _loading = true;
      } else {
        _moreLoading = true;
      }
      _error = null;
    });
    final client = RadioBrowserClient();
    try {
      final result = await client.browse(
        query: _query,
        country: _country,
        tag: _genre,
        offset: reset ? 0 : _nextOffset,
      );
      if (!mounted || generation != _generation) return;
      unawaited(ref.read(stationFavoritesProvider.notifier).adoptLegacy(result.stations));
      final seen = <String>{for (final s in reset ? const <RadioStation>[] : _stations) s.id};
      setState(() {
        _stations = [
          if (!reset) ..._stations,
          for (final station in result.stations)
            if (_qualifies(station) && seen.add(station.id)) station,
        ];
        _nextOffset = result.nextOffset;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load stations. Check your connection.');
      }
    } finally {
      client.close();
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _moreLoading = false;
        });
      }
    }
  }

  void _updateSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _query = value.trim();
      unawaited(_load(reset: true));
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(stationFavoritesProvider);
    final filtered = (_favoritesOnly
            ? favorites.values.toList(growable: false)
            : _stations)
        .where(_qualifies)
        .where((s) => !_losslessOnly || s.lossless)
        .where((s) => !_favoritesOnly ||
            (_country.isEmpty || s.countryCode == _country) &&
            (_genre.isEmpty ||
                (s.genre ?? '').toLowerCase().contains(_genre)) &&
            (_search.text.trim().isEmpty ||
                (s.title + ' ' + s.country + ' ' + (s.genre ?? ''))
                    .toLowerCase().contains(_search.text.trim().toLowerCase())))
        .toList(growable: false);
    final t = context.lokal;
    return LokalLibraryPage(
      title: 'Stations',
      subtitle: 'Worldwide · 256 kbps+ or lossless · Radio Browser',
      actions: [
        LokalRoundAction(
          icon: Icons.refresh_rounded,
          label: 'Refresh stations',
          onPressed: () => unawaited(_load(reset: true)),
        ),
      ],
      slivers: [
        const SliverToBoxAdapter(child: _NowPlayingStation()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: LokalSearchField(
              controller: _search,
              hint: 'Search stations worldwide',
              onChanged: _updateSearch,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _FilterChip(
                  label: 'Explore',
                  icon: Icons.public_rounded,
                  selected: !_favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = false),
                ),
                _FilterChip(
                  label: 'Favorites',
                  icon: Icons.favorite_rounded,
                  selected: _favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = true),
                ),
                _FilterChip(
                  label: 'Lossless',
                  selected: _losslessOnly,
                  onTap: () => setState(() => _losslessOnly = !_losslessOnly),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: DropdownButton<String>(
              value: _country,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              icon: Icon(Icons.expand_more_rounded, color: t.muted),
              items: [
                for (final country in _countries.entries)
                  DropdownMenuItem(
                    value: country.key,
                    child: Text(country.value,
                        style: TextStyle(color: t.text, fontSize: 14)),
                  ),
              ],
              onChanged: (value) {
                if (value == null || value == _country) return;
                setState(() => _country = value);
                unawaited(_load(reset: true));
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final genre in _genres)
                  _FilterChip(
                    label: genre.isEmpty ? 'All genres' : genre,
                    selected: _genre == genre,
                    onTap: () {
                      if (_genre == genre) return;
                      setState(() => _genre = genre);
                      unawaited(_load(reset: true));
                    },
                  ),
              ],
            ),
          ),
        ),
        if (!_favoritesOnly && _loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: _favoritesOnly
                  ? Icons.favorite_border_rounded : Icons.radio_rounded,
              title: _favoritesOnly ? 'No favorite stations' : 'No stations found',
              message: _error ??
                  (_favoritesOnly
                      ? 'Tap a heart to save a station here.'
                      : 'Only lossless and 256+ kbps stations are shown.'),
              actionLabel: !_favoritesOnly && _error != null ? 'Retry' : null,
              onAction: !_favoritesOnly && _error != null
                  ? () => unawaited(_load(reset: true)) : null,
            ),
          )
        else
          SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) => _StationRow(
              key: ValueKey(filtered[index].id),
              station: filtered[index],
              favorite: favorites.containsKey(filtered[index].id),
            ),
          ),
        if (!_favoritesOnly && _hasMore && !_loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: TextButton(
                  onPressed: _moreLoading ? null : () =>
                      unawaited(_load(reset: false)),
                  child: _moreLoading
                      ? const CircularProgressIndicator()
                      : const Text('Show more stations'),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Text(
              'Quality is reported by Radio Browser and may differ from the actual stream. '
              'Track titles appear when the broadcaster supplies metadata.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Material(
        color: selected ? t.accent : t.surface2,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: selected ? t.bg : t.accent),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(
                  color: selected ? t.bg : t.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationRow extends ConsumerStatefulWidget {
  const _StationRow({super.key, required this.station, required this.favorite});
  final RadioStation station;
  final bool favorite;

  @override
  ConsumerState<_StationRow> createState() => _StationRowState();
}

class _StationRowState extends ConsumerState<_StationRow> {
  Timer? _metadataTimer;
  String? _broadcastTrack;
  String? _broadcastCover;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshMetadata());
    });
    _metadataTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_refreshMetadata());
    });
  }

  @override
  void didUpdateWidget(covariant _StationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != widget.station.id) {
      _broadcastTrack = null;
      _broadcastCover = null;
      unawaited(_refreshMetadata());
    }
  }

  Future<void> _refreshMetadata() async {
    final id = widget.station.id;
    final info = await StationMetadataLookup.lookup(widget.station);
    if (!mounted || id != widget.station.id || info == null ||
        (info.label == _broadcastTrack && info.cover == _broadcastCover)) return;
    setState(() {
      _broadcastTrack = info.label;
      _broadcastCover = info.cover;
    });
  }

  @override
  void dispose() {
    _metadataTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final favorite = widget.favorite;
    final t = context.lokal;
    // Each lazy row selects only its own playback status; no list-wide ticker.
    final selected = ref.watch(radioPlayerProvider.select(
      (state) => state.station?.id == station.id,
    ));
    final playing = ref.watch(radioPlayerProvider.select(
      (state) => state.station?.id == station.id && state.playing,
    ));
    final activeNow = ref.watch(radioPlayerProvider.select(
      (state) => state.station?.id == station.id
          ? state.nowPlaying : null,
    ));
    final now = activeNow ?? _broadcastTrack;
    final activeCover = ref.watch(radioPlayerProvider.select(
      (state) => state.station?.id == station.id ? state.trackMetadata?.cover : null,
    ));
    final songCover = activeCover ?? _broadcastCover;
    final fallback = ColoredBox(
      color: t.surface2,
      child: Icon(Icons.radio_rounded, color: t.muted, size: 22),
    );
    final quality = station.lossless
        ? station.codec + ' · Lossless'
        : station.codec + ' · ' + station.bitrate.toString() + ' kbps';
    return InkWell(
      onTap: () {
        final player = ref.read(radioPlayerProvider.notifier);
        if (selected) {
          unawaited(player.toggle());
        } else {
          unawaited(player.play(station));
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.square(
                dimension: 52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (songCover != null || station.icon != null)
                      Image.network(
                        songCover ?? station.icon!,
                        fit: BoxFit.cover,
                        cacheWidth: 156,
                        errorBuilder: (_, _, _) => station.icon != null &&
                            songCover != null
                            ? Image.network(station.icon!, fit: BoxFit.cover,
                                cacheWidth: 156,
                                errorBuilder: (_, _, _) => fallback)
                            : fallback,
                      )
                    else
                      fallback,
                    if (songCover != null && station.icon != null)
                      Positioned(
                        right: 0, bottom: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(station.icon!, width: 17,
                            height: 17, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(station.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? t.accent : t.text,
                    ),
                  ),
                  Text((now != null && now.isNotEmpty) ? now :
                      'Current track unavailable',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                  Text([quality, station.country].where((v) => v.isNotEmpty)
                      .join(' · '), maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: t.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
              onPressed: () => unawaited(
                ref.read(stationFavoritesProvider.notifier).toggle(station),
              ),
              icon: Icon(favorite ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
                color: favorite ? t.accent : t.muted),
            ),
            Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: selected ? t.accent : t.muted, size: 26),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingStation extends ConsumerWidget {
  const _NowPlayingStation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(radioPlayerProvider);
    final station = player.station;
    if (station == null) return const SizedBox.shrink();
    final t = context.lokal;
    final activeArt = player.trackMetadata?.cover ?? station.icon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            if (activeArt != null)
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Image.network(activeArt, width: 44, height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(Icons.graphic_eq_rounded,
                    color: t.accent)))
            else
              Icon(Icons.graphic_eq_rounded, color: t.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(station.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
                  Text(player.error ?? (player.loading ? 'Tuning in…' :
                    player.trackMetadata?.label ?? player.nowPlaying ??
                    (player.playing ? 'Live' : 'Paused')),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: player.error == null ? t.muted : t.red,
                      fontSize: 12)),
                  Text(station.lossless ? '${station.codec} · Lossless' :
                    '${station.codec} · ${station.bitrate} kbps',
                    style: TextStyle(fontSize: 11, color: t.muted)),
                ],
              ),
            ),
            if (player.loading)
              const Padding(padding: EdgeInsets.all(10),
                child: SizedBox.square(dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
            else
              IconButton(
                tooltip: player.playing ? 'Pause' : 'Play',
                onPressed: () => unawaited(
                  ref.read(radioPlayerProvider.notifier).toggle()),
                icon: Icon(player.playing ? Icons.pause_rounded :
                  Icons.play_arrow_rounded, color: t.accent),
              ),
            IconButton(
              tooltip: 'Stop station',
              onPressed: () => unawaited(
                ref.read(radioPlayerProvider.notifier).stop()),
              icon: Icon(Icons.stop_rounded, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}
