import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// A borrowed presentation surface. Its MotionArtView owns the decoder and
/// alone decides whether it can play; the blur never acquires a video lease.
class MotionArtFrame {
  const MotionArtFrame({required this.owner, required this.controller});
  final Object owner;
  final VideoPlayerController? controller;
}

/// Scoped to one player. Owner identity prevents an outgoing cover's teardown
/// from clearing a replacement cover while full-cover/card layouts exchange.
class MotionArtFrameSource extends ChangeNotifier {
  final _frames = <Object, (String, VideoPlayerController)>{};
  bool _pending = false, _disposed = false;

  VideoPlayerController? forKey(String key) {
    for (final entry in _frames.values.toList().reversed) {
      if (entry.$1 == key) return entry.$2;
    }
    return null;
  }

  void update(String key, MotionArtFrame frame) {
    if (_disposed) return;
    final controller = frame.controller;
    if (controller == null) {
      if (_frames.remove(frame.owner) == null) return;
    } else {
      if (_frames[frame.owner] == (key, controller)) return;
      _frames.remove(frame.owner);
      _frames[frame.owner] = (key, controller);
    }
    if (_pending) return;
    _pending = true;
    // Warm controller handoffs and teardown can occur during widget build.
    // Notify the sibling backdrop after that synchronous frame has completed.
    scheduleMicrotask(() {
      _pending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _frames.clear();
    super.dispose();
  }
}
