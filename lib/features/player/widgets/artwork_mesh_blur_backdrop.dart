import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/album_art_service.dart';

/// Continuous mesh displacement normalized to the viewport size.
///
/// Only integer harmonics are permitted: identical position and first
/// derivative at phase 0 and 1 prevent the visible snap of a reset.
@visibleForTesting
Offset artworkMeshWaveOffset(double phase, double u, double v) {
  final t = phase * math.pi * 2;
  final x = math.sin(t + v * 5.1 + u * 2.3) +
      .48 * math.cos(2 * t + u * 5.4);
  final y = math.cos(2 * t + u * 4.6 + v * 2.1) +
      .42 * math.sin(3 * t + v * 5);
  return Offset(x * .055, y * .043);
}

/// Only repaint the ambient mesh at ~30 Hz in Performance Mode. The drift
/// controller continues running at its original speed, so the 26-second wave
/// stays continuous; Full mode still paints at the display refresh rate.
@visibleForTesting
bool artworkMeshNeedsFrame(Duration elapsed, Duration? previous,
    {required bool performanceMode}) {
  if (!performanceMode || previous == null || elapsed < previous) return true;
  return elapsed - previous >= const Duration(microseconds: 33333);
}

/// Whether artwork may be resolved while a player sheet is still opening.
/// Prewarmed textures are cheap to attach immediately; cache misses still
/// defer decoding until the sheet animation has settled.
@visibleForTesting
bool artworkMeshCanResolve({
  required bool prewarmOnly,
  required bool cached,
  required AnimationStatus? routeStatus,
}) =>
    prewarmOnly ||
    cached ||
    routeStatus == null ||
    routeStatus == AnimationStatus.completed;

/// Artwork-driven mesh blur. Preserves the contrasting color regions in the
/// cover instead of reducing the entire image to one dominant hue.
///
/// Each cover is blurred once at low resolution. Animation only deforms a
/// small image-shader mesh: no per-frame artwork decoding or full-screen blur.
class ArtworkMeshBlurBackdrop extends ConsumerStatefulWidget {
  const ArtworkMeshBlurBackdrop({
    super.key,
    required this.song,
    this.preserveArtworkContrast = false,
    this.prewarmOnly = false,
  });
  final Song song;
  /// Preserve cover color separation in the fullscreen reflection.
  final bool preserveArtworkContrast;
  /// Populate the shared texture cache without painting or animating a mesh.
  final bool prewarmOnly;

  @override
  ConsumerState<ArtworkMeshBlurBackdrop> createState() =>
      _ArtworkMeshBlurBackdropState();
}

class _ArtLayer {
  _ArtLayer(this.image, {this.from = 0, this.to = 1});
  final ui.Image image;
  double from;
  double to;
  double opacity(double t) => ui.lerpDouble(from, to, t)!;
  void dispose() => image.dispose();
}

class _ArtworkMeshBlurBackdropState
    extends ConsumerState<ArtworkMeshBlurBackdrop>
    with TickerProviderStateMixin {
  static const int _dimension = 224;
  // A rapid series of skips can overlap several one-second crossfades.
  // Keep the recent small (224px) textures alive until they fade out.
  static const _maxLayers = 5;
  static const _maxRecent = 5;
  static final Map<String, ui.Image> _recent = {};
  final ChangeNotifier _driftPaint = ChangeNotifier();
  Duration? _lastDriftPaint;
  bool _performanceMode = true;

  void _onDriftTick() {
    final elapsed = _drift.lastElapsedDuration;
    if (elapsed == null ||
        artworkMeshNeedsFrame(
          elapsed, _lastDriftPaint,
          performanceMode: _performanceMode &&
              LokalPerformanceAdvisor.samsungRasterMitigations,
        )) {
      _lastDriftPaint = elapsed;
      _driftPaint.notifyListeners();
    }
  }

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
    value: .15,
  )..addListener(_onDriftTick);
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
    value: 1,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _pruneLayers();
    });

  final List<_ArtLayer> _layers = [];
  ImageStream? _stream;
  ImageStreamListener? _streamListener;
  Animation<double>? _route;
  String? _requested;
  int _generation = 0;
  bool _ultraPerformance = false;
  bool _reduceMotion = false;

  String get _key => [
        widget.song.id,
        widget.song.albumArt,
        widget.song.filePath,
        widget.preserveArtworkContrast,
      ].join('|');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _route)) {
      _route?.removeStatusListener(_onRouteStatus);
      _route = animation;
      _route?.addStatusListener(_onRouteStatus);
    }
    // Attach prewarmed artwork during opening instead of showing a transient
    // palette fallback. Cold decoding is still deferred to protect FPS.
    if (artworkMeshCanResolve(
      prewarmOnly: widget.prewarmOnly,
      cached: _recent.containsKey(_key),
      routeStatus: _route?.status,
    )) {
      _resolve();
    }
    _syncMotion();
  }

  void _onRouteStatus(AnimationStatus status) {
    _syncMotion();
    if (status == AnimationStatus.completed) {
      // Never perform image decoding / setState during a route build frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _route?.status == AnimationStatus.completed) {
          _resolve();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ArtworkMeshBlurBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_key != [
      oldWidget.song.id,
      oldWidget.song.albumArt,
      oldWidget.song.filePath,
      oldWidget.preserveArtworkContrast,
    ].join('|') &&
        artworkMeshCanResolve(
          prewarmOnly: widget.prewarmOnly,
          cached: _recent.containsKey(_key),
          routeStatus: _route?.status,
        )) {
      _resolve();
    }
  }

  void _syncMotion([AnimationStatus? status]) {
    final settled = _route == null ||
        _route!.status == AnimationStatus.completed;
    if (widget.prewarmOnly || _ultraPerformance || _reduceMotion ||
        _layers.isEmpty || !TickerMode.of(context) || !settled) {
      _drift.stop(canceled: false);
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  void _unsubscribe() {
    if (_stream != null && _streamListener != null) {
      _stream!.removeListener(_streamListener!);
    }
    _stream = null;
    _streamListener = null;
  }

  void _resolve() {
    final key = _key;
    if (key == _requested) return;
    _requested = key;
    final generation = ++_generation;
    _unsubscribe();
    final cached = _recent.remove(key);
    if (cached != null) {
      _recent[key] = cached;
      _show(cached.clone(), immediateIfFirst: true);
      return;
    }
    unawaited(_load(key, generation));
  }

  Future<void> _load(String key, int generation) async {
    try {
      final song = widget.song;
      ImageProvider? provider;
      final artwork = song.albumArt;
      if (artwork != null &&
          (artwork.startsWith('https://') || artwork.startsWith('http://'))) {
        provider = NetworkImage(artwork);
      } else {
        String? path = artwork;
        if (song.filePath?.isNotEmpty == true) {
          path = await AlbumArtService.instance.resolveArtworkPath(
            existingPath: artwork,
            audioSourcePath: song.filePath!,
          );
        }
        if (path != null && await File(path).exists()) {
          provider = FileImage(File(path));
        }
      }
      if (!mounted || generation != _generation || provider == null) return;
      final thumbnail = ResizeImage.resizeIfNeeded(_dimension, null, provider);
      final stream = thumbnail.resolve(createLocalImageConfiguration(context));
      _stream = stream;
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        if (!mounted || generation != _generation) return;
        // Retain only our own image handle across asynchronous GPU work.
        final source = info.image.clone();
        _unsubscribe();
        unawaited(_prepare(source, key, generation));
      }, onError: (_, _) {
        if (generation == _generation) _unsubscribe();
        // Keep the outgoing art on transient download/decode errors.
      });
      _streamListener = listener;
      stream.addListener(listener);
    } catch (_) {
      // No art: the palette gradient below this layer remains available.
    }
  }

  Future<void> _prepare(ui.Image source, String key, int generation) async {
    ui.Image? result;
    try {
      // Preblur only 224x224 pixels, once per song. Overscan avoids a seam.
      final recorder = ui.PictureRecorder();
      final rect = Rect.fromLTWH(0, 0, _dimension.toDouble(), _dimension.toDouble());
      final canvas = Canvas(recorder, rect);
      canvas.saveLayer(
        rect,
        Paint()..imageFilter = ui.ImageFilter.blur(
          sigmaX: widget.preserveArtworkContrast ? 12 : 24,
          sigmaY: widget.preserveArtworkContrast ? 12 : 24,
          tileMode: ui.TileMode.clamp,
        ),
      );
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        rect.inflate(12),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      final picture = recorder.endRecording();
      try {
        result = await picture.toImage(_dimension, _dimension);
      } finally {
        picture.dispose();
      }
      if (!mounted || generation != _generation) return;
      _recent.remove(key)?.dispose();
      _recent[key] = result.clone();
      while (_recent.length > _maxRecent) {
        _recent.remove(_recent.keys.first)?.dispose();
      }
      _show(result);
      result = null; // now owned by the active layer
    } catch (_) {
      // Preserve the previous frame, never flash black on a failed decode.
    } finally {
      result?.dispose();
      source.dispose();
    }
  }

  void _show(ui.Image image, {bool immediateIfFirst = false}) {
    if (widget.prewarmOnly) {
      // _recent retains its own clone; invisible preloaders own no layers.
      image.dispose();
      return;
    }
    final firstLayer = _layers.isEmpty;
    final t = Curves.easeInOutCubic.transform(_fade.value);
    // When next/previous is pressed during an existing crossfade, continue
    // from every layer's *current* opacity rather than snapping to one cover.
    for (final layer in _layers) {
      layer.from = layer.opacity(t);
      layer.to = 0;
    }
    _layers.add(_ArtLayer(image));
    while (_layers.length > _maxLayers) {
      _layers.removeAt(0).dispose();
    }
    // Also fade in the first decoded artwork over the fallback palette;
    // otherwise its appearance pops immediately after the sheet settles.
    if ((firstLayer && immediateIfFirst) || _reduceMotion ||
        _ultraPerformance) {
      _fade.value = 1;
      _pruneLayers();
    } else {
      _fade.forward(from: 0);
    }
    if (mounted) {
      _syncMotion();
      // A first image or Ultra-mode transition may never tick the fade.
      _driftPaint.notifyListeners();
      setState(() {});
    }
  }

  void _pruneLayers() {
    if (_layers.isEmpty) return;
    while (_layers.length > 1) {
      _layers.removeAt(0).dispose();
    }
    _layers.first
      ..from = 1
      ..to = 1;
    if (mounted) {
      _driftPaint.notifyListeners();
      setState(() {});
    }
  }

  @override
  void dispose() {
    ++_generation;
    _unsubscribe();
    _route?.removeStatusListener(_onRouteStatus);
    _drift.dispose();
    _fade.dispose();
    _driftPaint.dispose();
    for (final layer in _layers) {
      layer.dispose();
    }
    _layers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.prewarmOnly) return const SizedBox.shrink();
    final appearance = ref.watch(lokalAppearanceProvider);
    // Regular Performance Mode keeps the ambient mesh alive; only Ultra
    // disables decorative animation. System reduced-motion is independent.
    _ultraPerformance = appearance.ultraPerformanceMode;
    if (_performanceMode != appearance.performanceMode) {
      _performanceMode = appearance.performanceMode;
      _lastDriftPaint = null;
    }
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ArtworkMeshPainter(
                repaint: Listenable.merge([_driftPaint, _fade]),
                layers: _layers,
                phase: () => _drift.value,
                transition: () => Curves.easeInOutCubic.transform(_fade.value),
              ),
            ),
            // Gentle contrast protection without tinting every region red.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x41000000),
                    Color(0x10000000),
                    Color(0x32000000),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkMeshPainter extends CustomPainter {
  _ArtworkMeshPainter({
    required Listenable repaint,
    required this.layers,
    required this.phase,
    required this.transition,
  }) : super(repaint: repaint);

  final List<_ArtLayer> layers;
  final double Function() phase;
  final double Function() transition;
  static const _columns = 8;
  static const _rows = 12;

  // Mesh topology does not change with the animation or viewport. Allocating
  // only animated positions avoids generating hundreds of temporary objects
  // and indices on each raster frame.
  static final List<Offset> _coordinates = [
    for (var y = 0; y <= _rows; y++)
      for (var x = 0; x <= _columns; x++)
        Offset(
          x / _columns * _ArtworkMeshBlurBackdropState._dimension,
          y / _rows * _ArtworkMeshBlurBackdropState._dimension,
        ),
  ];
  static final List<int> _indices = _meshIndices();
  static List<int> _meshIndices() {
    final indices = <int>[];
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _columns; x++) {
        final a = y * (_columns + 1) + x;
        final b = a + 1;
        final c = a + _columns + 1;
        indices.addAll([a, b, c, b, c + 1, c]);
      }
    }
    return indices;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || layers.isEmpty) return;
    final positions = <Offset>[];
    final frame = phase();
    // 18% overscan in both axes prevents gaps during mesh displacement.
    for (var y = 0; y <= _rows; y++) {
      for (var x = 0; x <= _columns; x++) {
        final u = x / _columns;
        final v = y / _rows;
        final baseX = (u * 1.36 - .18) * size.width;
        final baseY = (v * 1.36 - .18) * size.height;
        final wave = artworkMeshWaveOffset(frame, u, v);
        positions.add(Offset(
          baseX + wave.dx * size.width,
          baseY + wave.dy * size.height,
        ));
      }
    }
    final mesh = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: _coordinates,
      indices: _indices,
    );
    final matrix = Float64List(16);
    matrix[0] = matrix[5] = matrix[10] = matrix[15] = 1;
    final fade = transition();
    for (final layer in layers) {
      final opacity = layer.opacity(fade).clamp(0.0, 1.0);
      if (opacity < .002) continue;
      canvas.drawVertices(
        mesh,
        BlendMode.srcOver,
        Paint()
          ..shader = ui.ImageShader(
            layer.image,
            ui.TileMode.clamp,
            ui.TileMode.clamp,
            matrix,
            filterQuality: FilterQuality.medium,
          )
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: opacity),
            BlendMode.modulate,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_ArtworkMeshPainter oldDelegate) =>
      !identical(layers, oldDelegate.layers);
}
