import 'package:flutter/material.dart';

import '../../state/expense_store.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import 'other_charts.dart';
import 'ring_charts.dart';

/// The overview chart in the user's chosen style. Animates in on first show and on style change,
/// unless the OS asks to reduce motion.
class ChartView extends StatelessWidget {
  const ChartView({super.key, required this.style, required this.store, required this.onSetBudget});

  final ChartStyle style;
  final ExpenseStore store;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    final slices = store.slices;
    final needsData = style != ChartStyle.jar && style != ChartStyle.bar;
    if (needsData && slices.isEmpty) {
      return const _EmptyChart();
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey('${style.name}-${store.month}'),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Motion.long),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        switch (style) {
          case ChartStyle.arc:
          case ChartStyle.donut:
            return RingChart(
              half: style == ChartStyle.arc,
              slices: slices,
              total: store.monthTotal,
              currency: store.currency,
              progress: t,
              selected: store.filter,
              onSelect: store.toggleFilter,
            );
          case ChartStyle.bar:
            return WeekBarChart(days: store.week, today: store.today, currency: store.currency, progress: t);
          case ChartStyle.bubbles:
            return BubbleChart(
              slices: slices,
              currency: store.currency,
              progress: t,
              selected: store.filter,
              onSelect: store.toggleFilter,
            );
          case ChartStyle.jar:
            return JarChart(budget: store.budget, currency: store.currency, progress: t, onSetBudget: onSetBudget);
          case ChartStyle.classic:
            return ClassicChart(
              slices: slices,
              currency: store.currency,
              progress: t,
              selected: store.filter,
              onSelect: store.toggleFilter,
            );
        }
      },
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.pie_chart_outline_rounded, size: 56, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text('No spending yet this month', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Tap + or tell the assistant "spent 450 on lunch"',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
      ]),
    );
  }
}
