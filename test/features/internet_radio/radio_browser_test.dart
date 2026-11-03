import 'dart:convert';

import 'package:flick/features/internet_radio/radio_browser.dart';
import 'package:flick/features/internet_radio/station_metadata.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> station(String id, String codec, int bitrate) => {
  'stationuuid': id,
  'name': 'Station ' + id,
  'url_resolved': 'https://streams.example.test/' + id,
  'codec': codec,
  'bitrate': bitrate,
  'lastcheckok': 1,
  'country': 'France',
  'countrycode': 'FR',
  'tags': 'jazz,deep',
};

void main() {
  test('strict 256 kbps cutoff with verified lossless-codec exception', () {
    expect(qualifiesRadioBrowserStation(station('low', 'MP3', 255)), isFalse);
    expect(qualifiesRadioBrowserStation(station('aac', 'AAC', 256)), isTrue);
    expect(qualifiesRadioBrowserStation(station('opus', 'OPUS', 320)), isTrue);
    expect(qualifiesRadioBrowserStation(station('flac', 'FLAC', 0)), isTrue);
    expect(qualifiesRadioBrowserStation(station('unknown', '', 320)), isFalse);
    expect(qualifiesRadioBrowserStation({
      ...station('dead', 'MP3', 320),
      'lastcheckok': false,
    }), isFalse);
    expect(qualifiesRadioBrowserStation({
      ...station('file', 'AAC', 320),
      'url_resolved': 'file:///private/audio',
    }), isFalse);
  });

  test('browses and deduplicates 256+ kbps plus FLAC, with bitrate filter', () async {
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      final flac = request.url.queryParameters['codec'] == 'FLAC';
      return http.Response(jsonEncode(flac
          ? [station('lossless', 'FLAC', 0), station('lossless', 'FLAC', 0)]
          : [station('low', 'MP3', 128), station('aac', 'AAC', 256)]), 200);
    });
    final browser = RadioBrowserClient(client: client);
    addTearDown(client.close);

    final result = await browser.browse(query: 'Nova', country: 'FR', limit: 40);
    expect(result.stations.map((s) => s.id),
        ['rb:lossless', 'rb:aac']);
    expect(result.stations.last.bitrate, 256);
    expect(result.stations.last.countryCode, 'FR');
    expect(result.hasMore, isFalse);
    expect(urls.length, 2);
    expect(urls.first.queryParameters['bitrateMin'], '256');
    expect(urls.last.queryParameters['bitrateMin'], '0');
    expect(urls.last.queryParameters['codec'], 'FLAC');
    expect(urls.every((url) => url.queryParameters['name'] == 'Nova'), isTrue);
  });

  test('uses original stream URL when a resolved URL is empty', () {
    final record = {
      ...station('fallback', 'MP3', 320),
      'url_resolved': '',
      'url': 'https://streams.example.test/fallback',
    };
    expect(qualifiesRadioBrowserStation(record), isTrue);
    expect(stationFromRadioBrowser(record).url,
        'https://streams.example.test/fallback');
  });

  test('Icecast metadata uses the correct mount, never another station', () {
    final data = {
      'icestats': {
        'source': [
          {'listenurl': 'https://stream.example.test/other',
           'title': 'Wrong - Track'},
          {'listenurl': 'https://stream.example.test/live',
           'title': 'Correct - Song'},
        ],
      },
    };
    final match = StationMetadataLookup.parseIcecastStatusForTest(
        data, 'https://stream.example.test/live');
    expect(match?.label, 'Correct — Song');
    expect(StationMetadataLookup.parseIcecastStatusForTest(
        data, 'https://stream.example.test/missing'), isNull);
  });

  test('paginates without re-fetching lossless on later pages', () async {
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      return http.Response(jsonEncode([station('a', 'MP3', 320)]), 200);
    });
    addTearDown(client.close);
    final result = await RadioBrowserClient(client: client)
        .browse(offset: 60, limit: 60);
    expect(result.nextOffset, 61);
    expect(urls.length, 1);
    expect(urls.single.queryParameters['offset'], '60');
  });
}
