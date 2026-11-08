import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Let iOS resize the complete login page when WebKit opens the keyboard.
/// A fixed-height draggable bottom sheet can steal the page's scroll gesture
/// and leave its submit button underneath the keyboard.
class WebSignInFrame extends StatelessWidget {
  const WebSignInFrame({
    super.key,
    required this.fullscreen,
    required this.child,
  });

  final bool fullscreen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    if (fullscreen) {
      return Scaffold(
        backgroundColor: surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(child: child),
      );
    }
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          height: math.min(
            MediaQuery.sizeOf(context).height * .92,
            constraints.maxHeight,
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}
