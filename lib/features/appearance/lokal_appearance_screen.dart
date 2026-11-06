import 'package:flick/features/appearance/lokal_performance_selector.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_style.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';

/// Desktop Lokal's Appearance settings, for the phone.
///
/// Every change applies at once and cross-fades through the app theme, so
/// the screen itself is the preview.
class LokalAppearanceScreen extends ConsumerWidget {
  const LokalAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(lokalAppearanceProvider);
    final notifier = ref.read(lokalAppearanceProvider.notifier);
    final t = context.lokal;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                BackButton(color: t.text),
              ],
            ),
            KonnektedHeading(
              title: lokalText('Appearance'),
              eyebrow: 'Make it yours',
              action: Padding(
                padding: EdgeInsets.only(left: 12),
                child: LokalLogo(size: 52),
              ),
            ),
            _Label(lokalText('Theme')),
            LokalThemeGrid(
              selected: appearance.theme,
              onSelect: (id) {
                HapticFeedback.selectionClick();
                notifier.selectTheme(id);
              },
            ),
            _Label(lokalText('Accent')),
            LokalAccentRow(
              selected: appearance.accent,
              onSelect: (accent) {
                HapticFeedback.selectionClick();
                notifier.setAccent(accent);
              },
            ),
            _Label(lokalText('Display')),
            _Group(
              children: [
                lokalPerformanceSelector(ref),
                Divider(height: 1, color: t.border, indent: 16),
                _TextSize(
                  value: appearance.textScale,
                  onChanged: notifier.setTextScale,
                ),
                Divider(height: 1, color: t.border, indent: 16),
                SwitchListTile.adaptive(
                  title: Text(lokalText('Home greeting and subheader')),
                  subtitle: Text(lokalText(
                    'Show the greeting in Local, Discovery and Flow.',
                  )),
                  value: appearance.showHomeGreeting,
                  onChanged: notifier.setShowHomeGreeting,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: LokalTheme.label(context.lokal)),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Material(
      color: context.lokal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.lokal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    ),
  );
}

/// The ten desktop themes as small previews of themselves.
class LokalThemeGrid extends StatelessWidget {
  const LokalThemeGrid({
    super.key,
    required this.selected,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final LokalThemeId selected;
  final ValueChanged<LokalThemeId> onSelect;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: GridView.count(
      // Nested settings already reserve the system/dock insets. A null grid
      // padding inherits that bottom inset again and leaves a large blank gap.
      padding: EdgeInsets.zero,
      primary: false,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.3,
      children: [
        for (final id in LokalThemeId.values)
          _ThemeSwatch(
            id: id,
            selected: id == selected,
            onTap: () => onSelect(id),
          ),
      ],
    ),
  );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final LokalThemeId id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = context.lokal;
    final preview = LokalTokens.resolve(id);
    return Semantics(
      button: true,
      selected: selected,
      label: lokalText("{arg0} theme", args: {'arg0': id.label}),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: preview.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? current.accent : current.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      id.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: preview.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 6,
                      width: 48,
                      decoration: BoxDecoration(
                        color: preview.surface3,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [preview.accent, preview.accentDim],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Theme" plus the twelve desktop accent presets.
class LokalAccentRow extends StatelessWidget {
  const LokalAccentRow({
    super.key,
    required this.selected,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final LokalAccent? selected;
  final ValueChanged<LokalAccent?> onSelect;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _AccentDot(
          label: lokalText('Theme accent'),
          colors: [context.lokal.accent, context.lokal.accentDim],
          selected: selected == null,
          onTap: () => onSelect(null),
          icon: Icons.auto_awesome_rounded,
        ),
        for (final accent in LokalAccent.presets)
          _AccentDot(
            label: lokalText("{arg0} accent", args: {'arg0': accent.name}),
            colors: [accent.value, accent.dim],
            selected: selected == accent,
            onTap: () => onSelect(accent),
          ),
      ],
    ),
  );
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final onColor = colors.first.computeLuminance() > .5
        ? Colors.black
        : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          // No overshoot: the ring's padding must never go negative.
          curve: Curves.easeOutCubic,
          width: 44,
          height: 44,
          padding: EdgeInsets.all(selected ? 4 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? t.text : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: icon == null
                ? null
                : Icon(icon, size: 16, color: onColor.withValues(alpha: .8)),
          ),
        ),
      ),
    );
  }
}

class _TextSize extends StatelessWidget {
  const _TextSize({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(lokalText('Text size'))),
            Text(
              lokalText("{arg0}%", args: {'arg0': (value * 100).round()}),
              style: LokalTheme.label(context.lokal, size: 12),
            ),
          ],
        ),
        Slider(
          value: value,
          min: LokalAppearance.minTextScale,
          max: LokalAppearance.maxTextScale,
          divisions: 16,
          label: lokalText("{arg0}%", args: {'arg0': (value * 100).round()}),
          semanticFormatterCallback: (v) => '${(v * 100).round()} percent',
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
