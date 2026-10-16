import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_expance/logic/bubble_pack.dart';
import 'package:my_expance/logic/budget.dart';
import 'package:my_expance/logic/format.dart';
import 'package:my_expance/logic/grouping.dart';
import 'package:my_expance/logic/series.dart';
import 'package:my_expance/models/expense.dart';

var _id = 0;
Expense e(double amount, String category, DateTime day) =>
    Expense(id: ++_id, amount: amount, category: category, note: '', spentOn: day);

void main() {
  group('groupByCategory', () {
    test('largest first, fractions add up to 1', () {
      final d = DateTime(2026, 10, 1);
      final s = groupByCategory([e(100, 'food', d), e(300, 'bills', d), e(50, 'food', d)]);
      expect(s.map((x) => x.category), ['bills', 'food']);
      expect(s.first.total, 300);
      expect(s[1].count, 2);
      expect(s.fold<double>(0, (a, x) => a + x.fraction), closeTo(1, 1e-9));
    });

    test('keeps top 5 and folds the rest into Other', () {
      final d = DateTime(2026, 10, 1);
      final items = [
        e(900, 'food', d),
        e(800, 'bills', d),
        e(700, 'travel', d),
        e(600, 'shopping', d),
        e(500, 'health', d),
        e(40, 'education', d),
        e(30, 'transport', d),
        e(20, 'other', d),
      ];
      final s = groupByCategory(items);
      expect(s.length, 6);
      expect(s.last.category, 'other');
      expect(s.last.total, 90);
      expect(s.last.count, 3);
    });

    test('empty input gives no slices', () {
      expect(groupByCategory(const []), isEmpty);
    });
  });

  group('dailySeries', () {
    test('7 days oldest first with zeros filled, across a month boundary', () {
      final today = DateTime(2026, 10, 3);
      final s = dailySeries([
        e(100, 'food', DateTime(2026, 9, 28)),
        e(50, 'food', DateTime(2026, 10, 3)),
        e(25, 'food', DateTime(2026, 10, 3)),
        e(999, 'food', DateTime(2026, 9, 20)), // outside the window
      ], today);
      expect(s.length, 7);
      expect(s.first.day, DateTime(2026, 9, 27));
      expect(s.last.day, today);
      expect(s[1].total, 100);
      expect(s.last.total, 75);
      expect(s.fold<double>(0, (a, x) => a + x.total), 175);
    });
  });

  group('computeBudget', () {
    test('remaining and safe per day', () {
      final b = computeBudget(budget: 31000, spent: 10000, today: DateTime(2026, 10, 15))!;
      expect(b.daysLeft, 17); // 15th..31st
      expect(b.remaining, 21000);
      expect(b.safePerDay, closeTo(1235.29, 0.01));
      expect(b.overBudget, isFalse);
      expect(b.leftFraction, closeTo(21000 / 31000, 1e-9));
    });

    test('over budget', () {
      final b = computeBudget(budget: 1000, spent: 1500, today: DateTime(2026, 2, 28))!;
      expect(b.daysLeft, 1);
      expect(b.overBudget, isTrue);
      expect(b.safePerDay, 0);
      expect(b.leftFraction, 0);
    });

    test('no budget gives null', () {
      expect(computeBudget(budget: null, spent: 10, today: DateTime(2026, 10, 1)), isNull);
    });
  });

  group('packBubbles', () {
    void checkPacking(List<double> values, double w, double h) {
      final circles = packBubbles(values, w, h);
      expect(circles.length, values.where((v) => v > 0).length);
      for (final c in circles) {
        expect(c.x - c.r, greaterThanOrEqualTo(-1e-6));
        expect(c.y - c.r, greaterThanOrEqualTo(-1e-6));
        expect(c.x + c.r, lessThanOrEqualTo(w + 1e-6));
        expect(c.y + c.r, lessThanOrEqualTo(h + 1e-6));
      }
      for (var i = 0; i < circles.length; i++) {
        for (var j = i + 1; j < circles.length; j++) {
          final a = circles[i], b = circles[j];
          final d = math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
          expect(d, greaterThanOrEqualTo(a.r + b.r - 1e-6), reason: 'circles $i and $j overlap');
        }
      }
    }

    test('no overlaps and stays in bounds', () {
      checkPacking([900, 800, 700, 600, 500, 90], 340, 260);
      checkPacking([5000, 10, 10, 10, 10, 10], 300, 200);
      checkPacking([1, 1, 1, 1, 1, 1], 200, 400);
      checkPacking([42], 100, 100);
    });

    test('bigger value gets a bigger circle; zeros skipped', () {
      final c = packBubbles([100, 0, 400], 300, 300);
      expect(c.length, 2);
      final big = c.firstWhere((x) => x.index == 2), small = c.firstWhere((x) => x.index == 0);
      expect(big.r, greaterThan(small.r));
    });
  });

  group('formatMoney', () {
    test('Indian grouping for INR', () {
      expect(formatMoney(125000), '₹1,25,000');
      expect(formatMoney(12345678.5), '₹1,23,45,678.50');
      expect(formatMoney(999), '₹999');
      expect(formatMoney(0), '₹0');
      expect(formatMoney(-450), '-₹450');
      expect(formatMoney(99.5, decimals: false), '₹100');
    });

    test('western grouping for other currencies', () {
      expect(formatMoney(1234567, currency: 'USD'), r'$1,234,567');
      expect(formatMoney(12.3, currency: 'EUR'), '€12.30');
    });

    test('compact', () {
      expect(formatCompact(950), '₹950');
      expect(formatCompact(1240), '₹1.2k');
      expect(formatCompact(250000), '₹2.5L');
      expect(formatCompact(12000000), '₹1.2Cr');
      expect(formatCompact(3400000, currency: 'USD'), r'$3.4M');
    });
  });
}
