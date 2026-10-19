import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/format.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../state/settings_store.dart';

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, required this.currency, this.onTap});

  final Expense expense;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = categoryInfo(expense.category);
    final color = info.colorFor(theme.brightness);
    final futuristic = context.select<SettingsStore, bool>((s) => s.futuristic);
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 10,
      leading: futuristic
          ? Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Icon(info.icon, color: color, size: 20),
            )
          : CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.16),
              child: Icon(info.icon, color: color, size: 22),
            ),
      title: Text(expense.note.isEmpty ? info.label : expense.note, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${info.label} · ${_relativeDay(expense.spentOn)}'),
      trailing: Text(
        formatMoney(expense.amount, currency: currency),
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

String _relativeDay(DateTime d) {
  final today = dayOnly(DateTime.now());
  final diff = today.difference(dayOnly(d)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7 && diff > 0) return DateFormat('EEEE').format(d);
  return DateFormat('d MMM').format(d);
}
