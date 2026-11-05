import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';

/// Shared album/artist title and controls. Detail pages can paint their
/// artwork in a stationary layer behind this scrollable, transparent header.
class LokalDetailHeader extends StatelessWidget {
  const LokalDetailHeader({
    super.key,
    required this.title,
    required this.artwork,
    required this.isArtist,
    this.fixedArtwork = false,
    this.controlsInOverlay = false,
    required this.background,
    required this.onBack,
    required this.onArtworkTap,
    required this.onOnline,
    required this.onlineEnabled,
    this.onlineLoading = false,
    this.onlineDisabled = false,
    required this.onMore,
    this.artistCredit,
    this.metadata,
    this.artworkHeroTag,
    this.artistLogoPath,
    this.artistLogoAspect = 1,
  });

  final String title;
  final Widget artwork;
  final Widget? artistCredit;
  final String? metadata;
  final String? artworkHeroTag;
  final String? artistLogoPath;
  final double artistLogoAspect;
  final bool isArtist;
  /// When true, the artwork is painted behind the entire scroll view rather
  /// than inside this moving header. The header remains transparent.
  final bool fixedArtwork;
  /// True when the page draws its top controls above the scroll view.
  final bool controlsInOverlay;
  final Color background;
  final VoidCallback onBack, onOnline, onMore, onArtworkTap;
  final bool onlineEnabled;
  final bool onlineLoading;
  final bool onlineDisabled;

  static double artistHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return (size.height * .52 + (scale - 1) * 90)
        .clamp(350.0, 580.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final size = MediaQuery.sizeOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    final topInset = MediaQuery.paddingOf(context).top;
    final fullBleed = isArtist || fixedArtwork;
    final artSize = (size.width * (size.width > 620 ? .36 : .63))
        .clamp(184.0, 314.0);
    final heroHeight = fullBleed
        ? artistHeight(context)
        : artSize + 268 + topInset + (scale - 1) * 230;

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!fixedArtwork) DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: isArtist
                    ? const Alignment(0, -.5)
                    : const Alignment(0, -.2),
                radius: 1.15,
                colors: [Color.lerp(background, t.accent, .10)!, background],
              ),
            ),
          ),
          if (fixedArtwork)
            GestureDetector(
              onTap: onArtworkTap,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: lokalText('View artwork'),
                child: const SizedBox.expand(),
              ),
            )
          else if (isArtist) ...[
            GestureDetector(
              onTap: onArtworkTap,
              behavior: HitTestBehavior.opaque,
              child: RepaintBoundary(child: artwork),
            ),
            // A full-size decoration sits *above* the portrait. Without
            // IgnorePointer, its RenderDecoratedBox wins hit testing and
            // consumes taps before the artwork's GestureDetector can open
            // the fullscreen viewer.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Preserve contrast for the title without tinting the
                  // edge of the photo with the page background color.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .68, .93, 1],
                    colors: [
                      Colors.black.withValues(alpha: .10),
                      Colors.transparent,
                      Colors.black.withValues(alpha: .15),
                      Colors.black.withValues(alpha: .45),
                    ],
                  ),
                ),
              ),
            ),
          ] else
            Positioned(
              top: topInset + 76,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  width: artSize,
                  height: artSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .25),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: onArtworkTap,
                    child: ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: artworkHeroTag == null
                        ? RepaintBoundary(child: artwork)
                        : Hero(
                            tag: artworkHeroTag!,
                            child: RepaintBoundary(child: artwork),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          if (!controlsInOverlay) Positioned(
            left: 20,
            right: 20,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    _headerButton(
                      context,
                      Icons.arrow_back_rounded,
                      l10n.back,
                      onBack,
                    ),
                    const Spacer(),
                    // The catalogue is a single icon-only toggle in the
                    // header. Its state is exposed to assistive technology,
                    // not as a separate label or description on the page.
                    LokalGlassButton(
                      semanticLabel: onlineEnabled
                          ? lokalText('Disable online catalogue')
                          : lokalText('Enable online catalogue'),
                      onPressed: (onlineLoading || onlineDisabled) ? null : onOnline,
                      tint: onlineEnabled
                          ? t.accent.withValues(alpha: .28)
                          : Colors.black.withValues(alpha: .16),
                      child: onlineLoading
                          ? SizedBox.square(
                              dimension: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: fullBleed ? Colors.white : t.text,
                              ),
                            )
                          : Icon(
                              onlineEnabled
                                  ? Icons.language_rounded
                                  : Icons.language_outlined,
                              // The active catalogue state must remain clear
                              // on both dark artwork and light album headers.
                              color: onlineEnabled
                                  ? t.accent
                                  : (fullBleed ? Colors.white : t.text),
                              size: 23,
                            ),
                    ),
                    const SizedBox(width: 10),
                    _headerButton(
                      context,
                      Icons.more_horiz_rounded,
                      lokalText('More'),
                      onMore,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isArtist ? 'ARTIST' : 'ALBUM',
                  style: LokalTheme.label(
                    t,
                    size: 11,
                    color: fullBleed
                        ? Colors.white.withValues(alpha: .78)
                        : t.muted,
                  ),
                ),
                const SizedBox(height: 8),

                Semantics(
                  header: true,
                  label: isArtist && artistLogoPath?.isNotEmpty == true ? title : null,
                  child: isArtist && artistLogoPath?.isNotEmpty == true
                      ? Image.file(
                          File(artistLogoPath!),
                          width: (size.width - 48) * .82,
                          height: ((size.width - 48) * .82 /
                                  artistLogoAspect.clamp(.4, 6))
                              .clamp(64.0, heroHeight * .27),
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          // Disk-backed logo: never flash plain text while
                          // image decoding completes after reopening the page.
                          errorBuilder: (context, error, stackTrace) =>
                              _plainTitle(context, fullBleed),
                        )
                      : _plainTitle(context, fullBleed),
                ),
                if (artistCredit != null) ...[
                  const SizedBox(height: 9),
                  artistCredit!,
                ],
                if (metadata?.isNotEmpty == true) ...[
                  const SizedBox(height: 9),
                  Text(
                    metadata!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fullBleed ? Colors.white70 : t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _plainTitle(BuildContext context, bool fullBleed) {
    final t = context.lokal;
    return Text(
      title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: LokalTheme.sans,
        fontSize: fullBleed ? 43 : 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.35,
        height: 1.06,
        color: fullBleed ? Colors.white : t.text,
        shadows: fixedArtwork
            ? null
            : (isArtist
                ? const [Shadow(color: Color(0x55000000), blurRadius: 5)]
                : null),
      ),
    );
  }

  Widget _headerButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) => LokalGlassButton(
    semanticLabel: label,
    onPressed: onTap,
    tint: Colors.black.withValues(alpha: .16),
    child: Icon(icon, color: isArtist || fixedArtwork ? Colors.white : context.lokal.text, size: 23),
  );
}
