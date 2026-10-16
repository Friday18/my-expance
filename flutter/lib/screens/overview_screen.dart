import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/format.dart';
import '../models/category.dart';
import '../state/expense_store.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/category_legend.dart';
import '../widgets/charts/chart_view.dart';
import '../widgets/expense_tile.dart';
import 'expense_editor.dart';
import 'settings_screen.dart' show showBudgetDialog;

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final settings = context.watch<SettingsStore>();
    final theme = Theme.of(context);
    final items = store.visibleExpenses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expance'),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => store.changeMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Center(child: Text(DateFormat('MMM yyyy').format(store.month), style: theme.textTheme.titleSmall)),
          IconButton(
            tooltip: 'Next month',
            onPressed: store.isCurrentMonth ? null : () => store.changeMonth(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (store.error != null)
              SliverToBoxAdapter(child: _ErrorBanner(message: store.error!, onRetry: store.load)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _StylePicker(value: settings.chartStyle, onChanged: settings.setChartStyle),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 260,
                        child: store.loading && store.monthExpenses.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : AnimatedSwitcher(
                                duration: Motion.of(context, Motion.medium),
                                child: ChartView(
                                  key: ValueKey(settings.chartStyle),
                                  style: settings.chartStyle,
                                  store: store,
                                  onSetBudget: () => showBudgetDialog(context),
                                ),
                              ),
                      ),
                      if (store.slices.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        CategoryLegend(
                          slices: store.slices,
                          currency: store.currency,
                          selected: store.filter,
                          onSelect: store.toggleFilter,
                        ),
                      ],
                      if (store.budget != null && settings.chartStyle != ChartStyle.jar) ...[
                        const SizedBox(height: 12),
                        _BudgetLine(store: store),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Expanded(
                    child: Text(
                      store.filter == null ? 'Expenses' : '${categoryInfo(store.filter!).label} expenses',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (store.filter != null) TextButton(onPressed: store.clearFilter, child: const Text('Show all')),
                ]),
              ),
            ),
            if (items.isEmpty && !store.loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Nothing here yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                return Dismissible(
                  key: ValueKey('expense-${e.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: theme.colorScheme.errorContainer,
                    child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
                  ),
                  onDismissed: (_) async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await store.delete(e);
                      messenger.showSnackBar(SnackBar(
                        content: Text('Deleted ${formatMoney(e.amount, currency: store.currency)}'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => store.add(
                            amount: e.amount,
                            category: e.category,
                            note: e.note,
                            spentOn: e.spentOn,
                          ),
                        ),
                      ));
                    } catch (err) {
                      messenger.showSnackBar(SnackBar(content: Text(err.toString())));
                    }
                  },
                  child: ExpenseTile(
                    expense: e,
                    currency: store.currency,
                    onTap: () => showExpenseEditor(context, existing: e),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _StylePicker extends StatelessWidget {
  const _StylePicker({required this.value, required this.onChanged});

  final ChartStyle value;
  final ValueChanged<ChartStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final s in ChartStyle.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: value == s,
              onSelected: (_) => onChanged(s),
              avatar: Icon(s.icon, size: 18),
              label: Text(s.label),
              showCheckmark: false,
            ),
          ),
      ]),
    );
  }
}

class _BudgetLine extends StatelessWidget {
  const _BudgetLine({required this.store});
  final ExpenseStore store;

  @override
  Widget build(BuildContext context) {
    final b = store.budget!;
    final theme = Theme.of(context);
    final color = b.overBudget ? theme.colorScheme.error : theme.colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: b.usedFraction,
          minHeight: 8,
          color: color,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        b.overBudget
            ? 'Over budget by ${formatMoney(-b.remaining, currency: store.currency, decimals: false)}'
            : '${formatMoney(b.remaining, currency: store.currency, decimals: false)} left · '
                '${formatMoney(b.safePerDay, currency: store.currency, decimals: false)}/day for ${b.daysLeft} days',
        style: theme.textTheme.bodySmall,
      ),
    ]);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Expanded(child: Text(message, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      ),
    );
  }
}
