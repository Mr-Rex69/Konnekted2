import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'full_player_visuals.dart';

/// Paint a second view of the cover's existing texture, not a second video
/// player/controller. Native frames flow straight through the GPU blur.
class MotionCoverBlur extends StatelessWidget {
  const MotionCoverBlur({
    super.key,
    required this.controller,
    required this.fullCover,
  });
  final VideoPlayerController controller;
  final bool fullCover;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          if (!value.isInitialized || value.hasError || value.size.isEmpty) {
            return const SizedBox.shrink();
          }
          return IgnorePointer(
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 28,
                      sigmaY: 28,
                      tileMode: TileMode.clamp,
                    ),
                    child: Transform.scale(
                      scale: 1.12,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: value.size.width,
                          height: value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [.62, .56, fullCover ? .26 : .32, .56, .68]
                            .map(
                              (alpha) => FullPlayerVisuals.scrim.withValues(
                                alpha: alpha,
                              ),
                            )
                            .toList(),
                        stops: const [0, .18, .36, .56, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
