import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';

void main() {
  testWidgets('detail artwork reveals the decoded frame and retains old pixels', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lokal-art-reveal'),
    ))!;
    addTearDown(() async => dir.delete(recursive: true));
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/9qkAAAAASUVORK5CYII=';
    final first = File('${dir.path}/first.png');
    final second = File('${dir.path}/second.png');
    await tester.runAsync(() => first.writeAsBytes(base64Decode(png)));
    await tester.runAsync(() => second.writeAsBytes(base64Decode(png)));

    Widget page(String path, {bool reveal = true, bool reduced = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: SizedBox.square(
                dimension: 150,
                child: CachedImageWidget(
                  imagePath: path,
                  width: 150,
                  height: 150,
                  revealOnLoad: reveal,
                  placeholder: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(page(first.path));
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).gaplessPlayback, isTrue);
    await tester.pumpAndSettle();

    // Changing an artist portrait should retain the previous decoded image
    // until the replacement frame is available, with no blank frame.
    await tester.pumpWidget(page(second.path));
    expect(tester.widget<Image>(find.byType(Image)).gaplessPlayback, isTrue);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    await tester.pumpWidget(page(second.path, reduced: true));
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('artwork reveal fills a non-square hero', (tester) async {
    final art = File('assets/branding/lokal_icon.png');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: CachedImageWidget(
                imagePath: art.path,
                fit: BoxFit.cover,
                revealOnLoad: true,
                placeholder: const SizedBox(
                  key: ValueKey('hero-placeholder'),
                  width: 50,
                  height: 50,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('hero-placeholder'))),
      const Size(300, 400),
    );
  });

  testWidgets('list artwork stays on the existing no-fade fast path', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lokal-no-art-reveal'),
    ))!;
    addTearDown(() async => dir.delete(recursive: true));
    final art = File('${dir.path}/cover.png');
    await tester.runAsync(
      () => art.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/9qkAAAAASUVORK5CYII=',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 80,
          child: CachedImageWidget(imagePath: art.path, width: 80, height: 80),
        ),
      ),
    );
    expect(tester.widget<Image>(find.byType(Image)).gaplessPlayback, isFalse);
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });
}
