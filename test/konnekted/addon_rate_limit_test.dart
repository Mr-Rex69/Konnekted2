import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/morneye/morneye_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a gateway cooldown stops alternate search queries and reaches autoplay',
    () async {
      var calls = 0;
      final source = OnlineSource(
        id: 'a-test',
        name: 'Deezer',
        results: (_) async {
          calls++;
          throw const MorneyeRateLimitException(Duration(seconds: 120));
        },
        play: (_) async => throw UnimplementedError(),
      );
      await expectLater(
        findDiscoverySourceMatch(
          source: source,
          candidate: const RecommendationCandidate(
            title: 'Song',
            artist: 'Artist',
          ),
          queries: ['first', 'second', 'third'],
        ),
        throwsA(
          isA<DiscoveryRateLimited>().having(
            (error) => shouldHoldPendingPlayback(error),
            'holds pending song',
            isTrue,
          ),
        ),
      );
      expect(calls, 1);
    },
  );
}
