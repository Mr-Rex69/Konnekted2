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
    this.fillCover = false,
    this.preferColumns = false,
  });

  final Widget header, stage, controls;
  final bool expandPortraitStage;
  final double? landscapeHeight;
  final bool fillCover;
  final bool preferColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          LokalLayout.isLandscapeTablet(context) && constraints.maxWidth >= 720;
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
                      padding: fillCover
                          ? const EdgeInsets.only(right: 24)
                          : const EdgeInsets.fromLTRB(16, 8, 28, 20),
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

/// Metadata belongs with the transport in either tablet artwork mode. Short
/// windows tighten the rhythm; the containing column remains scrollable.
class LokalPlayerControls extends StatelessWidget {
  const LokalPlayerControls({
    super.key,
    required this.heading,
    required this.identity,
    required this.timeline,
    required this.transport,
    required this.options,
    required this.footer,
    required this.compact,
  });
  final Widget heading, identity, timeline, transport, options, footer;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading,
      SizedBox(height: compact ? 12 : 20),
      identity,
      SizedBox(height: compact ? 16 : 24),
      timeline,
      SizedBox(height: compact ? 16 : 24),
      transport,
      SizedBox(height: compact ? 16 : 24),
      options,
      SizedBox(height: compact ? 12 : 20),
      footer,
    ],
  );
}
