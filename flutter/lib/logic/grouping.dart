import '../models/expense.dart';

class CategorySlice {
  const CategorySlice({required this.category, required this.total, required this.count, required this.fraction});

  final String category;
  final double total;
  final int count;

  /// Share of the grand total, 0..1.
  final double fraction;
}

/// Totals by category, largest first. Keeps the top [maxSlices] categories and folds the rest
/// (plus anything already in "other") into a single "other" slice at the end.
List<CategorySlice> groupByCategory(List<Expense> items, {int maxSlices = 5}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  for (final e in items) {
    totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    counts[e.category] = (counts[e.category] ?? 0) + 1;
  }
  final grand = totals.values.fold<double>(0, (a, b) => a + b);
  if (grand <= 0) return const [];

  final named = totals.keys.where((k) => k != 'other').toList()
    ..sort((a, b) => totals[b]!.compareTo(totals[a]!));

  final keep = named.take(maxSlices).toList();
  var otherTotal = totals['other'] ?? 0;
  var otherCount = counts['other'] ?? 0;
  for (final k in named.skip(maxSlices)) {
    otherTotal += totals[k]!;
    otherCount += counts[k]!;
  }

  return [
    for (final k in keep)
      CategorySlice(category: k, total: totals[k]!, count: counts[k]!, fraction: totals[k]! / grand),
    if (otherTotal > 0)
      CategorySlice(category: 'other', total: otherTotal, count: otherCount, fraction: otherTotal / grand),
  ];
}
