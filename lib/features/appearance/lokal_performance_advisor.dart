import 'dart:async';
import 'dart:io' show ProcessInfo;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/lokal_appearance.dart';
import '../../core/utils/app_log.dart';
import '../../l10n/l10n.dart';


/// Aggregated frame timing, recorded only during navigation. The entries are
/// logged every 15 seconds and reset, never persisted between app sessions.
class _NavigationFrameWindow {
  int frames = 0;
  int uiMisses = 0;
  int rasterMisses = 0;
}

/// FrameTiming timestamps use Flutter's raw engine epoch, not DateTime's
/// Unix epoch. Retain activity transitions in that same clock so delayed
/// release-mode batches are assigned to the original page and gesture.
class _FrameActivity {
  const _FrameActivity(this.since, this.until, this.kind, this.surface);

  final int since;
  final int until;
  final String kind;
  final String surface;
}

/// Distinguish CPU-heavy rasterization from UI work in release diagnostics.
@visibleForTesting
String lokalFrameBottleneck(int frames, int slowUi, int slowRaster) {
  if (frames == 0) return 'no-frames';
  if (slowUi == 0 && slowRaster == 0) return 'none';
  if (slowUi > slowRaster * 2) return 'ui';
  if (slowRaster > slowUi * 2) return 'raster';
  return 'mixed';
}

/// Suggests once after the first foreground minutes. Lightweight diagnostics
/// continue for later hangs; background samples are discarded.
class LokalPerformanceAdvisor extends ConsumerStatefulWidget {
  const LokalPerformanceAdvisor({super.key, required this.child});
  final Widget child;
  static int lastGlassPaintMicros = 0;

  /// UI-quality tradeoffs are limited to the Samsung models with confirmed
  /// stutter reports; unrelated devices retain their animation cadence.
  /// Generic resource savings (e.g. cached geometry) remain universal.
  static bool samsungRasterMitigations = false;

  @visibleForTesting
  static bool affectedSamsungModel(String manufacturer, String model) {
    if (manufacturer.trim().toLowerCase() != 'samsung') return false;
    final id = model.trim().toUpperCase();
    return id.startsWith('SM-S938') || // Galaxy S25 Ultra
        id.startsWith('SM-M055') || // Galaxy M05
        id.startsWith('SM-M066') || // model seen in supplied M05 logs
        id == 'GALAXY S25 ULTRA' || id == 'GALAXY M05';
  }
  // Only the outer player screens register; internal lyrics/queue widgets
  // do not affect attribution. These flags are local to the diagnostics.
  static final List<String> _activePlayerSurfaces = [];
  static void enterPlayerSurface(String surface) {
    _activePlayerSurfaces.remove(surface);
    _activePlayerSurfaces.add(surface);
  }
  static void exitPlayerSurface(String surface) {
    _activePlayerSurfaces.remove(surface);
  }
  static String get diagnosticSurface => _activePlayerSurfaces.isEmpty
      ? 'browse' : _activePlayerSurfaces.last;

  // The previous performance snapshots mixed idle frames, list flings and
  // page navigation into a single rasterMiss total. Attribute frame samples
  // to the last interaction for M05 diagnostics without adding per-frame
  // platform-channel calls or logging any private content.
  static int _scrollUntilMicros = 0, _navigationUntilMicros = 0;
  static String _navigationSurface = 'other', _scrollSurface = 'other';
  static final List<_FrameActivity> _frameActivities = [];

  static void _recordActivity(String kind, String surface, int duration) {
    // This unadjusted frame stamp shares its epoch with
    // FrameTiming.timestampInMicroseconds(FramePhase.buildStart). A note
    // between frames applies to the following frame, not the previous one.
    final started =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds + 1;
    final previous = _frameActivities.isEmpty ? null : _frameActivities.last;
    if (previous != null &&
        previous.kind == kind &&
        previous.surface == surface &&
        started <= previous.until) {
      _frameActivities[_frameActivities.length - 1] =
          _FrameActivity(previous.since, started + duration, kind, surface);
    } else {
      _frameActivities.add(
        _FrameActivity(started, started + duration, kind, surface),
      );
      // Release-mode frame reports can be delayed by roughly a second.
      // Preserve ample history but never accumulate an unbounded list.
      if (_frameActivities.length > 128) {
        _frameActivities.removeRange(0, _frameActivities.length - 96);
      }
    }
  }

  /// Look up the activity at frame-build time, not at callback delivery.
  /// Navigation overrides an earlier scroll even if its timeout was active.
  @visibleForTesting
  static (String kind, String surface) activityForRawFrame(int timestamp) {
    for (final activity in _frameActivities.reversed) {
      if (timestamp >= activity.since) {
        if (timestamp < activity.until) {
          return (activity.kind, activity.surface);
        }
        return ('idle', 'other');
      }
    }
    return ('idle', 'other');
  }

  static void noteScroll({String surface = 'other'}) {
    _scrollSurface = surface;
    _scrollUntilMicros = DateTime.now().microsecondsSinceEpoch + 500000;
    _recordActivity('scroll', surface, 500000);
  }
  static String get scrollSurface => _scrollSurface;
  static void noteNavigation({String surface = 'other'}) {
    _navigationSurface = surface;
    // A new page supersedes the old page's active scroll immediately.
    _scrollUntilMicros = 0;
    _navigationUntilMicros = DateTime.now().microsecondsSinceEpoch + 1000000;
    _recordActivity('navigation', surface, 1000000);
  }
  static String get navigationSurface => _navigationSurface;
  static String get diagnosticActivity {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now < _scrollUntilMicros) return 'scroll';
    if (now < _navigationUntilMicros) return 'navigation';
    return 'idle';
  }
  @override
  ConsumerState<LokalPerformanceAdvisor> createState() =>
      _LokalPerformanceAdvisorState();
}

class _LokalPerformanceAdvisorState
    extends ConsumerState<LokalPerformanceAdvisor>
    with WidgetsBindingObserver {
  static const _seenKey = 'lokal.performance_suggestion_shown.v1';
  int _frames = 0, _missed = 0;
  bool _foreground = true, _seen = true, _suggesting = false;
  Timer? _timer;
  Timer? _diagnosticTimer;
  static const _diagnostics = MethodChannel('com.mossapps.flick/diagnostics');
  int _windowFrames = 0, _windowUiMisses = 0, _windowRasterMisses = 0;
  int _maxUiMicros = 0, _maxRasterMicros = 0;
  int _scrollFrames = 0, _scrollRasterMisses = 0;
  int _navigationFrames = 0, _navigationRasterMisses = 0;
  final Map<String, _NavigationFrameWindow> _navigationWindows = {};
  final Map<String, _NavigationFrameWindow> _scrollWindows = {};
  int? _previousCpuMs, _previousWallMs;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _seen = prefs.getBool(_seenKey) ?? false;
    // Even if the banner was dismissed and even in Ultra mode we must
    // measure: the Galaxy S25 Ultra report persists in Ultra mode, and the
    // original advisor silently stopped counting these frames.
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _timer = Timer(const Duration(minutes: 2), _finish);
    _diagnosticTimer = Timer.periodic(
      const Duration(seconds: 15), (_) => unawaited(_logPerformance()),
    );
    unawaited(_logPerformance());
  }

  void _timings(List<FrameTiming> values) {
    if (!_foreground || !mounted) return;
    final rate = View.of(context).display.refreshRate;
    final budget = 1000000 / (rate > 0 ? rate : 60);
    final maySuggest = _timer != null && !_seen &&
        !ref.read(lokalAppearanceProvider).performanceMode &&
        DateTime.now().microsecondsSinceEpoch -
                LokalPerformanceAdvisor.lastGlassPaintMicros <=
            500000;
    for (final frame in values) {
      if (frame.buildDuration.inMicroseconds > _maxUiMicros) {
        _maxUiMicros = frame.buildDuration.inMicroseconds;
      }
      if (frame.rasterDuration.inMicroseconds > _maxRasterMicros) {
        _maxRasterMicros = frame.rasterDuration.inMicroseconds;
      }
      final slowUi = frame.buildDuration.inMicroseconds > budget;
      final slowRaster = frame.rasterDuration.inMicroseconds > budget;
      _windowFrames++;
      if (slowUi) _windowUiMisses++;
      if (slowRaster) _windowRasterMisses++;
      final activity = LokalPerformanceAdvisor.activityForRawFrame(
        frame.timestampInMicroseconds(FramePhase.buildStart),
      );
      switch (activity.kind) {
        case 'scroll':
          _scrollFrames++;
          if (slowRaster) _scrollRasterMisses++;
          final scrollWindow = _scrollWindows.putIfAbsent(
            activity.surface,
            _NavigationFrameWindow.new,
          );
          scrollWindow.frames++;
          if (slowUi) scrollWindow.uiMisses++;
          if (slowRaster) scrollWindow.rasterMisses++;
        case 'navigation':
          _navigationFrames++;
          if (slowRaster) _navigationRasterMisses++;
          final window = _navigationWindows.putIfAbsent(
            activity.surface,
            _NavigationFrameWindow.new,
          );
          window.frames++;
          if (slowUi) window.uiMisses++;
          if (slowRaster) window.rasterMisses++;
      }
      if (maySuggest) {
        _frames++;
        if (slowUi || slowRaster) _missed++;
      }
    }
  }

  Future<void> _logPerformance() async {
    if (!mounted) return;
    if (!_foreground) {
      _previousCpuMs = null;
      _previousWallMs = null;
      _windowFrames = _windowUiMisses = _windowRasterMisses = 0;
      _maxUiMicros = _maxRasterMicros = 0;
      _scrollFrames = _scrollRasterMisses = 0;
      _navigationFrames = _navigationRasterMisses = 0;
      _navigationWindows.clear();
      _scrollWindows.clear();
      return;
    }
    try {
      final snapshot = await _diagnostics.invokeMapMethod<String, dynamic>(
        'getPerformanceSnapshot',
      );
      if (!mounted || !_foreground || snapshot == null) return;
      LokalPerformanceAdvisor.samsungRasterMitigations =
          LokalPerformanceAdvisor.affectedSamsungModel(
        snapshot['manufacturer']?.toString() ?? '',
        snapshot['model']?.toString() ?? '',
      );
      final cpu = (snapshot['cpuMs'] as num?)?.toInt();
      if (cpu == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = _previousWallMs == null ? 0 : now - _previousWallMs!;
      if (elapsed > 0 && _previousCpuMs != null) {
        final cpuCores = (cpu - _previousCpuMs!) / elapsed;
        final fps = _windowFrames * 1000 / elapsed;
        final frames = _windowFrames;
        final ui = _windowUiMisses;
        final raster = _windowRasterMisses;
        final appearance = ref.read(lokalAppearanceProvider);
        final mode = appearance.ultraPerformanceMode
            ? 'ultra'
            : appearance.performanceMode ? 'performance' : 'normal';
        final rssMb = ProcessInfo.currentRss ~/ (1024 * 1024);
        final scrollBySurface = _scrollWindows.entries.map(
          (entry) => '${entry.key}:${entry.value.frames}/'
              '${entry.value.uiMisses}/${entry.value.rasterMisses}',
        ).join(',');
        final navBySurface = _navigationWindows.entries.map(
          (entry) => '${entry.key}:${entry.value.frames}/'
              '${entry.value.uiMisses}/${entry.value.rasterMisses}',
        ).join(',');
        AppLog.instance.add(
          '[perf] ${snapshot['manufacturer']} ${snapshot['model']} '
          'sdk=${snapshot['sdk']} impellerRequested=${snapshot['impellerRequested']} '
          'frames=$frames fps=${fps.toStringAsFixed(1)} '
          'windowMs=$elapsed maxUiMs=${(_maxUiMicros / 1000).toStringAsFixed(1)} '
          'maxRasterMs=${(_maxRasterMicros / 1000).toStringAsFixed(1)} '
          'uiMiss=$ui rasterMiss=$raster '
          'suspect=${lokalFrameBottleneck(frames, ui, raster)} '
          'processCpuCores=${cpuCores.toStringAsFixed(2)} '
          'mode=$mode rssMb=$rssMb '
          'surface=${LokalPerformanceAdvisor.diagnosticSurface} '
          'scrollRaster=$_scrollRasterMisses/$_scrollFrames '
          'scrollFramesUiRaster=$scrollBySurface '
          'navigationRaster=$_navigationRasterMisses/$_navigationFrames '
          'navFramesUiRaster=$navBySurface',
          source: LogSource.platform,
        );
      }
      _previousCpuMs = cpu;
      _previousWallMs = now;
      _windowFrames = _windowUiMisses = _windowRasterMisses = 0;
      _maxUiMicros = _maxRasterMicros = 0;
      _scrollFrames = _scrollRasterMisses = 0;
      _navigationFrames = _navigationRasterMisses = 0;
      _navigationWindows.clear();
      _scrollWindows.clear();
    } catch (_) {
      // Perf telemetry must never interfere with startup or the audio path.
    }
  }

  Future<void> _finish() async {
    // Only the suggestion window ends here. The reported occasional hangs
    // can happen after two minutes, so keep the foreground counters alive.
    _timer = null;
    if (!mounted ||
        _seen ||
        _frames < 120 ||
        _missed / _frames < 0.12 ||
        ref.read(lokalAppearanceProvider).performanceMode)
      return;
    // Mark before showing: lifecycle changes cannot produce a second prompt.
    _seen = true;
    await (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    if (!mounted || !_foreground || _suggesting) return;
    _suggesting = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          lokalText(
            "{arg0}\n{arg1}",
            args: {
              'arg0': l10n.linkPerformanceTitle,
              'arg1': l10n.linkPerformanceBody,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(l10n.linkNotNow),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(
                ref
                    .read(lokalAppearanceProvider.notifier)
                    .setPerformanceMode(true),
              );
            },
            child: Text(l10n.linkEnablePerformance),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _previousCpuMs = _previousWallMs = null;
      _windowFrames = _windowUiMisses = _windowRasterMisses = 0;
      _maxUiMicros = _maxRasterMicros = 0;
      _scrollFrames = _scrollRasterMisses = 0;
      _navigationFrames = _navigationRasterMisses = 0;
      _navigationWindows.clear();
      _scrollWindows.clear();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _diagnosticTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
