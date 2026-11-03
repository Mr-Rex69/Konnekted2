import 'dart:async';
import 'dart:convert';

import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('radio operations return normally before their deadline', () async {
    final result = await radioWithTimeout(
      Future<int>.value(42),
      timeout: const Duration(seconds: 1),
      timeoutMessage: 'not used',
    );

    expect(result, 42);
  });

  test('a stalled radio operation fails with a useful timeout error', () async {
    final pending = Completer<void>();

    await expectLater(
      radioWithTimeout(
        pending.future,
        timeout: const Duration(milliseconds: 10),
        timeoutMessage: 'The station stream did not respond in time.',
      ),
      throwsA(
        isA<RadioCatalogException>().having(
          (error) => error.message,
          'message',
          'The station stream did not respond in time.',
        ),
      ),
    );
  });

  test('a malformed catalogue fails instead of returning an empty list', () {
    expect(
      () => parseRadioCatalog({'stations': []}),
      throwsA(isA<RadioCatalogException>()),
    );
  });
  test('uses the same station catalogue URL as desktop Lokal', () {
    expect(
      defaultRadioCatalogUrl,
      'https://raw.githubusercontent.com/lokal-music/Desktop/refs/heads/main/radios.json',
    );
  });

  test('follows HTTPS redirects when loading the station catalogue', () async {
    final source = Uri.parse(defaultRadioCatalogUrl);
    final destination = Uri.parse('https://cdn.example.test/radios.json');
    final client = MockClient((request) async {
      if (request.url == source) {
        return http.Response('', 302, headers: {'location': destination.toString()});
      }
      expect(request.url, destination);
      return http.Response(
        jsonEncode({
          'version': 1,
          'title': 'Test radio',
          'stations': [
            {'title': 'Station One', 'url': 'https://stream.example.test/live'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final json = await fetchRadioCatalogJson(client, source);
    final catalog = parseRadioCatalog(json);
    expect(catalog.title, 'Test radio');
    expect(catalog.stations.single.title, 'Station One');
  });

  test('uses the GitHub contents endpoint if the default raw catalogue fails', () async {
    final source = Uri.parse(defaultRadioCatalogUrl);
    final apiUrl = Uri.https(
      'api.github.com',
      '/repos/lokal-music/Desktop/contents/radios.json',
      {'ref': 'main'},
    );
    final catalogJson = jsonEncode({
      'version': 1,
      'title': 'Fallback radio',
      'stations': [
        {'title': 'Fallback Station', 'url': 'https://stream.example.test/live'},
      ],
    });
    final client = MockClient((request) async {
      if (request.url == source) {
        return http.Response('raw mirror unavailable', 503);
      }
      expect(request.url, apiUrl);
      return http.Response(
        jsonEncode({
          'encoding': 'base64',
          'content': base64Encode(utf8.encode(catalogJson)),
        }),
        200,
      );
    });
    addTearDown(client.close);

    final json = await fetchRadioCatalogJson(client, source);
    final catalog = parseRadioCatalog(json);
    expect(catalog.title, 'Fallback radio');
    expect(catalog.stations.single.title, 'Fallback Station');
  });

  test('refuses an HTTPS catalogue redirect to insecure HTTP', () async {
    final source = Uri.parse(defaultRadioCatalogUrl);
    final client = MockClient((request) async => http.Response(
      '',
      302,
      headers: {'location': 'http://insecure.example.test/radios.json'},
    ));
    addTearDown(client.close);

    await expectLater(
      fetchRadioCatalogJson(client, source),
      throwsA(isA<RadioCatalogException>().having(
        (error) => error.message,
        'message',
        contains('unsafe URL'),
      )),
    );
  });

}
