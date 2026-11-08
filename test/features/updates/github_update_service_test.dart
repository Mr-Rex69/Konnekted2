import 'dart:convert';

import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/providers/app_build_info_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const root = 'https://github.com/lokal-music/Mobile/releases/download';
final hash = List.filled(64, 'a').join();
Map<String, Object?> release(
  String version, {
  bool prerelease = false,
  bool draft = false,
  String flavor = 'full',
  bool legacy = false,
}) => {
  'tag_name': 'v$version',
  'prerelease': prerelease,
  'draft': draft,
  'body': 'Release notes',
  'assets': [
    {
      'name': '$flavor-metadata.json',
      'browser_download_url': '$root/v$version/$flavor-metadata.json',
    },
    {
      'name': 'Lokal-$version${flavor == 'play' ? '-Play' : ''}-${legacy ? 'universal' : 'arm64'}.apk',
      'browser_download_url':
          '$root/v$version/Lokal-$version${flavor == 'play' ? '-Play' : ''}-${legacy ? 'universal' : 'arm64'}.apk',
    },
  ],
};

void main() {
  test(
    'permanent Android tag updates existing installs using package metadata',
    () async {
      final rolling = release('7.5.3');
      rolling['tag_name'] = 'android';
      for (final asset in rolling['assets'] as List<Map<String, String>>) {
        asset['browser_download_url'] = asset['browser_download_url']!
            .replaceFirst('/v7.5.3/', '/android/');
      }
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host == 'api.github.com'
                ? rolling
                : {
                    'version': '7.5.3',
                    'versionCode': 216500001,
                    'flavor': 'full',
                    'sha256': hash,
                  },
          ),
          200,
        ),
      );
      addTearDown(client.close);
      final update = await GithubUpdateService(
        client,
      ).check(const AppBuildInfo(version: '7.5.2', build: '216500000'), 'full');
      expect(update?.version, '7.5.3');
      expect(update?.apkUrl, '$root/android/Lokal-7.5.3-arm64.apk');
      expect(
        update?.pageUrl,
        'https://github.com/lokal-music/Mobile/releases/tag/android',
      );
    },
  );

  test('finds the published 2.0.0 update after repository rename', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (request.url.host == 'api.github.com') {
        if (request.url.path !=
            '/repos/lokal-music/Mobile/releases/latest') {
          return http.Response('Wrong repository path', 404);
        }
        return http.Response(jsonEncode(release('2.0.0')), 200);
      }
      if (request.url.toString() == '$root/v2.0.0/full-metadata.json') {
        return http.Response(
          jsonEncode({
            'version': '2.0.0',
            'versionCode': 215113903,
            'flavor': 'full',
            'sha256': hash,
          }),
          200,
        );
      }
      return http.Response('Wrong asset URL', 404);
    });
    addTearDown(client.close);
    final available = await GithubUpdateService(client).check(
      const AppBuildInfo(version: '1.4.3', build: '215113000'),
      'full',
    );
    expect(available?.version, '2.0.0');
    expect(available?.build, 215113903);
    expect(
      available?.apkUrl,
      '$root/v2.0.0/Lokal-2.0.0-arm64.apk',
    );
    expect(
      requested.map((uri) => uri.toString()),
      contains('$root/v2.0.0/full-metadata.json'),
    );
  });


  test('accepts previous GitHub release asset URLs for already-signed versions', () async {
    const formerRoot = 'https://github.com/lokal-music/lokal-mobile/releases/download';
    final legacy = release('2.1.0');
    final assets = legacy['assets']! as List<Map<String, String>>;
    for (final entry in assets) {
      entry['browser_download_url'] =
          entry['browser_download_url']!.replaceFirst(root, formerRoot);
    }
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        expect(request.url.path,
            '/repos/lokal-music/Mobile/releases/latest');
        return http.Response(jsonEncode(legacy), 200);
      }
      expect(request.url.toString(),
          '$formerRoot/v2.1.0/full-metadata.json');
      return http.Response(jsonEncode({
        'version': '2.1.0', 'versionCode': 215113904,
        'flavor': 'full', 'sha256': hash,
      }), 200);
    });
    addTearDown(client.close);
    final available = await GithubUpdateService(client).check(
      const AppBuildInfo(version: '2.0.0', build: '215113903'), 'full',
    );
    expect(available?.apkUrl, '$formerRoot/v2.1.0/Lokal-2.1.0-arm64.apk');
    expect(available?.pageUrl, 'https://github.com/lokal-music/Mobile/releases/tag/v2.1.0');
  });

  test('rejects forged GitHub assets even if names and hashes look valid', () async {
    final forged = release('2.0.0');
    final assets = forged['assets']! as List<Map<String, String>>;
    assets[0]['browser_download_url'] =
        'https://github.com/lokal-music/Mobile-evil/releases/download/v2.0.0/full-metadata.json';
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode(forged), 200);
      }
      return http.Response(
        jsonEncode({
          'version': '2.0.0',
          'versionCode': 215113903,
          'flavor': 'full',
          'sha256': hash,
        }),
        200,
      );
    });
    addTearDown(client.close);
    expect(
      await GithubUpdateService(client).check(
        const AppBuildInfo(version: '1.4.3', build: '1'),
        'full',
      ),
      isNull,
    );
  });

  test(
    'same marketing version with higher build offers replacement; no downgrade',
    () async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host == 'api.github.com'
                ? [release('1.0.0')]
                : {
                    'version': '1.0.0',
                    'versionCode': 200,
                    'flavor': 'full',
                    'sha256': hash,
                  },
          ),
          200,
        ),
      );
      final service = GithubUpdateService(client);
      expect(
        (await service.check(
          const AppBuildInfo(version: '1.0.0', build: '199'),
          'full',
        ))?.build,
        200,
      );
      expect(
        await service.check(
          const AppBuildInfo(version: '1.0.0', build: '200'),
          'full',
        ),
        isNull,
      );
      expect(
        await service.check(
          const AppBuildInfo(version: '1.0.0', build: '201'),
          'full',
        ),
        isNull,
      );
      client.close();
    },
  );

  test(
    'stable skips nightlies and drafts; nightly finds newer compatible build',
    () async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host == 'api.github.com'
                ? [
                    release('2.0.0', draft: true),
                    release('1.0.1-nightly.2', prerelease: true),
                    release('1.0.0'),
                  ]
                : {
                    'version': r.url.path.contains('nightly')
                        ? '1.0.1-nightly.2'
                        : '1.0.0',
                    'versionCode': r.url.path.contains('nightly') ? 300 : 200,
                    'flavor': 'full',
                    'sha256': hash,
                  },
          ),
          200,
        ),
      );
      final service = GithubUpdateService(client);
      expect(
        (await service.check(
          const AppBuildInfo(version: '1.0.0', build: '199'),
          'full',
        ))?.build,
        200,
      );
      expect(
        (await service.check(
          const AppBuildInfo(version: '1.0.1-nightly.1', build: '199'),
          'full',
        ))?.build,
        300,
      );
      client.close();
    },
  );

  test(
    'chooses matching Play asset and rejects invalid checksum metadata',
    () async {
      var valid = true;
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host == 'api.github.com'
                ? [release('1.0.1', flavor: 'play')]
                : {
                    'version': '1.0.1',
                    'versionCode': 201,
                    'flavor': 'play',
                    'sha256': valid ? hash : 'bad',
                  },
          ),
          200,
        ),
      );
      final service = GithubUpdateService(client);
      final installed = const AppBuildInfo(version: '1.0.0', build: '200');
      expect(
        (await service.check(installed, 'play'))?.apkUrl,
        endsWith('-Play-arm64.apk'),
      );
      valid = false;
      expect(await service.check(installed, 'play'), isNull);
      client.close();
    },
  );

  test('API failure is not reported as up to date', () async {
    final client = MockClient((_) async => http.Response('limited', 403));
    expect(
      GithubUpdateService(client)
          .check(const AppBuildInfo(version: '1.0.0', build: '1'), 'full'),
      throwsStateError,
    );
    client.close();
  });

  test('still recognizes signed legacy universal APKs for in-place updates',
      () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.host == 'api.github.com'
              ? [release('1.0.0', legacy: true)]
              : {
                  'version': '1.0.0',
                  'versionCode': 200,
                  'flavor': 'full',
                  'sha256': hash,
                },
        ),
        200,
      ),
    );
    final asset = await GithubUpdateService(client).check(
      const AppBuildInfo(version: '1.0.0', build: '199'),
      'full',
    );
    expect(asset?.apkUrl, endsWith('-universal.apk'));
    client.close();
  });

}
