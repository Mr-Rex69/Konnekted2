import 'dart:convert';

import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/providers/app_build_info_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _root = 'https://github.com/lokal-music/mobile/releases/download/ios';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> _release({
  String name = 'Lokal.ipa',
  bool draft = false,
}) => {
  'tag_name': 'ios',
  'draft': draft,
  'prerelease': true,
  'body': 'iPhone notes',
  'assets': [
    for (final filename in [name, '$name.json'])
      {'name': filename, 'browser_download_url': '$_root/$filename'},
  ],
};
Map<String, Object?> _metadata(int build) => {
  'bundle_id': 'app.lokal.mobile',
  'version': '1.0.0',
  'build': '$build',
  'sha256': _hash,
};

void main() {
  test(
    'iOS prerelease offers a higher build at the same app version',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode(
            request.url.host == 'api.github.com' ? _release() : _metadata(163),
          ),
          200,
        );
      });
      addTearDown(client.close);
      final update = await GithubUpdateService(client)
          .check(const AppBuildInfo(version: '1.0.0', build: '162'), 'ios');
      expect(update?.isIos, isTrue);
      expect(update?.build, 163);
      expect(update?.downloadUrl, '$_root/Lokal.ipa');
      expect(update?.pageUrl, endsWith('/tag/ios'));
      expect(paths.first, endsWith('/releases/tags/ios'));
      expect(paths.any((path) => path.endsWith('/latest')), isFalse);
    },
  );

  for (final build in [161, 162]) {
    test('iOS never offers the current or an older build ($build)', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host == 'api.github.com'
                ? _release()
                : _metadata(build),
          ),
          200,
        ),
      );
      addTearDown(client.close);
      expect(
        await GithubUpdateService(client)
            .check(const AppBuildInfo(version: '1.0.0', build: '162'), 'ios'),
        isNull,
      );
    });
  }

  test(
    'a draft or forged release asset cannot be offered or fetched',
    () async {
      for (final draft in [true, false]) {
        final release = _release(draft: draft);
        if (!draft) {
          release['assets'] = [
            {'name': 'Lokal.ipa', 'browser_download_url': '$_root/Lokal.ipa'},
            {
              'name': 'Lokal.ipa.json',
              'browser_download_url': 'https://example.invalid/metadata',
            },
          ];
        }
        final calls = <Uri>[];
        final client = MockClient((request) async {
          calls.add(request.url);
          return http.Response(jsonEncode(release), 200);
        });
        addTearDown(client.close);
        expect(
          await GithubUpdateService(client)
              .check(const AppBuildInfo(version: '1.0.0', build: '162'), 'ios'),
          isNull,
        );
        expect(calls, hasLength(1));
      }
    },
  );

  test('iOS rejects wrong bundle metadata or missing checksums', () async {
    for (final change in [
      {'bundle_id': 'other.app'},
      {'sha256': 'invalid'},
    ]) {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host == 'api.github.com'
                ? _release()
                : {..._metadata(163), ...change},
          ),
          200,
        ),
      );
      addTearDown(client.close);
      expect(
        await GithubUpdateService(client)
            .check(const AppBuildInfo(version: '1.0.0', build: '162'), 'ios'),
        isNull,
      );
    }
  });

  test(
    'legacy iOS package filenames remain readable during migration',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host == 'api.github.com'
                ? _release(name: 'Lokal-unsigned.ipa')
                : _metadata(163),
          ),
          200,
        ),
      );
      addTearDown(client.close);
      expect(
        (await GithubUpdateService(client).check(
          const AppBuildInfo(version: '1.0.0', build: '162'),
          'ios',
        ))?.isIos,
        isTrue,
      );
    },
  );
}
