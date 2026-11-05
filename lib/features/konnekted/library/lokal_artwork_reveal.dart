import 'package:flutter/material.dart';

/// Crossfades a late album cover or artist portrait without touching the
/// surrounding route, header chrome or page background.
///
/// The previous source remains visible until the replacement completes.
/// Actual image decoding is handled by CachedImageWidget.revealOnLoad.
class LokalArtworkReveal extends StatelessWidget {
  const LokalArtworkReveal({
    super.key,
    required this.identity,
    required this.child,
  });

  final String identity;
  final Widget child;

  static const duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [
          ...previousChildren,
          ?currentChild,
        ],
      ),
      child: SizedBox.expand(
        key: ValueKey(identity),
        child: child,
      ),
    ),
  );
}
