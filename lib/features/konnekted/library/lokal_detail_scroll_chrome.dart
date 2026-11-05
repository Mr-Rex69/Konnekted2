import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';

/// BitChord's top chrome uses a distinct progressive backdrop layer, rather
/// than blurring the portrait. Begin as the header starts leaving and finish
/// before the last of its artwork has scrolled away.
@visibleForTesting
double detailTopFrostOpacity(double offset, double heroHeight) {
  if (heroHeight <= 0 || offset <= 0) return 0;
  final progress = ((offset / heroHeight - .55) / .30).clamp(0.0, 1.0).toDouble();
  return progress * progress * (3 - 2 * progress);
}

/// A fixed, hit-test-transparent blur of the *scrolling page behind it*.
/// The source remains outside this overlay in the page Stack, analogous to
/// BitChord's shared Haze source and floating TopFadeBlur.
//
/// Do not blur/crossfade a copy of the portrait here. Blur is sampled from the
/// live page after the scroll view has painted, so rows passing under the top
/// controls are softened too. Only this small layer rebuilds as we scroll.
class LokalDetailProgressiveTopBlur extends StatelessWidget {
  const LokalDetailProgressiveTopBlur({
    super.key,
    required this.scrollController,
    required this.heroHeight,
    required this.background,
    this.dynamicBlur = true,
  });

  final ScrollController scrollController;
  final double heroHeight;
  final Color background;
  final bool dynamicBlur;

  static const double controlsHeight = 76;
  static const double fadeRun = 16;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.paddingOf(context).top +
        controlsHeight +
        fadeRun;
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
        final offset = scrollController.hasClients
            ? scrollController.offset
            : scrollController.initialScrollOffset;
        final opacity = detailTopFrostOpacity(offset, heroHeight);
        if (opacity <= 0) return const SizedBox.shrink();

        return IgnorePointer(
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .60, .68, .76, .84, .92, 1],
                    colors: [
                      Colors.black,
                      Colors.black,
                      Color(0xF0FFFFFF),
                      Color(0xD6FFFFFF),
                      Color(0x95FFFFFF),
                      Color(0x37FFFFFF),
                      Colors.transparent,
                    ],
                  ).createShader(bounds),
                  child: dynamicBlur
                      ? BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 14,
                            sigmaY: 14,
                          ),
                          child: const SizedBox.expand(),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(color: background),
                          child: const SizedBox.expand(),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floating header controls live *above* the page, not in the scrolling
/// artist/album sliver. They remain tappable as the progressive frost samples
/// the feed underneath, just like BitChord's app-level top bar.
class LokalDetailFloatingControls extends StatelessWidget {
  const LokalDetailFloatingControls({
    super.key,
    required this.title,
    required this.onBack,
    required this.onOnline,
    required this.onMore,
    required this.onlineEnabled,
    this.onlineLoading = false,
    this.onlineDisabled = false,
    required this.scrollController,
    required this.heroHeight,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onOnline;
  final VoidCallback onMore;
  final bool onlineEnabled;
  final bool onlineLoading;
  final bool onlineDisabled;
  final ScrollController scrollController;
  final double heroHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              LokalGlassButton(
                semanticLabel: lokalText('Back'),
                tint: Colors.black.withValues(alpha: .16),
                onPressed: onBack,
                child: Icon(Icons.arrow_back_rounded,
                    color: t.text, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedBuilder(
                  animation: scrollController,
                  builder: (context, _) {
                    final offset = scrollController.hasClients
                        ? scrollController.offset
                        : 0.0;
                    final alpha = detailTopFrostOpacity(offset, heroHeight);
                    return Opacity(
                      opacity: alpha,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              LokalGlassButton(
                semanticLabel: onlineEnabled
                    ? lokalText('Disable online catalogue')
                    : lokalText('Enable online catalogue'),
                onPressed: onlineLoading || onlineDisabled ? null : onOnline,
                tint: onlineEnabled
                    ? t.accent.withValues(alpha: .28)
                    : Colors.black.withValues(alpha: .16),
                child: onlineLoading
                    ? const SizedBox.square(
                        dimension: 21,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        onlineEnabled
                            ? Icons.language_rounded
                            : Icons.language_outlined,
                        color: onlineEnabled ? t.accent : t.text,
                        size: 23,
                      ),
              ),
              const SizedBox(width: 10),
              LokalGlassButton(
                semanticLabel: lokalText('More'),
                onPressed: onMore,
                tint: Colors.black.withValues(alpha: .16),
                child: Icon(Icons.more_horiz_rounded,
                    color: t.text, size: 23),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
