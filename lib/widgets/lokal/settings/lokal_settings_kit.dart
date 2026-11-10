import '../lokal_page_geometry.dart';

import 'package:flick/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

import 'lokal_settings_surfaces.dart';

export 'lokal_settings_surfaces.dart';

/// Lokal's settings kit: desktop's `Section` and `Row` (src/pages/Settings.jsx)
/// for the phone.
///
/// Every row carries its label and description as plain fields, so a
/// [LokalSettingsSection] can be cut down to the rows that match a search
/// without building them, like desktop's settings search.

/// A row that the settings search can find.
abstract interface class LokalSearchable {
  /// The text the search looks in: the label and the description.
  String get searchText;
}

/// Whether [text] matches the settings search [query], case-insensitively.
bool lokalSettingsMatch(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return text.toLowerCase().contains(q);
}

String _searchText(String label, String? description) => description == null
    ? lokalText(label)
    : '${lokalText(label)} ${lokalText(description)}';

/// A DM Mono title over a solid card of rows.
class LokalSettingsSection extends StatelessWidget {
  const LokalSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.heading,
  });

  /// The section's name, also what a deep link to it uses.
  final String title;

  /// Shown instead of [title] above the card, e.g. "Playback · Lyrics" in
  /// search results.
  final String? heading;
  final List<Widget> children;

  /// This section cut down to the rows matching [query]: all of it when its
  /// title matches, `null` when nothing does.
  LokalSettingsSection? filtered(String query, {String? heading}) {
    if (query.trim().isEmpty || lokalSettingsMatch(title, query)) {
      return heading == null
          ? this
          : LokalSettingsSection(
              title: title,
              heading: heading,
              children: children,
            );
    }
    final rows = [
      for (final child in children)
        if (child case final LokalSearchable row
            when lokalSettingsMatch(row.searchText, query))
          child,
    ];
    if (rows.isEmpty) return null;
    return LokalSettingsSection(
      title: title,
      heading: heading ?? this.heading,
      children: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Semantics(
              header: true,
              child: Text(
                lokalText(heading ?? title).toUpperCase(),
                style: LokalTheme.label(t),
              ),
            ),
          ),
          LokalSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const LokalSettingsDivider(),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop's settings `Row`: a label, a one-line description and a control.
///
/// [stacked] puts the control under the text at full width, for a control too
/// wide to sit beside it.
class LokalSettingRow extends StatelessWidget implements LokalSearchable {
  const LokalSettingRow({
    super.key,
    required this.label,
    this.description,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.stacked = false,
    this.icon,
    this.toggled,
    this.selected,
  });

  /// An on/off row: an [LokalOnOffPill] that the whole row flips.
  factory LokalSettingRow.toggle({
    Key? key,
    required String label,
    String? description,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    IconData? icon,
  }) => LokalSettingRow(
    key: key,
    label: label,
    description: description,
    enabled: enabled,
    icon: icon,
    toggled: value,
    trailing: LokalOnOffPill(value: value),
    onTap: () => onChanged(!value),
  );

  /// One choice of a list shown as rows: a check on the [selected] one.
  factory LokalSettingRow.option({
    Key? key,
    required String label,
    String? description,
    required bool selected,
    required VoidCallback? onTap,
    IconData? icon,
    bool enabled = true,
  }) => LokalSettingRow(
    key: key,
    label: label,
    description: description,
    icon: icon,
    enabled: enabled,
    onTap: onTap,
    selected: selected,
    trailing: _OptionMark(selected: selected),
  );

  final String label;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool stacked;
  final IconData? icon;

  /// Set for an on/off row, so screen readers announce it as a switch.
  final bool? toggled;

  /// Set for one choice of several, so screen readers announce it.
  final bool? selected;

  @override
  String get searchText => _searchText(lokalText(label), description);

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          lokalText(label),
          style: TextStyle(
            fontFamily: LokalTheme.sans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        if (description != null && description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              lokalText(description!),
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 12.5,
                height: 1.35,
                color: t.muted,
              ),
            ),
          ),
      ],
    );
    final leading = icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(icon, size: 22, color: t.accent),
          );
    Widget body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ?leading,
                  Expanded(child: text),
                ],
              ),
              if (trailing != null) ...[const SizedBox(height: 12), trailing!],
            ],
          )
        : Row(
            children: [
              ?leading,
              Expanded(child: text),
              if (trailing != null) ...[const SizedBox(width: 14), trailing!],
            ],
          );
    body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: body,
    );
    final tap = enabled ? onTap : null;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Semantics(
        button: tap != null && toggled == null,
        toggled: toggled,
        selected: selected,
        enabled: enabled,
        child: tap == null
            ? body
            : InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  tap();
                },
                child: body,
              ),
      ),
    );
  }
}

/// Desktop's inline ON/OFF switch, in DM Mono.
class LokalOnOffPill extends StatelessWidget {
  const LokalOnOffPill({super.key, required this.value, this.onChanged});

  final bool value;

  /// Only for a pill on its own; inside a [LokalSettingRow] the row flips it.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 54,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: value ? t.accent : t.surface3,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: value ? t.accent : t.border2),
      ),
      child: Text(
        value ? lokalText('ON') : lokalText('OFF'),
        style: LokalTheme.label(
          t,
          size: 11,
          color: value ? t.onAccent : t.muted,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    );
    if (onChanged == null) return ExcludeSemantics(child: pill);
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged!(!value);
        },
        child: ExcludeSemantics(child: pill),
      ),
    );
  }
}

/// One choice of a [LokalSegmented].
class LokalSegment<T> {
  const LokalSegment(this.value, this.label, {this.description});

  final T value;
  final String label;

  /// Shown under [label] in a [LokalSettingChoice]'s sheet.
  final String? description;
}

/// Desktop's segmented control, for three choices or fewer.
class LokalSegmented<T> extends StatelessWidget {
  const LokalSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
  });

  final List<LokalSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Fill the width, for a control stacked under its row's text.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    Widget segment(LokalSegment<T> s) {
      final selected = s.value == value;
      final child = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          lokalText(s.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: LokalTheme.sans,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? t.onAccent : t.muted,
          ),
        ),
      );
      return Semantics(
        button: true,
        selected: selected,
        label: s.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null || selected
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onChanged!(s.value);
                },
          child: child,
        ),
      );
    }

    final control = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final s in segments)
            expand ? Expanded(child: segment(s)) : segment(s),
        ],
      ),
    );
    if (expand) return control;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: control,
      ),
    );
  }
}

/// A row with a slider under it and its value in DM Mono.
///
/// The value moves with the finger; [onChanged] is called once it lets go,
/// so a drag doesn't save every step.
class LokalSettingSlider extends StatefulWidget implements LokalSearchable {
  const LokalSettingSlider({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.valueLabel,
    required this.onChanged,
    this.semanticFormatter,
    this.live = false,
    this.onValueTap,
  });

  final String label;
  final String? description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value) valueLabel;
  final ValueChanged<double>? onChanged;
  final String Function(double value)? semanticFormatter;

  /// Calls [onChanged] on every step of a drag too, for a value you hear
  /// change, like an equalizer band.
  final bool live;

  /// Tapping the value, e.g. to type an exact one.
  final VoidCallback? onValueTap;

  @override
  String get searchText => _searchText(lokalText(label), description);

  @override
  State<LokalSettingSlider> createState() => _LokalSettingSliderState();
}

class _LokalSettingSliderState extends State<LokalSettingSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    final enabled = widget.onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lokalText(widget.label),
                        style: TextStyle(
                          fontFamily: LokalTheme.sans,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      if (widget.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            widget.description!,
                            style: TextStyle(
                              fontFamily: LokalTheme.sans,
                              fontSize: 12.5,
                              height: 1.35,
                              color: t.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onValueTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: widget.onValueTap == null
                        ? null
                        : BoxDecoration(
                            color: t.surface3,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: t.border2),
                          ),
                    child: Text(
                      widget.valueLabel(value),
                      style: LokalTheme.label(t, size: 12, color: t.text),
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: t.accent,
                inactiveTrackColor: t.surface3,
                thumbColor: t.accent,
                overlayColor: t.accent.withValues(alpha: .12),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                semanticFormatterCallback:
                    widget.semanticFormatter ?? widget.valueLabel,
                onChanged: enabled
                    ? (v) {
                        setState(() => _dragging = v);
                        if (widget.live) widget.onChanged!(v);
                      }
                    : null,
                onChangeEnd: enabled
                    ? (v) {
                        setState(() => _dragging = null);
                        widget.onChanged!(v);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that opens a sub-page, with an optional current value.
class LokalSettingLink extends StatelessWidget implements LokalSearchable {
  const LokalSettingLink({
    super.key,
    required this.label,
    this.description,
    required this.onTap,
    this.value,
    this.icon,
  });

  final String label;
  final String? description;
  final VoidCallback onTap;
  final String? value;
  final IconData? icon;

  @override
  String get searchText => _searchText(lokalText(label), description);

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return LokalSettingRow(
      label: label,
      description: description,
      icon: icon,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(value!, style: LokalTheme.label(t, size: 12)),
            ),
          Icon(Icons.chevron_right_rounded, size: 22, color: t.muted),
        ],
      ),
    );
  }
}

/// A row for four choices or more: the current one in DM Mono, the rest in a
/// sheet.
class LokalSettingChoice<T> extends StatelessWidget implements LokalSearchable {
  const LokalSettingChoice({
    super.key,
    required this.label,
    this.description,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String? description;
  final List<LokalSegment<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  String get searchText => _searchText(lokalText(label), description);

  Future<void> _pick(BuildContext context) async {
    final picked = await showLokalSettingsSheet<LokalSegment<T>>(
      context: context,
      title: label,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            LokalSheetOption(
              label: option.label,
              description: option.description,
              selected: option.value == value,
              onTap: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    );
    if (picked != null && picked.value != value) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    String current = '';
    for (final option in options) {
      if (option.value == value) current = option.label;
    }
    return LokalSettingRow(
      label: label,
      description: description,
      enabled: enabled,
      onTap: () => _pick(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              current.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LokalTheme.label(t, size: 12, color: t.text),
            ),
          ),
          Icon(Icons.unfold_more_rounded, size: 18, color: t.muted),
        ],
      ),
    );
  }
}

/// A small capsule button for a row's action, like desktop's "Clear".
class LokalSettingButton extends StatelessWidget {
  const LokalSettingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final color = destructive ? t.red : t.text;
    return Opacity(
      opacity: onPressed == null ? .45 : 1,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: destructive ? t.red.withValues(alpha: .12) : t.surface3,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: destructive ? t.red.withValues(alpha: .4) : t.border2,
              ),
            ),
            child: Text(
              lokalText(label).toUpperCase(),
              style: LokalTheme.label(t, size: 11, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// An existing widget placed in a section, findable by [label] and
/// [description].
class LokalSettingCustom extends StatelessWidget implements LokalSearchable {
  const LokalSettingCustom({
    super.key,
    required this.label,
    this.description,
    required this.child,
  });

  final String label;
  final String? description;
  final Widget child;

  @override
  String get searchText => _searchText(lokalText(label), description);

  @override
  Widget build(BuildContext context) => child;
}

/// The settings search field: a solid capsule on the theme's surface.
class LokalSettingsSearchField extends StatelessWidget {
  const LokalSettingsSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search settings',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            controller: controller,
            onChanged: onChanged,
            autofocus: autofocus,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              fontFamily: LokalTheme.sans,
              fontSize: 15,
              color: t.text,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: t.muted),
              prefixIcon: Icon(Icons.search_rounded, color: t.muted),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: lokalText('Clear search'),
                      icon: Icon(Icons.close_rounded, color: t.muted),
                      onPressed: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                    ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// The large title at the top of a settings page, with a glass back button
/// when there is somewhere to go back to.
class LokalSettingsHeader extends StatelessWidget {
  const LokalSettingsHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final bool showBack;

  /// Small controls on the right of the back button's row.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final canPop = showBack && (Navigator.maybeOf(context)?.canPop() ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: LokalPageGeometry.barPadding,
          child: SizedBox(
            height: LokalPageGeometry.barHeight,
            child: Row(
              children: [
                if (canPop)
                  _RoundButton(
                    semanticLabel: lokalText('Back'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Icon(Icons.chevron_left_rounded, color: t.text),
                  ),
                const Spacer(),
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  action,
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: LokalPageGeometry.titlePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: LokalTheme.sans,
                    fontSize: 34,
                    height: 1.1,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                  ),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle!,
                    style: TextStyle(fontSize: 13, color: t.muted, height: 1.4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A settings sub-page: the theme's background (like Home and Library), the
/// large title with its back button, and [children] scrolling under it.
///
/// [children] are usually [LokalSettingsSection]s; wrap free content in
/// [LokalSettingsBlock] to line it up with them.
class LokalSettingsScaffold extends StatelessWidget {
  const LokalSettingsScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
    this.controller,
  });

  final String title;
  final String? subtitle;

  /// Small controls beside the back button.
  final List<Widget> actions;
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => LokalSettingsPageFrame(
    controller: controller,
    header: LokalSettingsHeader(
      title: title,
      subtitle: subtitle,
      actions: actions,
    ),
    children: children,
  );
}

/// A round button for a settings header's actions: a solid theme surface.
class LokalSettingsHeaderAction extends StatelessWidget {
  const LokalSettingsHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: _RoundButton(
      semanticLabel: tooltip,
      onPressed: onPressed,
      child: Icon(icon, size: 20, color: context.lokal.text),
    ),
  );
}

/// The header's round button: the theme's raised surface and border, no
/// blur of the page behind it.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: t.surface2,
        shape: CircleBorder(side: BorderSide(color: t.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: LokalPageGeometry.barHeight,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _OptionMark extends StatelessWidget {
  const _OptionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Icon(
      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
      size: 22,
      color: selected ? t.accent : t.muted2,
    );
  }
}
