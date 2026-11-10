import 'dart:async';

import 'package:flick/services/notification_artwork_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationArtworkResolver', () {
    test('keeps local artwork immediately and ignores missing artwork', () {
      final resolver = NotificationArtworkResolver(
        fetcher: (_) => throw StateError('Remote fetch not expected'),
      );
      final updates = <String>[];

      expect(
        resolver.pathFor(
          identity: 'local',
          artwork: '/storage/emulated/0/Music/cover.jpg',
          onResolved: updates.add,
        ),
        '/storage/emulated/0/Music/cover.jpg',
      );
      expect(
        resolver.pathFor(
          identity: 'no-art',
          artwork: null,
          onResolved: updates.add,
        ),
        isNull,
      );
      expect(updates, isEmpty);
    });

    test(
      'caches a remote cover without blocking or repeated requests',
      () async {
        final pending = Completer<String?>();
        var requests = 0;
        final updates = <String>[];
        final resolver = NotificationArtworkResolver(
          fetcher: (url) {
            expect(url, 'https://covers.example/album.jpg');
            requests++;
            return pending.future;
          },
        );

        String? read() => resolver.pathFor(
          identity: 'addon:track-1',
          artwork: 'https://covers.example/album.jpg',
          onResolved: updates.add,
        );

        expect(read(), isNull);
        expect(read(), isNull);
        expect(requests, 1);
        pending.complete('/cache/album.jpg');
        await Future<void>.delayed(Duration.zero);
        expect(updates, ['/cache/album.jpg']);
        expect(read(), '/cache/album.jpg');
        expect(requests, 1);
      },
    );

    test('late completion never overwrites the next track', () async {
      final oldRequest = Completer<String?>();
      final newRequest = Completer<String?>();
      final updates = <String>[];
      final resolver = NotificationArtworkResolver(
        fetcher: (url) =>
            url.contains('old') ? oldRequest.future : newRequest.future,
      );

      expect(
        resolver.pathFor(
          identity: 'song-1',
          artwork: 'https://covers.example/old.jpg',
          onResolved: updates.add,
        ),
        isNull,
      );
      expect(
        resolver.pathFor(
          identity: 'song-2',
          artwork: 'https://covers.example/new.jpg',
          onResolved: updates.add,
        ),
        isNull,
      );
      oldRequest.complete('/cache/old.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(updates, isEmpty);
      newRequest.complete('/cache/new.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(updates, ['/cache/new.jpg']);
    });

    test('invalidates downloads after the notification is hidden', () async {
      final pending = Completer<String?>();
      final updates = <String>[];
      final resolver = NotificationArtworkResolver(
        fetcher: (_) => pending.future,
      );
      resolver.pathFor(
        identity: 'song-1',
        artwork: 'https://covers.example/cover.jpg',
        onResolved: updates.add,
      );
      resolver.invalidate();
      pending.complete('/cache/cover.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(updates, isEmpty);
    });

    test(
      'PC-streamed covers resolve through their authenticated library source',
      () async {
        final pending = Completer<String?>();
        final updates = <String>[];
        final requests = <(String, String)>[];
        final resolver = NotificationArtworkResolver(
          fetcher: (_) =>
              throw StateError('Must not fetch a provider marker as HTTP'),
          sourceFetcher: (audio, cover) {
            requests.add((audio, cover));
            return pending.future;
          },
        );
        String? read() => resolver.pathFor(
          identity: 'pc-stream',
          artwork: 'lokal-cover://track',
          audioSourcePath: 'lokal://42/track',
          onResolved: updates.add,
        );
        expect(read(), isNull);
        expect(read(), isNull);
        expect(requests, [('lokal://42/track', 'lokal-cover://track')]);
        pending.complete('/cache/authenticated-pc-cover.png');
        await Future<void>.delayed(Duration.zero);
        expect(updates, ['/cache/authenticated-pc-cover.png']);
        expect(read(), '/cache/authenticated-pc-cover.png');
      },
    );

    test(
      'a delayed PC-streamed cover cannot overwrite a new playback owner',
      () async {
        final pending = Completer<String?>();
        final updates = <String>[];
        final resolver = NotificationArtworkResolver(
          sourceFetcher: (_, __) => pending.future,
        );
        resolver.pathFor(
          identity: 'pc-stream',
          artwork: 'lokal-cover://track',
          audioSourcePath: 'lokal://42/track',
          onResolved: updates.add,
        );
        resolver.invalidate();
        pending.complete('/cache/old-pc-cover.png');
        await Future<void>.delayed(Duration.zero);
        expect(updates, isEmpty);
      },
    );

    testWidgets('a transient PC cover retries without a playback update', (
      tester,
    ) async {
      var attempts = 0;
      final updates = <String>[];
      final resolver = NotificationArtworkResolver(
        sourceFetcher: (_, __) async {
          if (++attempts == 1) throw StateError('LAN temporarily unavailable');
          return '/cache/recovered-pc-cover.png';
        },
      );
      addTearDown(resolver.invalidate);
      resolver.pathFor(
        identity: 'pc-stream',
        artwork: 'lokal-cover://one',
        audioSourcePath: 'lokal://42/one',
        onResolved: updates.add,
      );
      await tester.pump();
      expect(attempts, 1);
      expect(updates, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      expect(attempts, 2);
      expect(updates, ['/cache/recovered-pc-cover.png']);
    });

    testWidgets('pending cover retries stop on owner handoff', (tester) async {
      var attempts = 0;
      final resolver = NotificationArtworkResolver(
        fetcher: (_) async {
          attempts++;
          return null;
        },
      );
      resolver.pathFor(
        identity: 'old',
        artwork: 'https://covers.example/a',
        onResolved: (_) {},
      );
      await tester.pump();
      resolver.invalidate();
      await tester.pump(const Duration(seconds: 20));
      expect(attempts, 1);
    });

    test(
      'failed and unsupported remote covers do not disrupt playback',
      () async {
        final updates = <String>[];
        final resolver = NotificationArtworkResolver(
          fetcher: (_) async => throw StateError('offline'),
        );
        addTearDown(resolver.invalidate);
        expect(
          resolver.pathFor(
            identity: 'bad-url',
            artwork: 'javascript:alert(1)',
            onResolved: updates.add,
          ),
          isNull,
        );
        expect(
          resolver.pathFor(
            identity: 'offline',
            artwork: 'https://covers.example/missing.jpg',
            onResolved: updates.add,
          ),
          isNull,
        );
        await Future<void>.delayed(Duration.zero);
        expect(updates, isEmpty);
      },
    );
  });
}
