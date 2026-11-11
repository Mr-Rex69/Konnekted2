import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';

import 'full_player_visuals.dart';

/// Artwork can be white even when the ambient backdrop is dark. Give each
/// header control its own guaranteed dark glass, independent of the cover.
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
  });

  final String deviceLabel;
  final IconData outputIcon;
  final bool isCasting;
  final VoidCallback onClose, onOutput, onCast, onMore;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: BackdropGroup(
      child: Row(
        children: [
          _action(LucideIcons.chevronLeft, lokalText('Back'), onClose),
          const SizedBox(width: 8),
          Expanded(
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
                            color: FullPlayerVisuals.primaryText,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              deviceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'GoogleSansFlex',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: FullPlayerVisuals.primaryText,
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
          const SizedBox(width: 8),
          _action(
            LucideIcons.cast,
            lokalText('Cast'),
            onCast,
            selected: isCasting,
          ),
          const SizedBox(width: 6),
          _action(Icons.more_vert, lokalText('More options'), onMore),
        ],
      ),
    ),
  );

  Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool selected = false,
  }) => _surface(
    label: label,
    onTap: onTap,
    selected: selected,
    child: SizedBox.square(
      dimension: 44,
      child: Icon(icon, size: 22, color: FullPlayerVisuals.primaryText),
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
        child: LokalGlass.capsule(
          tint: FullPlayerVisuals.scrim,
          grouped: true,
          shadow: false,
          singlePassLens: true,
          backdropBlurSigma: 12,
          liquidTintOpacity: selected
              ? FullPlayerVisuals.headerSelectedOpacity
              : FullPlayerVisuals.headerOpacity,
          fallbackTintOpacity: selected
              ? FullPlayerVisuals.headerSelectedOpacity
              : FullPlayerVisuals.headerOpacity,
          performanceTintOpacity: FullPlayerVisuals.headerPerformanceOpacity,
          pronouncedRim: true,
          rimStrength: selected ? 1.2 : .8,
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
  );
}
