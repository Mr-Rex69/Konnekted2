import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/utils/app_haptics.dart';

import '../models/search_category.dart';
import '../providers/search_filter_provider.dart';

import 'package:flick/l10n/l10n.dart';

/// Source and result type are separate single-choice controls. Selecting a
/// category isolates it immediately without an All state.
class SearchFilterChips extends StatelessWidget {
  const SearchFilterChips({
    super.key,
    required this.enabled,
    required this.onToggle,
    required this.scope,
    required this.onScopeChanged,
    this.counts,
    this.query = '',
  });
  final Set<SearchCategory> enabled;
  final ValueChanged<SearchCategory> onToggle;
  final SearchScope scope;
  final ValueChanged<SearchScope> onScopeChanged;
  final Map<SearchCategory, int>? counts;
  final String query;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<SearchScope>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              textStyle: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            segments: [
              ButtonSegment(
                value: SearchScope.all,
                label: Text(l10n.all),
              ),
              ButtonSegment(
                value: SearchScope.library,
                label: Text(lokalText('Local')),
              ),
              ButtonSegment(
                value: SearchScope.online,
                label: Text(lokalText('Online')),
              ),
              ButtonSegment(
                value: SearchScope.soulseek,
                label: Text('Soulseek'),
              ),
            ],
            selected: {scope},
            onSelectionChanged: (value) {
              AppHaptics.tap();
              onScopeChanged(value.single);
            },
          ),
        ),
        if (scope != SearchScope.soulseek) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final category in visibleSearchCategories)
                  _chip(
                    context,
                    category.label,
                    enabled.contains(category),
                    () => onToggle(category),
                    count: scope != SearchScope.online && query.trim().isNotEmpty
                        ? (counts ?? const <SearchCategory, int>{})[category]
                        : null,
                  ),
              ],
            ),
          ),
        ],
        // The content begins at the same distance below the last control in
        // every scope, including Soulseek's single-row selector.
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback tap, {
    int? count,
  }) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(color: t.muted)),
            ],
          ],
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: t.accent.withValues(alpha: .18),
        labelStyle: TextStyle(
          color: selected ? t.accent : t.text,
          fontSize: 12,
        ),
        onSelected: (_) {
          AppHaptics.tap();
          tap();
        },
      ),
    );
  }
}
