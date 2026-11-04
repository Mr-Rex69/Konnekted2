import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

LokalSettingRow lokalPerformanceSelector(WidgetRef ref) {
  final level = ref.watch(
    lokalAppearanceProvider.select((look) => look.performanceLevel),
  );
  return LokalSettingRow(
    label: 'Performance mode',
    description: switch (level) {
      LokalPerformanceLevel.full => 'Glass surfaces and animated artwork.',
      LokalPerformanceLevel.performance =>
        'Solid surfaces with animated artwork. Recommended for most phones.',
      LokalPerformanceLevel.ultra => 'Still artwork, flat cover flow and lighter lyrics. For less powerful phones.',
    },
    stacked: true,
    trailing: LokalSegmented<LokalPerformanceLevel>(
      value: level,
      segments: const [
        LokalSegment(LokalPerformanceLevel.full, 'Off'),
        LokalSegment(LokalPerformanceLevel.performance, 'Performance'),
        LokalSegment(LokalPerformanceLevel.ultra, 'Ultra'),
      ],
      onChanged: ref.read(lokalAppearanceProvider.notifier).setPerformanceLevel,
    ),
  );
}
