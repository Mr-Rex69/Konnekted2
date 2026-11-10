import 'package:flutter/widgets.dart';

/// Keep the single video surface at its natural widescreen ratio, exposing
/// the player's continuous backdrop instead of a black square around it.
/// This also preserves the complete official embed and its native controls.
class PlayerVideoFrame extends StatelessWidget {
  const PlayerVideoFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(aspectRatio: 16 / 9, child: child),
  );
}
