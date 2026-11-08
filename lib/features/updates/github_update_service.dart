import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flick/providers/app_build_info_provider.dart';

const lokalUpdateReleasesUrl = 'https://github.com/lokal-music/Mobile/releases';

class LokalUpdateRelease {
  const LokalUpdateRelease({
    required this.version,
    required this.build,
    required this.downloadUrl,
    required this.sha256,
    required this.pageUrl,
    required this.notes,
    this.isIos = false,
  });
  final String version, downloadUrl, sha256, pageUrl, notes;
  final int build;
  final bool isIos;
  String get identity => '$version+$build:$sha256';
}

class GithubUpdateService {
  GithubUpdateService(this.client);
  final http.Client client;
  static const _repo = 'lokal-music/Mobile';
  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'Lokal-Mobile',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// Accept canonical release assets and historic repository aliases. GitHub
  /// redirects old links today; keep their exact paths for signed older APKs.
  static bool _trustedReleaseAssetUrl(
    String url, {
    required String tag,
    required String filename,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final parts = uri.pathSegments;
    if (parts.length != 6 ||
        !{
          'lokal-music/mobile',
          'lokal-music/lokal-mobile',
          'lokal-konnekt/lokal-mobile',
        }.contains('${parts[0].toLowerCase()}/${parts[1].toLowerCase()}') ||
        parts[2] != 'releases' ||
        parts[3] != 'download' ||
        parts[4] != tag ||
        parts[5] != filename) {
      return false;
    }
    return true;
  }

  Future<dynamic> _json(String url) async {
    final response = await client
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Update server returned ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  Future<LokalUpdateRelease?> check(
    AppBuildInfo installed,
    String flavor,
  ) async {
    if (flavor == 'ios') return _checkIos(installed);
    if (flavor != 'full' && flavor != 'play') {
      throw StateError('Unknown APK variant');
    }
    final current = int.tryParse(installed.build);
    if (current == null) throw StateError('Installed build number unavailable');
    final nightly = installed.version.contains('-nightly.');
    final response = await _json(
      nightly
          ? 'https://api.github.com/repos/$_repo/releases?per_page=20'
          : 'https://api.github.com/repos/$_repo/releases/latest',
    );
    final data = response is List ? List<dynamic>.of(response) : [response];
    // Replacing a stable release preserves its old creation date, so it may
    // be below many nightlies in the list. Always include GitHub's stable tip.
    if (nightly) {
      final stable = await _json(
        'https://api.github.com/repos/$_repo/releases/latest',
      );
      if (stable is Map<String, dynamic>) data.insert(0, stable);
    }
    final candidates = data
        .whereType<Map<String, dynamic>>()
        .where(
          (r) =>
              r['draft'] != true &&
              (r['prerelease'] != true ||
                  nightly && '${r['tag_name']}'.contains('-nightly.')),
        )
        .take(4);
    LokalUpdateRelease? newest;
    for (final release in candidates) {
      final assets = (release['assets'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      String? asset(String name) {
        for (final a in assets) {
          if (a['name'] == name && a['browser_download_url'] is String) {
            final url = a['browser_download_url'] as String;
            // GitHub's release API returns the canonical repository owner in
            // browser_download_url, even if an older repo URL redirected the
            // metadata request. Validate structured URLs, not the former
            // Lokal-Konnekt path or an unsafe string prefix.
            if (_trustedReleaseAssetUrl(
              url,
              tag: '${release['tag_name']}',
              filename: name,
            )) {
              return url;
            }
          }
        }
        return null;
      }

      final metadataUrl = asset('$flavor-metadata.json');
      if (metadataUrl == null) continue;
      final metadata = await _json(metadataUrl);
      if (metadata is! Map || metadata['flavor'] != flavor) continue;
      final code = int.tryParse('${metadata['versionCode']}');
      final version = metadata['version'] as String?;
      final hash = metadata['sha256'] as String? ?? '';
      if (code == null ||
          code <= current ||
          version == null ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
        continue;
      }
      final prefix = 'Lokal-$version${flavor == 'play' ? '-Play' : ''}';
      // New releases contain ARM64 only. Keep finding older universal
      // releases so an installed signed beta can still update in place.
      final apk = asset('$prefix-arm64.apk') ?? asset('$prefix-universal.apk');
      if (apk == null) continue;
      if (newest == null || code > newest.build) {
        newest = LokalUpdateRelease(
          version: version,
          build: code,
          downloadUrl: apk,
          sha256: hash.toLowerCase(),
          pageUrl:
              '$lokalUpdateReleasesUrl/tag/${Uri.encodeComponent(release['tag_name'] as String)}',
          notes: release['body'] as String? ?? '',
        );
      }
    }
    return newest;
  }

  Future<LokalUpdateRelease?> _checkIos(AppBuildInfo installed) async {
    final current = int.tryParse(installed.build);
    if (current == null) throw StateError('Installed build number unavailable');
    // The iPhone channel is independent of GitHub's latest stable Android
    // release and intentionally includes the iOS prerelease.
    final release = await _json(
      'https://api.github.com/repos/$_repo/releases/tags/ios',
    );
    if (release is! Map<String, dynamic> ||
        release['draft'] == true ||
        release['tag_name'] != 'ios') {
      return null;
    }
    final assets = (release['assets'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    String? asset(String filename) {
      for (final item in assets) {
        final url = item['browser_download_url'];
        if (item['name'] == filename &&
            url is String &&
            _trustedReleaseAssetUrl(url, tag: 'ios', filename: filename)) {
          return url;
        }
      }
      return null;
    }

    final filename = asset('Lokal.ipa') != null
        ? 'Lokal.ipa'
        : 'Lokal-unsigned.ipa';
    final ipa = asset(filename);
    final manifest = asset('$filename.json');
    if (ipa == null || manifest == null) return null;
    final data = await _json(manifest);
    if (data is! Map || data['bundle_id'] != 'app.lokal.mobile') return null;
    final build = int.tryParse('${data['build']}');
    final version = data['version'];
    final hash = data['sha256'];
    if (build == null ||
        build <= current ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        hash is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
      return null;
    }
    return LokalUpdateRelease(
      version: version,
      build: build,
      downloadUrl: ipa,
      sha256: hash.toLowerCase(),
      pageUrl: '$lokalUpdateReleasesUrl/tag/ios',
      notes: release['body'] is String ? release['body'] as String : '',
      isIos: true,
    );
  }
}
