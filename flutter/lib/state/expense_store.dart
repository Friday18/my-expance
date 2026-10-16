import 'package:flutter/foundation.dart';

import '../logic/budget.dart';
import '../logic/grouping.dart';
import '../logic/series.dart';
import '../models/expense.dart';
import '../services/api_client.dart';

/// App state for the signed-in user: profile, the selected month's expenses, and the category filter.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore(this.api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final now = _clock();
    _month = DateTime(now.year, now.month);
  }

  final ApiClient api;
  final DateTime Function() _clock;

  late DateTime _month;
  Profile? _profile;
  List<Expense> _loaded = const [];
  bool _loading = false;
  String? _error;
  String? _filter;

  DateTime get month => _month;
  Profile? get profile => _profile;
  String get currency => _profile?.currency ?? 'INR';
  double? get monthlyBudget => _profile?.monthlyBudget;
  bool get loading => _loading;
  String? get error => _error;
  String? get filter => _filter;
  DateTime get today => dayOnly(_clock());

  bool get isCurrentMonth => _month.year == today.year && _month.month == today.month;

  DateTime get _monthStart => _month;
  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 0);

  /// Expenses in the selected month, newest first.
  List<Expense> get monthExpenses => _loaded
      .where((e) => !e.spentOn.isBefore(_monthStart) && !e.spentOn.isAfter(_monthEnd))
      .toList(growable: false);

  /// Month expenses after the category filter.
  List<Expense> get visibleExpenses {
    final items = monthExpenses;
    if (_filter == null) return items;
    if (_filter == 'other') {
      final shown = slices.map((s) => s.category).where((c) => c != 'other').toSet();
      return items.where((e) => !shown.contains(e.category)).toList(growable: false);
    }
    return items.where((e) => e.category == _filter).toList(growable: false);
  }

  double get monthTotal => monthExpenses.fold(0.0, (a, e) => a + e.amount);

  List<CategorySlice> get slices => groupByCategory(monthExpenses);

  /// Last 7 days ending today (current month) or ending on the month's last day.
  List<DayTotal> get week => dailySeries(_loaded, isCurrentMonth ? today : _monthEnd);

  BudgetInfo? get budget {
    if (!isCurrentMonth) return null;
    return computeBudget(budget: monthlyBudget, spent: monthTotal, today: today);
  }

  void toggleFilter(String category) {
    _filter = _filter == category ? null : category;
    notifyListeners();
  }

  void clearFilter() {
    if (_filter == null) return;
    _filter = null;
    notifyListeners();
  }

  Future<void> changeMonth(int delta) async {
    final next = DateTime(_month.year, _month.month + delta);
    final current = DateTime(today.year, today.month);
    if (next.isAfter(current)) return;
    _month = next;
    _filter = null;
    _loaded = const [];
    notifyListeners();
    await refresh();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _profile = await api.me();
      await _fetchExpenses();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _error = null;
    try {
      _loading = true;
      notifyListeners();
      await _fetchExpenses();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchExpenses() async {
    // Six extra days before the month so the 7-day bar chart is full on the 1st.
    final start = DateTime(_monthStart.year, _monthStart.month, _monthStart.day - 6);
    _loaded = await api.listExpenses(start: start, end: _monthEnd);
  }

  Future<void> add({required double amount, required String category, String note = '', DateTime? spentOn}) async {
    final e = await api.addExpense(amount: amount, category: category, note: note, spentOn: spentOn);
    _loaded = [e, ..._loaded]..sort(_newestFirst);
    notifyListeners();
  }

  Future<void> update(Expense updated) async {
    final saved = await api.updateExpense(updated);
    _loaded = [for (final e in _loaded) e.id == saved.id ? saved : e]..sort(_newestFirst);
    notifyListeners();
  }

  /// Removes locally first so swipe-to-delete feels instant; restores on failure.
  Future<void> delete(Expense expense) async {
    final before = _loaded;
    _loaded = _loaded.where((e) => e.id != expense.id).toList();
    notifyListeners();
    try {
      await api.deleteExpense(expense.id);
    } catch (_) {
      _loaded = before;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setBudget(double? amount) async {
    _profile = await api.updateMe(monthlyBudget: amount, clearBudget: amount == null);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    _profile = await api.updateMe(currency: currency);
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    clear();
  }

  void clear() {
    final now = _clock();
    _month = DateTime(now.year, now.month);
    _profile = null;
    _loaded = const [];
    _filter = null;
    _error = null;
    notifyListeners();
  }

  static int _newestFirst(Expense a, Expense b) {
    final c = b.spentOn.compareTo(a.spentOn);
    return c != 0 ? c : b.id.compareTo(a.id);
  }
}
