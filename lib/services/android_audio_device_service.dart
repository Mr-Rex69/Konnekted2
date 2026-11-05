import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flick/services/uac2_service.dart';
import 'package:flick/core/utils/dev_log.dart';

class AndroidPlaybackDeviceInfo {
  const AndroidPlaybackDeviceInfo({
    required this.hasUsbDac,
    required this.hasAttachedUac2Device,
    required this.manufacturer,
    required this.model,
    this.routeType,
    this.routeLabel,
  });

  final bool hasUsbDac;
  final bool hasAttachedUac2Device;
  final String manufacturer;
  final String model;
  final String? routeType;
  final String? routeLabel;

  bool get isUsbRoute => routeType == 'usb';
  bool get isInternalRoute => routeType == 'internal';
  bool get isWiredRoute => routeType == 'wired';
  bool get isBluetoothRoute => routeType == 'bluetooth';
  bool get isDockRoute => routeType == 'dock';
  bool get looksLikeUsbAudioRoute {
    final summary = routeSummary.toLowerCase();
    return summary.contains('usb') || summary.contains('dac');
  }

  bool get isLikelyDap {
    final haystack = '${manufacturer.toLowerCase()} ${model.toLowerCase()}';
    const dapKeywords = <String>[
      'fiio',
      'ibasso',
      'hiby',
      'shanling',
      'astell',
      'iriver',
      'cayin',
      'sony',
      'tempotec',
      'luxury',
      'luxuryprecision',
    ];
    return dapKeywords.any(haystack.contains);
  }

  bool get isXiaomiDevice {
    final haystack = '${manufacturer.toLowerCase()} ${model.toLowerCase()}';
    return haystack.contains('xiaomi') ||
        haystack.contains('redmi') ||
        haystack.contains('poco') ||
        haystack.contains('miui');
  }

  String get routeSummary => routeLabel ?? routeType ?? 'unknown';

  factory AndroidPlaybackDeviceInfo.fromMap(Map<Object?, Object?> raw) {
    return AndroidPlaybackDeviceInfo(
      hasUsbDac: raw['hasUsbDac'] == true,
      hasAttachedUac2Device:
          raw['hasAttachedUac2Device'] == true || raw['hasUsbDac'] == true,
      manufacturer: raw['manufacturer'] as String? ?? '',
      model: raw['model'] as String? ?? '',
      routeType: raw['routeType'] as String?,
      routeLabel: raw['routeLabel'] as String?,
    );
  }

  static const unknown = AndroidPlaybackDeviceInfo(
    hasUsbDac: false,
    hasAttachedUac2Device: false,
    manufacturer: '',
    model: '',
  );
}

/// Identical route probes must not emit a second session-change event.
@visibleForTesting
bool sameAndroidPlaybackDeviceSnapshot(AndroidPlaybackDeviceInfo first, AndroidPlaybackDeviceInfo second) =>
  first.hasUsbDac == second.hasUsbDac && first.hasAttachedUac2Device == second.hasAttachedUac2Device &&
  first.routeType == second.routeType && first.routeLabel == second.routeLabel &&
  first.manufacturer == second.manufacturer && first.model == second.model;

class AndroidAudioDeviceService {
  AndroidAudioDeviceService._();

  static final AndroidAudioDeviceService instance =
      AndroidAudioDeviceService._();

  static const MethodChannel _channel = MethodChannel(
    'com.mossapps.flick/audio_device',
  );

  final ValueNotifier<AndroidPlaybackDeviceInfo> deviceInfoNotifier =
      ValueNotifier(AndroidPlaybackDeviceInfo.unknown);

  /// Media route (speaker/Bluetooth/USB) queried by actual USAGE_MEDIA
  /// attributes on Android 13+. Separate from the song engine's device
  /// inventory, which may prefer a connected device that isn't active.
  final ValueNotifier<AndroidPlaybackDeviceInfo> mediaOutputInfoNotifier =
      ValueNotifier(AndroidPlaybackDeviceInfo.unknown);

  bool _channelConfigured = false;
  Future<void>? _initializeInFlight;
  Future<AndroidPlaybackDeviceInfo>? _refreshInFlight;
  Future<AndroidPlaybackDeviceInfo>? _mediaRefreshInFlight;

  /// Android owns Bluetooth/speaker media routing; opening its chooser avoids
  /// pretending that a communication-device API can route media/USB audio.
  Future<bool> showOutputSwitcher() async =>
      await _channel.invokeMethod<bool>('showOutputSwitcher') ?? false;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    final inFlight = _initializeInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _initializeInternal();
    _initializeInFlight = future;
    try {
      await future;
    } finally {
      _initializeInFlight = null;
    }
  }

  Future<AndroidPlaybackDeviceInfo> refresh() async {
    if (!Platform.isAndroid) {
      return AndroidPlaybackDeviceInfo.unknown;
    }

    if (Uac2Service.instance.shouldFreezeAndroidDirectUsbSessionQueries) {
      return deviceInfoNotifier.value;
    }

    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _refreshInternal();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<AndroidPlaybackDeviceInfo> refreshMediaOutput() async {
    if (!Platform.isAndroid) return mediaOutputInfoNotifier.value;
    final inFlight = _mediaRefreshInFlight;
    if (inFlight != null) return inFlight;
    final pending = _refreshMediaOutputInternal();
    _mediaRefreshInFlight = pending;
    try {
      return await pending;
    } finally {
      if (identical(_mediaRefreshInFlight, pending)) {
        _mediaRefreshInFlight = null;
      }
    }
  }

  Future<AndroidPlaybackDeviceInfo> _refreshMediaOutputInternal() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getMediaOutputDeviceInfo',
      );
      if (raw == null) return mediaOutputInfoNotifier.value;
      final route = AndroidPlaybackDeviceInfo.fromMap(raw);
      if (!sameAndroidPlaybackDeviceSnapshot(
        mediaOutputInfoNotifier.value,
        route,
      )) {
        mediaOutputInfoNotifier.value = route;
      }
    } catch (error) {
      devLog('AndroidAudioDeviceService.mediaRoute failed: $error');
    }
    return mediaOutputInfoNotifier.value;
  }

  Future<void> _initializeInternal() async {
    if (!_channelConfigured) {
      _channelConfigured = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onPlaybackDevicesChanged') {
          devLog('[Engine] Audio device change detected');
          if (Uac2Service.instance.shouldFreezeAndroidDirectUsbSessionQueries) {
            return;
          }
          await refresh();
          await refreshMediaOutput();
        }
      });
    }

    await refresh();
    await refreshMediaOutput();
  }

  Future<AndroidPlaybackDeviceInfo> _refreshInternal() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getPlaybackDeviceInfo',
      );
      final info = raw == null
          ? AndroidPlaybackDeviceInfo.unknown
          : AndroidPlaybackDeviceInfo.fromMap(raw);
      deviceInfoNotifier.value = info;
      return info;
    } catch (e) {
      devLog('AndroidAudioDeviceService.refresh failed: $e');
      deviceInfoNotifier.value = AndroidPlaybackDeviceInfo.unknown;
      return AndroidPlaybackDeviceInfo.unknown;
    }
  }
}
