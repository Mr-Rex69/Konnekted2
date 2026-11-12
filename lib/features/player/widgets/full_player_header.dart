import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/core/constants/app_constants.dart';

import 'full_player_visuals.dart';

/// Lightweight, artwork-responsive frost shared by Android and iOS.
///
/// Unlike the larger moving mini-player, small static header buttons do not
/// need a refractive shader. They use one shared, clipped Gaussian backdrop
/// blur, a nearly clear neutral fill and a hairline highlight instead of an
/// opaque black scrim. Artwork brightness determines foreground contrast.
class FullPlayerHeader extends StatelessWidget {
  const FullPlayerHeader({
    super.key,
    required this.deviceLabel,
    required this.outputIcon,
    required this.isCasting,
    required this.onClose,
    required this.onOutput,
    required this.onCast,
    required this.onMore,
    this.brightArtwork = false,
  });

  final String deviceLabel;
  final IconData outputIcon;
  final bool isCasting;
  final VoidCallback onClose, onOutput, onCast, onMore;

  /// True when a bright full-bleed cover is directly behind the controls.
  /// Dark gradient/background modes keep the white foreground.
  final bool brightArtwork;

  // Strong dark foreground contrasts with translucent frost on midtone covers.
  static const Color _darkInk = Color(0xFF0B1118);
  // Reuse the native blur filter across rebuilds and all four controls.
  static final ImageFilter _frostFilter = ImageFilter.blur(
    sigmaX: 3.5,
    sigmaY: 3.5,
  );

  Color _foreground(double brightness) =>
      Color.lerp(FullPlayerVisuals.primaryText, _darkInk, brightness)!;

  List<Shadow> _glyphShadow(double brightness) => [
    Shadow(
      color: Color.lerp(
        Colors.black.withValues(alpha: .28),
        Colors.white.withValues(alpha: .18),
        brightness,
      )!,
      blurRadius: 2,
    ),
  ];

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // One continuous value keeps the label, glyphs and their soft contrast
    // shadows together. Rapid skips retarget from the currently painted ink.
    tween: Tween<double>(end: brightArtwork ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppConstants.animationVerySlow,
    curve: Curves.easeInOutCubic,
    builder: (context, brightness, _) => _buildHeader(brightness),
  );

  Widget _buildHeader(double brightness) => SizedBox(
    height: 58,
    child: BackdropGroup(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            top: 7,
            child: _action(
              LucideIcons.chevronLeft,
              lokalText('Back'),
              onClose,
              brightness,
            ),
          ),
          Padding(
            // The right-hand Cast + More cluster is wider than Back.
            // Reserve equal space on both sides to center the output pill.
            padding: const EdgeInsets.symmetric(horizontal: 102),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 215),
                child: _surface(
                  label: deviceLabel,
                  onTap: onOutput,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            outputIcon,
                            size: 17,
                            color: _foreground(brightness),
                            shadows: _glyphShadow(brightness),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              deviceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'GoogleSansFlex',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _foreground(brightness),
                                shadows: _glyphShadow(brightness),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 7,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _action(
                  LucideIcons.cast,
                  lokalText('Cast'),
                  onCast,
                  brightness,
                  selected: isCasting,
                ),
                const SizedBox(width: 6),
                _action(
                  Icons.more_vert,
                  lokalText('More options'),
                  onMore,
                  brightness,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap,
    double brightness, {
    bool selected = false,
  }) => _surface(
    label: label,
    onTap: onTap,
    selected: selected,
    child: SizedBox.square(
      dimension: 44,
      child: Icon(
        icon,
        size: 20,
        color: _foreground(brightness),
        shadows: _glyphShadow(brightness),
      ),
    ),
  );

  Widget _surface({
    required String label,
    required VoidCallback onTap,
    required Widget child,
    bool selected = false,
  }) => Semantics(
    label: label,
    button: true,
    selected: selected,
    onTap: onTap,
    child: ExcludeSemantics(
      child: Tooltip(
        message: label,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter.grouped(
            // The same inexpensive frost as the footer, without a lens,
            // custom fragment shader, or separate vibrancy pass. BackdropGroup
            // lets the three isolated buttons reuse a single backdrop read.
            filter: _frostFilter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(
                  alpha: brightArtwork
                      ? (selected ? .22 : .15)
                      : (selected ? .19 : .12),
                ),
                border: Border.all(
                  width: .75,
                  color: Colors.white.withValues(
                    alpha: brightArtwork ? .30 : .21,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onTap,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
