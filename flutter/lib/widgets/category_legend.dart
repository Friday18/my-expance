import 'package:flutter/material.dart';

import '../logic/format.dart';
import '../logic/grouping.dart';
import '../models/category.dart';

/// Colour key under the chart. Tapping a chip filters the list below to that category.
class CategoryLegend extends StatelessWidget {
  const CategoryLegend({
    super.key,
    required this.slices,
    required this.currency,
    required this.selected,
    required this.onSelect,
  });

  final List<CategorySlice> slices;
  final String currency;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in slices)
          FilterChip(
            selected: selected == s.category,
            showCheckmark: false,
            onSelected: (_) => onSelect(s.category),
            avatar: CircleAvatar(
              radius: 6,
              backgroundColor: categoryInfo(s.category).colorFor(theme.brightness),
            ),
            label: Text('${categoryInfo(s.category).label} · ${formatCompact(s.total, currency: currency)}'),
            tooltip: 'Show only ${categoryInfo(s.category).label}',
          ),
      ],
    );
  }
}
