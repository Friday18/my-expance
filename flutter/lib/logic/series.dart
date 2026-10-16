import '../models/expense.dart';

class DayTotal {
  const DayTotal(this.day, this.total);
  final DateTime day;
  final double total;
}

/// Daily totals for the [days] days ending on [today], oldest first, with zero-spend days filled in.
List<DayTotal> dailySeries(List<Expense> items, DateTime today, {int days = 7}) {
  final end = dayOnly(today);
  final start = DateTime(end.year, end.month, end.day - (days - 1));
  final totals = <DateTime, double>{};
  for (final e in items) {
    final d = dayOnly(e.spentOn);
    if (d.isBefore(start) || d.isAfter(end)) continue;
    totals[d] = (totals[d] ?? 0) + e.amount;
  }
  return List.generate(days, (i) {
    final d = DateTime(start.year, start.month, start.day + i);
    return DayTotal(d, totals[d] ?? 0);
  });
}
