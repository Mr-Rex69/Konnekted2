import 'dart:convert';
import 'dart:io';

import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fixed-size artwork avoids layout-builder overhead in lists',
      (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('lokal-thumbnail-test')))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
    final image = File('${dir.path}/art.png');
    // A valid one-pixel PNG: no network or platform artwork resolver needed.
    await tester.runAsync(() => image.writeAsBytes(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/9qkAAAAASUVORK5CYII='
    )));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CachedImageWidget(
                key: const ValueKey('fixed'),
                imagePath: image.path,
                width: 48,
                height: 48,
                useThumbnail: true,
              ),
            ),
            SizedBox(
              width: 48,
              height: 48,
              child: CachedImageWidget(
                key: const ValueKey('constrained'),
                imagePath: image.path,
                useThumbnail: true,
              ),
            ),
          ],
        ),
      ),
    ));

    final fixed = find.byKey(const ValueKey('fixed'));
    final constrained = find.byKey(const ValueKey('constrained'));
    expect(
      find.descendant(of: fixed, matching: find.byType(LayoutBuilder)),
      findsNothing,
      reason: 'known tile widths must not add per-image layout callbacks',
    );
    expect(
      find.descendant(of: constrained, matching: find.byType(LayoutBuilder)),
      findsOneWidget,
      reason: 'responsive images still derive the decode width from layout',
    );
  });
}
