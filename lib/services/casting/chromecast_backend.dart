import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'cast_device.dart';

/// Shared native sender contract. Mobile transport failures must reach ownership
/// handoff and UI; unsupported desktop hosts retain the existing optional bridge.
class ChromecastBackend {
  ChromecastBackend({bool? propagateErrors})
    : _propagateErrors =
          propagateErrors ?? (Platform.isIOS || Platform.isAndroid);

  static const _channel = MethodChannel('com.mossapps.flick/cast');
  static const _eventChannel = EventChannel('com.mossapps.flick/cast_events');
  final bool _propagateErrors;
  Stream<Map<String, dynamic>>? _events;

  Future<T?> _call<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      if (_propagateErrors) rethrow;
    } on MissingPluginException {
      if (_propagateErrors) rethrow;
    }
    return null;
  }

  Future<List<CastDevice>> discover() async {
    final raw = await _call<List<dynamic>>('discover');
    return raw
            ?.whereType<Map>()
            .map(
              (m) => CastDevice(
                id: m['id'] as String? ?? '',
                name: m['name'] as String? ?? 'Chromecast',
                backend: CastBackend.chromecast,
              ),
            )
            .where((device) => device.id.isNotEmpty)
            .toList() ??
        const [];
  }

  Future<void> connect(CastDevice device) =>
      _invoke('connect', {'id': device.id});

  Future<void> load(
    String url, {
    String? title,
    String? artist,
    bool? autoplay,
    Duration? position,
    String? contentType,
    String? album,
    String? artworkUrl,
    String? trackId,
    String? loadId,
  }) => _invoke('load', {
    'url': url,
    'title': title,
    'artist': artist,
    'autoplay': ?autoplay,
    if (position != null) 'position': position.inMilliseconds,
    'contentType': ?contentType,
    'album': ?album,
    'artworkUrl': ?artworkUrl,
    'trackId': ?trackId,
    'loadId': ?loadId,
  });

  Future<Map<String, dynamic>> sessionInfo() async {
    final value = await _call<Map>('sessionInfo');
    return value?.cast<String, dynamic>() ?? {};
  }

  Future<void> sendCustom(Map<String, dynamic> data) =>
      _invoke('sendCustom', {'protocol': 1, ...data});

  Future<void> play() => _invoke('play');
  Future<void> pause() => _invoke('pause');
  Future<void> resume() => _invoke('play');
  Future<void> stop() => _invoke('stop');
  Future<void> seek(Duration position) =>
      _invoke('seek', {'position': position.inMilliseconds});
  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'volume': volume});
  Future<double?> getVolume() => _call<double>('getVolume');
  Future<void> disconnect() => _invoke('disconnect');

  Future<List<Map<String, dynamic>>> getOutputRoutes() async {
    final raw = await _call<List<dynamic>>('getOutputRoutes');
    return raw
            ?.whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList() ??
        const [];
  }

  Future<bool> selectOutputRoute(String id) async =>
      await _call<bool>('selectOutputRoute', {'id': id}) ?? false;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    await _call<void>(method, args);
  }

  Stream<Map<String, dynamic>> get events {
    _events ??= _eventChannel.receiveBroadcastStream().map(
      (e) => (e as Map).cast<String, dynamic>(),
    );
    return _events!;
  }
}
