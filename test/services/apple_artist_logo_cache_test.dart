import 'dart:convert';
import 'dart:io';

import 'package:flick/services/apple_music/apple_artist_logo_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/gH8AAAAASUVORK5CYII=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('permanent PNG logo restores before UI without any network request',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = await Directory.systemTemp.createTemp('lokal_artist_logos_');
    addTearDown(() => dir.delete(recursive: true));
    var requests = 0;
    var fail = false;
    final client = MockClient((request) async {
      requests++;
      if (fail) return http.Response('unavailable', 503);
      return http.Response.bytes(base64Decode(_png), 200,
          headers: {'content-type': 'image/png'});
    });
    addTearDown(client.close);
    final cache = AppleArtistLogoCache(
      directory: () async => dir,
      preferences: () async => prefs,
      client: client,
    );
    const url = 'https://is1-ssl.mzstatic.com/image/logo.png';
    final logo = await cache.save(
      artistName: 'Beyoncé', logoUrl: url, aspect: 4,
    );
    expect(logo, isNotNull);
    expect(await File(logo!.path).exists(), isTrue);
    expect(requests, 1);

    // Simulate a force-close: a different service instance with empty memory.
    final restored = AppleArtistLogoCache(
      directory: () async => dir,
      preferences: () async => prefs,
      client: client,
    );
    expect(restored.cachedFor('Beyonce'), isNull);
    await restored.restore();
    expect(restored.cachedFor('BEYONCÉ')?.path, logo.path);
    expect(restored.cachedFor('Beyoncé')?.aspect, 4);
    expect(requests, 1); // No network needed for the first UI frame.

    // A manual refresh must never delete the old logo if Apple is down.
    fail = true;
    final old = await restored.save(
      artistName: 'Beyonce', logoUrl: url, aspect: 4, force: true,
    );
    expect(old?.path, logo.path);
    expect(requests, 2);
    expect(await File(restored.cachedFor('Beyonce')!.path).exists(), isTrue);
  });

  test('rejects untrusted URLs and invalid bytes without losing a cached logo',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = await Directory.systemTemp.createTemp('lokal_artist_logo_bad_');
    addTearDown(() => dir.delete(recursive: true));
    final client = MockClient((request) async =>
        http.Response.bytes([0, 1, 2, 3], 200));
    addTearDown(client.close);
    final cache = AppleArtistLogoCache(
      directory: () async => dir,
      preferences: () async => prefs,
      client: client,
    );
    expect(await cache.save(
      artistName: 'Artist',
      logoUrl: 'https://untrusted.example/logo.png',
      aspect: 2,
    ), isNull);
    expect(await cache.save(
      artistName: 'Artist',
      logoUrl: 'https://is1-ssl.mzstatic.com/broken.png',
      aspect: 2,
    ), isNull);
  });
}
