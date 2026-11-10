import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Window geometry, independent of device names and physical screen pixels.
abstract final class LokalLayout {
  static bool usesSidebar(Size size) => size.width >= 600 && size.height >= 480;

  static bool isTablet(BuildContext context) =>
      LokalContentScope.maybeOf(context)?.tablet ??
      usesSidebar(MediaQuery.sizeOf(context));

  static int columns(double width, {double target = 190, int min = 2}) =>
      ((width + 16) / (target + 16)).floor().clamp(min, 8);

  /// Use the display, not the letterboxed app window, when restoring rotation.
  static List<DeviceOrientation> defaultOrientations({FlutterView? view}) {
    final display = (view ?? PlatformDispatcher.instance.views.first).display;
    final size = display.size / display.devicePixelRatio;
    return size.shortestSide >= 600
        ? const []
        : const [DeviceOrientation.portraitUp];
  }
}

/// Keeps tablet identity when a sidebar leaves a phone-width content pane.
class LokalContentScope extends InheritedWidget {
  const LokalContentScope({
    super.key,
    required this.tablet,
    required super.child,
  });
  final bool tablet;

  static LokalContentScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LokalContentScope>();

  @override
  bool updateShouldNotify(LokalContentScope oldWidget) =>
      tablet != oldWidget.tablet;
}
