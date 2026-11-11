import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Reconcile the shared iOS audio options after a silent video plugin changes
/// them. Native code repairs only published, playing local music; it never
/// activates a session or takes audio ownership from idle/remote playback.
Future<void> restoreIosNowPlayingAfterSilentVideo() async {
  if (kIsWeb || !Platform.isIOS) return;
  try {
    await const MethodChannel('lokal/ios')
        .invokeMethod<void>('restoreNowPlayingAfterSilentVideo');
  } on MissingPluginException {
    // Other hosts and older native test bridges have no iOS session owner.
  } on PlatformException {
    // Decorative video must not fail playback; later metadata reconciles again.
  }
}
