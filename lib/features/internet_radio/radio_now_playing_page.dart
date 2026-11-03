import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/internet_radio/station_favorites.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The radio-specific counterpart of Lokal's full Now Playing screen.
/// A live station has no seekable duration or ordinary music queue.
class RadioNowPlayingPage extends ConsumerWidget {
  const RadioNowPlayingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioPlayerProvider);
    final station = radio.station;
    final t = context.lokal;
    if (station == null) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(title: const Text('Stations'), backgroundColor: t.bg),
        body: const Center(child: Text('No station playing')),
      );
    }

    final track = radio.trackMetadata;
    final image = track?.cover ?? station.icon;
    final title = track?.title ?? radio.nowPlaying ?? station.title;
    final artist = track?.artist.isNotEmpty == true
        ? track!.artist : station.title;
    final quality = station.lossless
        ? station.codec + ' · Lossless'
        : station.codec + ' · ' + station.bitrate.toString() + ' kbps';
    final favorite = ref.watch(stationFavoritesProvider)
        .containsKey(station.id);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: const Text('Now Playing'),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: image != null
                          ? Image.network(image, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _RadioArtworkFallback(
                                icon: station.icon))
                          : _RadioArtworkFallback(icon: station.icon),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 26, color: t.text,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(artist, textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: t.muted)),
                  const SizedBox(height: 10),
                  Text(station.title + ' · LIVE', style: TextStyle(
                    color: t.accent, fontSize: 13,
                    fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(quality, style: TextStyle(
                    color: t.muted, fontSize: 13)),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: favorite ? 'Remove favorite station'
                            : 'Favorite station',
                        onPressed: () => unawaited(ref
                            .read(stationFavoritesProvider.notifier)
                            .toggle(station)),
                        icon: Icon(favorite ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                          color: favorite ? t.accent : t.text, size: 27),
                      ),
                      const SizedBox(width: 22),
                      if (radio.loading)
                        const SizedBox.square(dimension: 60,
                            child: CircularProgressIndicator())
                      else
                        FilledButton(
                          onPressed: () => unawaited(
                            ref.read(radioPlayerProvider.notifier).toggle()),
                          style: FilledButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: t.bg,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(20)),
                          child: Icon(radio.playing
                              ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 32),
                        ),
                      const SizedBox(width: 22),
                      IconButton(
                        tooltip: 'Stop station',
                        onPressed: () {
                          unawaited(ref.read(radioPlayerProvider.notifier).stop());
                          Navigator.of(context).maybePop();
                        },
                        icon: Icon(Icons.stop_rounded,
                          color: t.text, size: 28),
                      ),
                    ],
                  ),
                  if (radio.error != null) ...[
                    const SizedBox(height: 18),
                    Text(radio.error!, textAlign: TextAlign.center,
                      style: TextStyle(color: t.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioArtworkFallback extends StatelessWidget {
  const _RadioArtworkFallback({this.icon});
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return ColoredBox(
      color: t.surface2,
      child: icon == null
          ? Center(child: Icon(Icons.radio_rounded, size: 94, color: t.muted))
          : Image.network(icon!, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Icon(Icons.radio_rounded, size: 94, color: t.muted))),
    );
  }
}
