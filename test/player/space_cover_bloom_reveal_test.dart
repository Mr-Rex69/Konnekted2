import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/space_cover_bloom_reveal.dart';
import 'package:flick/features/player/widgets/player_panel_stage.dart';

void main() {
  const viewport = Size(430, 930);
  const artwork = Rect.fromLTWH(24, 175, 380, 380);

  test('Space expands outward from every cover edge, not vertically', () {
    final start = spaceCoverBloomBounds(viewport, artwork, 0);
    final mid = spaceCoverBloomBounds(viewport, artwork, .5);
    final end = spaceCoverBloomBounds(viewport, artwork, 1);
    expect(start, artwork.inflate(2));
    expect(mid.top, lessThan(start.top));
    expect(mid.bottom, greaterThan(start.bottom));
    expect(mid.left, lessThan(start.left));
    expect(mid.right, greaterThan(start.right));
    expect(end.top, lessThan(0));
    expect(end.left, lessThan(0));
    expect(end.bottom, greaterThan(viewport.height));
    expect(end.right, greaterThan(viewport.width));
  });

  test('frost never covers the normal 20px-radius album corners', () {
    final cover = spaceCoverRevealAnchor(viewport, coverRect: artwork);
    expect(cover, artwork);
    for (final progress in [.5, .85, 1.0]) {
      final path = spaceCoverBloomFrostClip(
        viewport, cover, progress, cornerRadius: 20,
      );
      // The square corner lies OUTSIDE the rounded image and may receive
      // frost; the inner cover's edges and centre must remain untouched.
      expect(path.contains(const Offset(28, 179)), isTrue);
      expect(path.contains(const Offset(44, 176)), isFalse);
      expect(path.contains(cover.center), isFalse);
    }
  });

  test('queue and lyrics cover geometry follows the real panel morph', () {
    const panel = Size(384, 560);
    final resting = playerPanelArtworkRect(
      panel, artGap: 17, infoReserve: 72, queue: 0, lyrics: 0,
    );
    final midQueue = playerPanelArtworkRect(
      panel, artGap: 17, infoReserve: 72, queue: .5, lyrics: 0,
    );
    final queueThumbnail = playerPanelArtworkRect(
      panel, artGap: 17, infoReserve: 72, queue: 1, lyrics: 0,
    );
    final midLyrics = playerPanelArtworkRect(
      panel, artGap: 17, infoReserve: 72, queue: 0, lyrics: .5,
    );
    final lyricsThumbnail = playerPanelArtworkRect(
      panel, artGap: 17, infoReserve: 72, queue: 0, lyrics: 1,
    );
    expect(resting.width, 384);
    expect(queueThumbnail.width, 52);
    expect(lyricsThumbnail.width, 52);
    expect(midQueue.width, inInclusiveRange(52, 384));
    expect(midLyrics.width, inInclusiveRange(52, 384));
    expect(midQueue.width, greaterThan(queueThumbnail.width));
    expect(midLyrics.top, lessThan(lyricsThumbnail.top));
    expect(midLyrics.top, greaterThan(resting.top));
  });

  testWidgets('Space blur follows moving artwork during queue/lyrics exit', (
    tester,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AnimationController(
      vsync: tester, value: 1,
      duration: const Duration(milliseconds: 620),
    );
    final movingCover = ValueNotifier<Rect>(
      const Rect.fromLTWH(30, 150, 250, 250),
    );
    addTearDown(controller.dispose);
    addTearDown(movingCover.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpaceCoverBloomReveal(
          progress: controller,
          coverRectResolver: () => movingCover.value,
          coverMotion: movingCover,
          child: const Center(child: Text('Lyrics')),
        ),
      ),
    ));
    final clip = tester.widget<ClipPath>(find.byType(ClipPath).first);
    const position = Offset(160, 180);
    expect(clip.clipper!.getClip(viewport).contains(position), isFalse);
    movingCover.value = const Rect.fromLTWH(90, 250, 250, 250);
    await tester.pump();
    expect(clip.clipper!.getClip(viewport).contains(position), isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Space uses the full-size panel layout when entered from Lyrics', () {
    final expanded = playerPanelRestArtworkRect(
      const Size(384, 560),
      artGap: 17,
      infoReserve: 72,
    );
    expect(expanded, const Rect.fromLTWH(0, 40.5, 384, 384));
    final compact = playerPanelRestArtworkRect(
      const Size(384, 400),
      artGap: 10,
      infoReserve: 72,
    );
    expect(compact, const Rect.fromLTWH(36, 0, 312, 312));
  });

  test('Fullcover has a square full-width clear poster', () {
    const sleeve = Rect.fromLTWH(0, 0, 430, 570);
    final cover = spaceCoverRevealAnchor(
      viewport, coverRect: sleeve,
    );
    final clip = spaceCoverBloomFrostClip(
      viewport, cover, 1, cornerRadius: 0,
    );
    expect(cover.top, 0);
    expect(cover.width, viewport.width);
    expect(clip.contains(const Offset(1, 1)), isFalse);
    expect(clip.contains(const Offset(10, 650)), isTrue);
  });

  test('Canvas remains clear in its upper visual plane', () {
    final canvas = spaceCoverRevealAnchor(viewport, canvasMode: true);
    expect(canvas.left, 0);
    expect(canvas.top, 0);
    expect(canvas.width, viewport.width);
    expect(canvas.height, closeTo(viewport.height * .64, .001));
    final clip = spaceCoverBloomFrostClip(
      viewport, canvas, 1, cornerRadius: 0,
    );
    expect(clip.contains(const Offset(215, 300)), isFalse);
    expect(clip.contains(const Offset(215, 800)), isTrue);
  });

  testWidgets('frost expands and contracts without replacing lyrics', (
    tester,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 500),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpaceCoverBloomReveal(
          progress: animation,
          coverRect: artwork,
          coverCornerRadius: 20,
          child: const Center(child: Text('Synchronized lyrics')),
        ),
      ),
    ));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('Synchronized lyrics'), findsOneWidget);
    animation.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 310));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 310));
    expect(animation.value, 1);
    expect(find.text('Synchronized lyrics'), findsOneWidget);

    animation.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 250));
    expect(animation.value, 0);
    // WidgetTester checks live tickers before addTearDown runs.
    await tester.pumpWidget(const SizedBox.shrink());
    animation.dispose();
  });

  testWidgets('Canvas stays mounted during the outward frosted reveal', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: tester,
      value: .72,
      duration: const Duration(milliseconds: 620),
    );
    addTearDown(animation.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 560,
          child: SpaceCoverBloomReveal(
            progress: animation,
            canvasMode: true,
            coverCornerRadius: 0,
            child: const Center(child: Text('Canvas lyrics')),
          ),
        ),
      ),
    ));
    expect(find.text('Canvas lyrics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
