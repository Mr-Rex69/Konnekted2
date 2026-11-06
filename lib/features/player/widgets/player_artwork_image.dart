import 'package:flick/core/theme/lokal_performance_scope.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/models/song.dart';
import 'package:flick/features/discovery/discovery_artwork.dart'
    show DiscoveryArtworkKind, DiscoveryArtworkRequest,
         discoveryImageUrl, discoveryLocalArtworkProvider,
         sharedDiscoveryArtworkResolver;
import 'package:flick/services/album_art_service.dart';
import 'package:flick/widgets/common/flick_artwork_placeholder.dart';
import 'player_artwork_quality.dart';

/// Only streaming and pending online tracks use a catalogue lookup when the
/// full player's original artwork URL is missing or fails to decode.
@visibleForTesting
bool shouldRecoverOnlineArtwork(Song song) =>
    song.isPending ||
    (song.sourcePackage?.startsWith('konnekted.') ?? false);

/// Amazon's streamed artwork is usually a small catalogue thumbnail. Always
/// prefer an independently matched Deezer/iTunes/YouTube sleeve in the full
/// player, even if that Amazon thumbnail loads without an error.
@visibleForTesting
bool shouldPreferIndependentAmazonArtwork(Song song) =>
    shouldRecoverOnlineArtwork(song) &&
    RegExp(r'^amazon(?:\b|[-_])', caseSensitive: false)
        .hasMatch(song.sourceDisplayName?.trim() ?? '');

/// Holds decoded frames through a cover change. Painting RawImage avoids a
/// second asynchronous image resolution when a carousel stage changes slots.
class PlayerArtworkImage extends StatefulWidget {
  const PlayerArtworkImage({
    super.key,
    required this.song,
    this.radius = 28,
    this.decodeWidth = 1024,
    this.placeholder,
    this.crossfade = true,
    this.onArtworkRecovered,
  });
  final Song song;
  final double radius;
  final int decodeWidth;
  final Widget? placeholder;
  final bool crossfade;
  /// Called only after an alternative catalogue image has decoded successfully.
  final ValueChanged<String>? onArtworkRecovered;

  @override
  State<PlayerArtworkImage> createState() => _PlayerArtworkImageState();
}

class _PlayerArtworkImageState extends State<PlayerArtworkImage>
    with SingleTickerProviderStateMixin {
  // Previous/next carousel stages may be disposed and recreated during a
  // playlist commit. Keep a bounded set of decoded frames across those
  // remounts so the incoming sleeve never flashes a placeholder.
  static final Map<String, ImageInfo> _recentFrames = {};
  static const int _maxRecentFrames = 4;
  // A recovered catalogue URL is already independent of Amazon. After Now
  // Playing adopts it, don't run a second lookup excluding that same image.
  static final Map<String, String> _amazonIndependentArtwork = {};

  static void _rememberFrame(String key, ImageInfo info) {
    _recentFrames.remove(key)?.dispose();
    _recentFrames[key] = info.clone();
    while (_recentFrames.length > _maxRecentFrames) {
      _recentFrames.remove(_recentFrames.keys.first)?.dispose();
    }
  }

  late final _fade =
      AnimationController(
        vsync: this,
        value: 1,
        duration: const Duration(milliseconds: 420),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _previous?.dispose();
            _previous = null;
          });
        }
      });
  ImageInfo? _shown, _previous;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _shownKey, _requested;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
    if (MediaQuery.disableAnimationsOf(context)) _fade.value = 1;
  }

  @override
  void didUpdateWidget(PlayerArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _unsubscribe() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  Future<void> _resolve() async {
    final song = widget.song;
    final decodeWidth = LokalPerformanceScope.of(context)
        ? widget.decodeWidth.clamp(64, 768)
        : widget.decodeWidth;
    final amazonIdentity = '${song.id}|${song.sourcePackage ?? ''}';
    final verifiedAmazonCover = _amazonIndependentArtwork[amazonIdentity];
    final preferAmazonIndependent = shouldPreferIndependentAmazonArtwork(song) &&
        (verifiedAmazonCover == null || verifiedAmazonCover != song.albumArt);
    var amazonLookupAttempted = false;
    // Include the source-quality policy in the retained-frame identity. A
    // low-resolution poster cached before this upgrade must not be reused.
    final key = '${song.id}|${song.albumArt}|${song.filePath}|${decodeWidth}|full-res-v1';
    if (_requested == key) return;
    _requested = key;
    final cached = _recentFrames.remove(key);
    if (cached != null) {
      _recentFrames[key] = cached;
      _shown?.dispose();
      _previous?.dispose();
      _previous = null;
      _shown = cached.clone();
      _shownKey = key;
      _fade.value = 1;
    }
    final generation = ++_generation;
    _unsubscribe();
    try {
      final sources = <ImageProvider>[];
      var path = song.albumArt;
      if (path?.startsWith('http://') == true ||
          path?.startsWith('https://') == true) {
        // Prefer the provider's original-size sleeve, but always try the
        // original thumbnail before starting a catalogue fallback.
        for (final url in PlayerArtworkQuality.candidates(path)) {
          sources.add(NetworkImage(url));
        }
      } else {
        if (song.filePath?.isNotEmpty == true &&
            song.sourcePackage != 'konnekted.progressive' &&
            song.sourcePackage != 'konnekted.morneye-live') {
          try {
            path = await AlbumArtService.instance.resolveArtworkPath(
              existingPath: path,
              audioSourcePath: song.filePath!,
            );
          } catch (_) {
            // A damaged audio-tag read must not block the online metadata
            // fallback. Streaming handles are never local artwork files.
            path = null;
          }
        }
        if (path != null && await File(path).exists()) {
          sources.add(FileImage(File(path)));
        }
      }
      if (!mounted || generation != _generation) return;

      late void Function() tryFallback;
      late void Function() tryRemoteFallback;
      void resolveCandidate(
        List<ImageProvider> candidates,
        int index, {
        String? recoveredArtwork,
        bool remoteAfterFailure = false,
        bool independentAmazonCandidate = false,
      }) {
        if (!mounted || generation != _generation) return;
        _unsubscribe();
        final provider = ResizeImage.resizeIfNeeded(
          decodeWidth,
          null,
          candidates[index],
        );
        final stream = provider.resolve(createLocalImageConfiguration(context));
        _stream = stream;
        final listener = ImageStreamListener(
          (info, _) {
            if (!mounted || generation != _generation) {
              info.dispose();
              return;
            }
            // HTTP 200 may return a tiny placeholder even for a 1200px URL.
            // Prefer a genuinely usable independent catalogue cover.
            if (independentAmazonCandidate &&
                (info.image.width < 300 || info.image.height < 300)) {
              info.dispose();
              if (index + 1 < candidates.length) {
                resolveCandidate(
                  candidates, index + 1,
                  recoveredArtwork: recoveredArtwork,
                  independentAmazonCandidate: true,
                );
              } else if (sources.isNotEmpty) {
                resolveCandidate(sources, 0);
              } else {
                tryFallback();
              }
              return;
            }
            if (independentAmazonCandidate && recoveredArtwork != null) {
              _amazonIndependentArtwork[amazonIdentity] = recoveredArtwork;
              if (_amazonIndependentArtwork.length > 150) {
                _amazonIndependentArtwork.remove(
                    _amazonIndependentArtwork.keys.first);
              }
            }
            _showFrame(info, key);
            if (recoveredArtwork != null) {
              // Also update Now Playing, the mini-player, blur backdrop, queue
              // and notification; a recovered full-player image must not be
              // restricted to this single widget.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && generation == _generation) {
                  widget.onArtworkRecovered?.call(recoveredArtwork);
                }
              });
            }
          },
          onError: (_, _) {
            if (!mounted || generation != _generation) return;
            if (index + 1 < candidates.length) {
              resolveCandidate(
                candidates, index + 1,
                recoveredArtwork: recoveredArtwork,
                remoteAfterFailure: remoteAfterFailure,
                independentAmazonCandidate: independentAmazonCandidate,
              );
            } else if (independentAmazonCandidate) {
              // A failed catalogue rendition must not discard a working Amazon
              // cover; treat it as the last-resort fallback.
              if (sources.isNotEmpty) {
                resolveCandidate(sources, 0);
              } else {
                tryFallback();
              }
            } else if (remoteAfterFailure) {
              // Match Search: if its local-library art was itself broken,
              // continue to the independent Deezer/iTunes metadata lookup.
              tryRemoteFallback();
            } else if (recoveredArtwork == null) {
              tryFallback();
            } else {
              _showFrame(null, key);
            }
          },
        );
        _listener = listener;
        stream.addListener(listener);
      }

      final artworkRequest = DiscoveryArtworkRequest(
        kind: DiscoveryArtworkKind.track,
        title: song.title,
        artist: song.artist,
        exclude: discoveryImageUrl(song.albumArt),
      );

      tryRemoteFallback = () {
        if (preferAmazonIndependent && amazonLookupAttempted) {
          _showFrame(null, key);
          return;
        }
        if (preferAmazonIndependent) amazonLookupAttempted = true;
        unawaited(() async {
          try {
            final found = await sharedDiscoveryArtworkResolver
                .resolve(artworkRequest)
                .timeout(const Duration(seconds: 6), onTimeout: () => '');
            if (!mounted || generation != _generation) return;
            var cover = discoveryImageUrl(found);
            // Amazon may credit the recording differently from Deezer/iTunes.
            // On an exact song-lookup miss, match its album independently
            // before accepting the add-on's smaller thumbnail.
            final albumTitle = song.album?.trim() ?? '';
            if (preferAmazonIndependent &&
                (cover.isEmpty || cover == song.albumArt) &&
                albumTitle.isNotEmpty) {
              final albumFound = await sharedDiscoveryArtworkResolver
                  .resolve(DiscoveryArtworkRequest(
                    kind: DiscoveryArtworkKind.album,
                    title: albumTitle,
                    artist: (song.albumArtist?.trim().isNotEmpty ?? false)
                        ? song.albumArtist!.trim() : song.artist,
                    exclude: discoveryImageUrl(song.albumArt),
                  ))
                  .timeout(const Duration(seconds: 6), onTimeout: () => '');
              if (!mounted || generation != _generation) return;
              cover = discoveryImageUrl(albumFound);
            }
            if (cover.isEmpty || cover == song.albumArt) {
              if (preferAmazonIndependent && sources.isNotEmpty) {
                resolveCandidate(sources, 0);
              } else if (preferAmazonIndependent) {
                tryFallback();
              } else {
                _showFrame(null, key);
              }
              return;
            }
            resolveCandidate(
              [for (final url in PlayerArtworkQuality.candidates(cover))
                NetworkImage(url)],
              0,
              recoveredArtwork: cover,
              independentAmazonCandidate: preferAmazonIndependent,
            );
          } catch (_) {
            if (!mounted || generation != _generation) return;
            if (preferAmazonIndependent && sources.isNotEmpty) {
              resolveCandidate(sources, 0);
            } else if (preferAmazonIndependent) {
              tryFallback();
            } else {
              _showFrame(null, key);
            }
          }
        }());
      };

      tryFallback = () {
        // Search can show a local-library match or an online catalogue match
        // when a LastWave image is missing/broken. Reproduce that exact order
        // rather than leaving the full player at a permanent placeholder.
        if (!shouldRecoverOnlineArtwork(song) ||
            song.title.trim().isEmpty ||
            song.artist.trim().isEmpty ||
            song.artist == 'Artist not supplied') {
          _showFrame(null, key);
          return;
        }

        String? localCover;
        try {
          localCover = ProviderScope.containerOf(context, listen: false)
              .read(discoveryLocalArtworkProvider)
              .lookup(artworkRequest);
        } catch (_) {
          // An unavailable library index must not prevent online recovery.
        }
        if (localCover != null && localCover.isNotEmpty &&
            localCover != song.albumArt) {
          final candidates = <ImageProvider>[];
          if (localCover.startsWith('https://')) {
            for (final url in PlayerArtworkQuality.candidates(localCover)) {
              candidates.add(NetworkImage(url));
            }
          } else if (File(localCover).existsSync()) {
            candidates.add(FileImage(File(localCover)));
          }
          if (candidates.isNotEmpty) {
            resolveCandidate(
              candidates, 0,
              recoveredArtwork: localCover,
              remoteAfterFailure: true,
            );
            return;
          }
        }
        tryRemoteFallback();
      };

      if (preferAmazonIndependent) {
        // Systematic primary lookup. Never gate this on a broken or low-res
        // Amazon URL; the addon candidates are only an error fallback.
        tryRemoteFallback();
      } else if (sources.isEmpty) {
        tryFallback();
      } else {
        resolveCandidate(sources, 0);
      }
    } catch (_) {
      if (mounted && generation == _generation) _showFrame(null, key);
    }
  }

  void _showFrame(ImageInfo? frame, String key) {
    final animate =
        widget.crossfade &&
        _shown != null &&
        frame != null &&
        _shownKey != key &&
        !MediaQuery.disableAnimationsOf(context);
    // A transient missing/failed new source must not erase the previous
    // decoded sleeve while the carousel and source resolver settle.
    if (frame == null && _shown != null) return;
    _fade.stop();
    setState(() {
      _previous?.dispose();
      _previous = animate ? _shown : null;
      if (!animate) _shown?.dispose();
      _shown = frame;
      _shownKey = key;
    });
    if (frame != null) _rememberFrame(key, frame);
    if (animate) {
      _fade.forward(from: 0);
    } else {
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _generation++;
    _unsubscribe();
    _fade.dispose();
    _shown?.dispose();
    _previous?.dispose();
    super.dispose();
  }

  Widget _image(ImageInfo info) => RawImage(
    image: info.image,
    scale: info.scale,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: _fade,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          if (_previous != null) _image(_previous!),
          if (_shown == null)
            widget.placeholder ?? const FlickArtworkPlaceholder()
          else
            Opacity(
              opacity: Curves.easeInOutCubic.transform(_fade.value),
              child: _image(_shown!),
            ),
        ],
      ),
    ),
  );
}
