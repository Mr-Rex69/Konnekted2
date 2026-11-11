import 'dart:io';

import 'package:flutter/services.dart';

import '../playback_cache_preferences_service.dart';

/// Cast receivers fetch HTTP bytes; they cannot open the sender's SAF grant.
/// Use the existing bounded original-file staging cache without transcoding.
Future<String?> castLocalFile(
  String? source, {
  required String extension,
}) async {
  if (source == null || source.isEmpty) return null;
  var path = source;
  final uri = Uri.tryParse(source);
  if (uri?.scheme == 'content') {
    final limit = await PlaybackCachePreferencesService().getMaxCacheBytes();
    path =
        await const MethodChannel('com.mossapps.flick/storage')
            .invokeMethod<String>('cacheUriForPlayback', {
              'uri': source,
              'extensionHint': extension,
              'maxStagingBytes': limit,
            }) ??
        '';
  } else if (uri != null && uri.scheme == 'file') {
    path = uri.toFilePath();
  }
  if (path.isEmpty || !await File(path).exists()) return null;
  return path;
}
