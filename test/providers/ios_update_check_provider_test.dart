import 'dart:convert';

import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/providers/app_build_info_provider.dart';
import 'package:flick/providers/connectivity_provider.dart';
import 'package:flick/providers/update_check_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  ConnectivityStatus build() => ConnectivityStatus.online;
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final automatic in [true, false]) {
    test(
      'iPhone routes checks to iOS metadata; automatic=$automatic, manual remains available',
      () async {
        SharedPreferences.setMockInitialValues({
          'lokal.automatic_update_checks': automatic,
        });
        final requested = <Uri>[];
        final client = MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            jsonEncode(
              request.url.host == 'api.github.com'
                  ? {
                      'tag_name': 'ios',
                      'prerelease': true,
                      'draft': false,
                      'body': '',
                      'assets': [
                        for (final name in ['Lokal.ipa', 'Lokal.ipa.json'])
                          {
                            'name': name,
                            'browser_download_url':
                                'https://github.com/lokal-music/mobile/releases/download/ios/$name',
                          },
                      ],
                    }
                  : {
                      'bundle_id': 'app.lokal.mobile',
                      'version': '1.0.0',
                      'build': '163',
                      'sha256': List.filled(64, 'a').join(),
                    },
            ),
            200,
          );
        });
        addTearDown(client.close);
        final container = ProviderContainer(
          overrides: [
            connectivityProvider.overrideWith(_Online.new),
            appBuildInfoProvider.overrideWith(
              (ref) async => const AppBuildInfo(version: '1.0.0', build: '162'),
            ),
            githubUpdateServiceProvider.overrideWithValue(
              GithubUpdateService(client),
            ),
          ],
        );
        addTearDown(container.dispose);
        // iOS does not ask Android's diagnostics bridge for an APK flavor.
        expect(await container.read(updateBuildFlavorProvider.future), 'ios');
        final notifier = container.read(updateCheckProvider.notifier);
        await notifier.refreshIfOnline();
        expect(requested, hasLength(automatic ? 2 : 0));
        if (!automatic) await notifier.refreshIfOnline(force: true);
        expect(container.read(updateCheckProvider).release?.isIos, isTrue);
        expect(container.read(updateCheckProvider).release?.build, 163);
        expect(requested.first.path, endsWith('/releases/tags/ios'));
      },
    );
  }
}
