import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../theme/app_theme.dart';
import 'calm.dart';
import 'expense_tile.dart';

/// "Proof" sheet: the exact transactions behind a number, with their sum.
/// First step of the "receipts for every number" feature.
Future<void> showProofSheet(
  BuildContext context, {
  required String title,
  required List<Expense> items,
  required String currency,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProofSheet(title: title, items: items, currency: currency),
  );
}

class _ProofSheet extends StatelessWidget {
  const _ProofSheet({required this.title, required this.items, required this.currency});
  final String title;
  final List<Expense> items;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    final theme = Theme.of(context);
    final total = items.fold(0.0, (a, e) => a + e.amount);
    final maxH = MediaQuery.sizeOf(context).height * 0.75;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: GlassCard(
          blur: true,
          fill: t.sheetFill,
          radius: 28,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: t.glassBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(children: [
                const AccentGradient(child: Icon(Icons.verified_rounded, size: 22)),
                const SizedBox(width: 8),
                Expanded(child: Text('Proof · $title', style: theme.textTheme.titleMedium)),
                Text('${items.length} ${items.length == 1 ? 'entry' : 'entries'}', style: theme.textTheme.bodySmall),
              ]),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) => ExpenseTile(expense: items[i], currency: currency),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Text('=', style: theme.textTheme.titleLarge?.copyWith(color: t.muted)),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MoneyText(total, currency: currency, gradient: true, style: theme.textTheme.headlineSmall),
                  ),
                ),
                Icon(Icons.check_circle_rounded, color: t.accentA),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
