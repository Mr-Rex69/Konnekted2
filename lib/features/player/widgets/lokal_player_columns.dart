import 'package:flutter/widgets.dart';

import 'package:flick/core/utils/lokal_layout.dart';

/// Shared composition for local, radio and desktop-controlled playback.
/// Landscape puts the stage beside a scrollable control column; portrait
/// retains each player's original vertical ordering and sizing.
class LokalPlayerColumns extends StatelessWidget {
  const LokalPlayerColumns({
    super.key,
    required this.header,
    required this.stage,
    required this.controls,
    this.expandPortraitStage = true,
    this.landscapeHeight,
  });

  final Widget header, stage, controls;
  final bool expandPortraitStage;
  final double? landscapeHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final wide =
          LokalLayout.isTablet(context) &&
          constraints.maxWidth >= 720 &&
          media.size.width > media.size.height;
      if (!wide) {
        return Column(
          mainAxisSize: expandPortraitStage
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            header,
            if (expandPortraitStage) Expanded(child: stage) else stage,
            controls,
          ],
        );
      }
      return SizedBox(
        height: landscapeHeight,
        child: Column(
          children: [
            header,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 28, 20),
                      child: _pane(context, stage),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _pane(
                      context,
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 24, 16, 24),
                          child: controls,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _pane(BuildContext context, Widget child) => LayoutBuilder(
    builder: (context, constraints) => LokalContentScope(
      tablet: true,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(size: constraints.biggest),
        child: child,
      ),
    ),
  );
}
