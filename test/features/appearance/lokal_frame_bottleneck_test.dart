import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';

void main() {
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
