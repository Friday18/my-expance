class Expense {
  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.note,
    required this.spentOn,
  });

  final int id;
  final double amount;
  final String category;
  final String note;

  /// Calendar date only (time is midnight local).
  final DateTime spentOn;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as int,
        amount: (json['amount'] as num).toDouble(),
        category: json['category'] as String,
        note: (json['note'] as String?) ?? '',
        spentOn: parseDay(json['spent_on'] as String),
      );

  Expense copyWith({double? amount, String? category, String? note, DateTime? spentOn}) => Expense(
        id: id,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        note: note ?? this.note,
        spentOn: spentOn ?? this.spentOn,
      );
}

DateTime parseDay(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String formatDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
