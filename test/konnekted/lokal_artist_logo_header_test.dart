import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/gH8AAAAASUVORK5CYII=';

void main() {
  testWidgets('saved stylized logo is the first header title frame', (
    tester,
  ) async {
    final dir = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'artist_header_logo_',
      );
      await File('${directory.path}/artist.png')
          .writeAsBytes(base64Decode(png), flush: true);
      return directory;
    }))!;
    addTearDown(() => dir.delete(recursive: true));
    final logo = File('${dir.path}/artist.png');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LokalDetailHeader(
                title: 'Beyoncé',
                isArtist: true,
                fixedArtwork: true,
                controlsInOverlay: true,
                background: Colors.black,
                artwork: const ColoredBox(color: Colors.black),
                artistLogoPath: logo.path,
                artistLogoAspect: 4,
                onlineEnabled: false,
                onBack: () {},
                onOnline: () {},
                onMore: () {},
                onArtworkTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // Before async FileImage decoding, the title must NOT be replaced by
    // the plain-text variant, avoiding the launch/title-flash regression.
    expect(find.text('Beyoncé'), findsNothing);
    final artwork = find
        .byType(Image)
        .evaluate()
        .map((element) => element.widget as Image);
    expect(artwork.any((image) => image.image is FileImage), isTrue);
    await tester.pump();
    expect(find.text('Beyoncé'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
