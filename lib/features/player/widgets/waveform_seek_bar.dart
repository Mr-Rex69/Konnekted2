import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/app_colors.dart';

import 'waveform_envelope.dart';

class WaveformSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration>? onChangeEnd;
  final double appearProgress;
  final List<double>? cachedPeaks;

  const WaveformSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onChanged,
    this.onChangeEnd,
    this.barCount = 60,
    this.appearProgress = 1.0,
    this.cachedPeaks,
  });

  final int barCount;

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  static const double _baseHeight = 60;
  static const double _expandedHeight = 96;
  static const double _fineScrubZoom = 2.6;

  // Cache the waveform data so it doesn't jitter on rebuilds
  late List<double> _waveformData;
  bool _isFineScrubbing = false;
  Duration? _interactivePosition;
  double _fineScrubAnchorDx = 0;
  Duration _fineScrubAnchorPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _generateWaveform();
  }

  @override
  void didUpdateWidget(WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final peaksChanged = widget.cachedPeaks != oldWidget.cachedPeaks;
    final durationChanged =
        widget.duration != oldWidget.duration ||
        widget.barCount != oldWidget.barCount;
    if ((durationChanged || peaksChanged) &&
        widget.duration.inMilliseconds > 0) {
      _generateWaveform();
    }
  }

  void _generateWaveform() {
    final peaks = widget.cachedPeaks;
    _waveformData =
        peaks != null &&
            peaks.length > 1 &&
            peaks.every((p) => p.isFinite && p >= 0)
        ? List<double>.unmodifiable(peaks)
        : const [];
  }

  Duration get _displayPosition => _interactivePosition ?? widget.position;

  Duration _positionFromDx(double dx, double width) {
    final progress = (dx / width).clamp(0.0, 1.0);
    final ms = (progress * widget.duration.inMilliseconds).round();
    return Duration(milliseconds: ms);
  }

  void _updateInteractivePosition(Duration position) {
    _interactivePosition = position;
  }

  void _onDragStart(DragStartDetails details) {
    // Optional: add visual feedback when dragging starts
  }

  void _onDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_isFineScrubbing) return;
    final width = constraints.maxWidth;
    final position = _positionFromDx(details.localPosition.dx, width);
    setState(() {
      _updateInteractivePosition(position);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final finalPosition = _displayPosition;
    if (_interactivePosition != null) {
      setState(() {
        _interactivePosition = null;
      });
    }
    widget.onChanged(finalPosition);
    if (widget.onChangeEnd != null) {
      widget.onChangeEnd!(finalPosition);
    }
  }

  void _onTapUp(TapUpDetails details, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final newPos = _positionFromDx(details.localPosition.dx, width);
    widget.onChanged(newPos);
    widget.onChangeEnd?.call(newPos);
  }

  void _onLongPressStart(
    LongPressStartDetails details,
    BoxConstraints constraints,
  ) {
    final anchorPosition = _positionFromDx(
      details.localPosition.dx,
      constraints.maxWidth,
    );
    setState(() {
      _isFineScrubbing = true;
      _fineScrubAnchorDx = details.localPosition.dx;
      _fineScrubAnchorPosition = anchorPosition;
      _updateInteractivePosition(anchorPosition);
    });
  }

  void _onLongPressMoveUpdate(
    LongPressMoveUpdateDetails details,
    BoxConstraints constraints,
  ) {
    final width = constraints.maxWidth;
    final anchorProgress = widget.duration.inMilliseconds == 0
        ? 0.0
        : _fineScrubAnchorPosition.inMilliseconds /
              widget.duration.inMilliseconds;
    final deltaProgress =
        (details.localPosition.dx - _fineScrubAnchorDx) /
        width /
        _fineScrubZoom;
    final progress = (anchorProgress + deltaProgress).clamp(0.0, 1.0);
    final nextPosition = Duration(
      milliseconds: (progress * widget.duration.inMilliseconds).round(),
    );

    setState(() {
      _updateInteractivePosition(nextPosition);
    });
  }

  void _endFineScrub() {
    final finalPosition = _displayPosition;
    if (!_isFineScrubbing && _interactivePosition == null) {
      return;
    }

    setState(() {
      _isFineScrubbing = false;
      _interactivePosition = null;
    });
    widget.onChanged(finalPosition);
    widget.onChangeEnd?.call(finalPosition);
  }

  double _timeIndicatorLeft(double maxWidth, double progress) {
    final effectiveWidth = maxWidth - 4;
    final rawLeft = 2 + effectiveWidth * progress;
    return (rawLeft - 25).clamp(0.0, maxWidth - 50);
  }

  Widget _buildTimeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _formatDuration(_displayPosition),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontFamily: 'GoogleSansFlex',
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isScrubbing = _isFineScrubbing || _interactivePosition != null;
        final progress = widget.duration.inMilliseconds == 0
            ? 0.0
            : _displayPosition.inMilliseconds / widget.duration.inMilliseconds;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: (details) =>
                  _onDragUpdate(details, constraints),
              onHorizontalDragEnd: _onDragEnd,
              onLongPressStart: (details) =>
                  _onLongPressStart(details, constraints),
              onLongPressMoveUpdate: (details) =>
                  _onLongPressMoveUpdate(details, constraints),
              onLongPressEnd: (_) => _endFineScrub(),
              onTapUp: (details) => _onTapUp(details, constraints),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppConstants.animationFast,
                curve: Curves.easeOutCubic,
                height: _isFineScrubbing ? _expandedHeight : _baseHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: _isFineScrubbing
                      ? AppColors.glassBackgroundStrong
                      : Colors.transparent,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: _isFineScrubbing ? 6 : 0,
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      waveformData: _waveformData,
                      position: _displayPosition,
                      duration: widget.duration,
                      color: AppColors.textTertiary.withValues(alpha: 0.3),
                      activeColor: AppColors.accent,
                      barCount: widget.barCount,
                      zoomFactor: _isFineScrubbing ? _fineScrubZoom : 1.0,
                      appearProgress: widget.appearProgress,
                    ),
                  ),
                ),
              ),
            ),
            if (isScrubbing)
              Positioned(
                top: -22,
                left: _timeIndicatorLeft(constraints.maxWidth, progress),
                child: _buildTimeIndicator(),
              ),
          ],
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Duration position;
  final Duration duration;
  final Color color;
  final Color activeColor;
  final int barCount;
  final double zoomFactor;
  final double appearProgress;

  _WaveformPainter({
    required this.waveformData,
    required this.position,
    required this.duration,
    required this.color,
    required this.activeColor,
    required this.barCount,
    required this.zoomFactor,
    required this.appearProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final window = 1 / zoomFactor;
    final start = zoomFactor <= 1
        ? 0.0
        : (progress - window / 2).clamp(0.0, max(0.0, 1.0 - window));
    if (waveformData.length < 2) {
      // Missing analysis is an ordinary timeline, never random fake audio.
      final line = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        line,
      );
      line.color = activeColor;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width * progress, size.height / 2),
        line,
      );
      return;
    }
    paintWaveformEnvelope(
      canvas,
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width,
        height: size.height * .72,
      ),
      peaks: waveformData,
      progress: progress,
      active: activeColor,
      inactive: color,
      start: start.toDouble(),
      end: start + window,
      reveal: appearProgress,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.position != position ||
      old.duration != duration ||
      old.waveformData != waveformData ||
      old.appearProgress != appearProgress ||
      old.zoomFactor != zoomFactor ||
      old.color != color ||
      old.activeColor != activeColor;
}
