import 'package:flick/features/discovery/discovery_artwork.dart';
import 'package:flick/features/konnekted/konnekted_discovery_view.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Artwork extends Fake implements DiscoveryArtworkResolver {
  @override
  Future<String> resolve(DiscoveryArtworkRequest request) async => '';
}

void main() {
  testWidgets(
    'Discovery long press opens the same actions callback as Search',
    (tester) async {
      var played = 0;
      var actions = 0;
      var queued = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryArtworkResolverProvider.overrideWithValue(_Artwork()),
          ],
          child: MaterialApp(
            theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
            home: Scaffold(
              body: KonnektedDiscoveryRow(
                track: const LokalDiscoveryTrack(
                  title: 'Discovery song',
                  artist: 'Artist',
                ),
                onTap: () => played++,
                onMore: () => actions++,
                onQueue: () async {
                  queued++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Discovery song'));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(played, 0);
      expect(queued, 0);
    },
  );

  testWidgets('swipe right adds a Discovery track once without playing it', (
    tester,
  ) async {
    var played = 0;
    var actions = 0;
    var queued = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discoveryArtworkResolverProvider.overrideWithValue(_Artwork()),
        ],
        child: MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: KonnektedDiscoveryRow(
              track: const LokalDiscoveryTrack(
                title: 'Discovery song',
                artist: 'Artist',
              ),
              onTap: () => played++,
              onMore: () => actions++,
              onQueue: () async {
                queued++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('Discovery song'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(queued, 1);
    expect(played, 0);
    expect(actions, 0);
  });
}
