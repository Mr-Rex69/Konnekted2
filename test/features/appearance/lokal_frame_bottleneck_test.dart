import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';

void main() {
  test('delayed frame timings use original page and navigation overrides scroll',
      () {
    // Raw FrameTiming timestamps and the engine's system frame stamp share
    // an epoch; Unix DateTime timestamps do not.
    final rawStart =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds + 1;
    LokalPerformanceAdvisor.noteScroll(surface: 'Library');
    expect(
      LokalPerformanceAdvisor.activityForRawFrame(rawStart),
      (kind: 'scroll', surface: 'Library'),
    );

    LokalPerformanceAdvisor.noteNavigation(surface: 'You');
    expect(
      LokalPerformanceAdvisor.activityForRawFrame(rawStart),
      (kind: 'navigation', surface: 'You'),
    );
    expect(
      LokalPerformanceAdvisor.activityForRawFrame(rawStart + 1000001),
      (kind: 'idle', surface: 'other'),
    );
  });

  test('scroll frame diagnostics identify the active tab', () {
    LokalPerformanceAdvisor.noteScroll(surface: 'Library');
    expect(LokalPerformanceAdvisor.scrollSurface, 'Library');
    LokalPerformanceAdvisor.noteScroll(surface: 'You');
    expect(LokalPerformanceAdvisor.scrollSurface, 'You');
  });

  test('classify UI vs raster and completely stalled rendering separately', () {
    expect(lokalFrameBottleneck(0, 0, 0), 'no-frames');
    expect(lokalFrameBottleneck(120, 0, 0), 'none');
    expect(lokalFrameBottleneck(120, 70, 2), 'ui');
    expect(lokalFrameBottleneck(120, 5, 70), 'raster');
    expect(lokalFrameBottleneck(120, 30, 45), 'mixed');
  });
}
