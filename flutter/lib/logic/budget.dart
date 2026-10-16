class BudgetInfo {
  const BudgetInfo({
    required this.budget,
    required this.spent,
    required this.remaining,
    required this.daysLeft,
    required this.safePerDay,
  });

  final double budget;
  final double spent;
  final double remaining;

  /// Days left in the month, counting today.
  final int daysLeft;

  /// What can be spent each remaining day and still stay within budget (0 when over).
  final double safePerDay;

  bool get overBudget => remaining < 0;

  /// How full the jar still is: 1.0 = untouched, 0.0 = empty or overspent.
  double get leftFraction => budget <= 0 ? 0 : (remaining / budget).clamp(0.0, 1.0);

  double get usedFraction => budget <= 0 ? 1 : (spent / budget).clamp(0.0, 1.0);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Budget for the month containing [today]. Returns null when no budget is set.
BudgetInfo? computeBudget({required double? budget, required double spent, required DateTime today}) {
  if (budget == null || budget <= 0) return null;
  final daysLeft = daysInMonth(today.year, today.month) - today.day + 1;
  final remaining = budget - spent;
  final safe = remaining <= 0 ? 0.0 : remaining / daysLeft;
  return BudgetInfo(
    budget: budget,
    spent: spent,
    remaining: remaining,
    daysLeft: daysLeft,
    safePerDay: (safe * 100).floorToDouble() / 100,
  );
}
