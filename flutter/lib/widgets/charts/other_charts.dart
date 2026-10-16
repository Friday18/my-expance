import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../logic/bubble_pack.dart';
import '../../logic/budget.dart';
import '../../logic/format.dart';
import '../../logic/grouping.dart';
import '../../logic/series.dart';
import '../../models/category.dart';
import '../../models/expense.dart';

// ---------------------------------------------------------------- Bar: last 7 days

class WeekBarChart extends StatelessWidget {
  const WeekBarChart({
    super.key,
    required this.days,
    required this.today,
    required this.currency,
    required this.progress,
  });

  final List<DayTotal> days;
  final DateTime today;
  final String currency;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxV = days.fold<double>(0, (m, d) => math.max(m, d.total));
    final weekTotal = days.fold<double>(0, (a, d) => a + d.total);
    final dayFmt = DateFormat('E');

    return Semantics(
      label: 'Last 7 days: ${days.map((d) => '${dayFmt.format(d.day)} ${formatMoney(d.total, currency: currency)}').join(', ')}',
      child: ExcludeSemantics(
        child: Column(children: [
          Text('${formatMoney(weekTotal, currency: currency, decimals: false)} in the last 7 days',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: LayoutBuilder(builder: (context, c) {
                        final isToday = d.day == dayOnly(today);
                        const labelH = 52.0;
                        final barMax = math.max(0.0, c.maxHeight - labelH);
                        final h = maxV <= 0 ? 0.0 : (d.total / maxV) * barMax * progress;
                        return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          if (d.total > 0)
                            FittedBox(
                              child: Text(formatCompact(d.total, currency: currency),
                                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            height: math.max(4, h),
                            decoration: BoxDecoration(
                              color: isToday ? scheme.primary : scheme.primary.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(dayFmt.format(d.day).substring(0, 1),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                                color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                              )),
                        ]);
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Bubbles

class BubbleChart extends StatelessWidget {
  const BubbleChart({
    super.key,
    required this.slices,
    required this.currency,
    required this.progress,
    required this.selected,
    required this.onSelect,
  });

  final List<CategorySlice> slices;
  final String currency;
  final double progress;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final circles = packBubbles([for (final s in slices) s.total], c.maxWidth, c.maxHeight, gap: 6);
      return Stack(children: [
        for (final p in circles)
          Positioned(
            left: p.x - p.r,
            top: p.y - p.r,
            width: p.r * 2,
            height: p.r * 2,
            child: _Bubble(
              slice: slices[p.index],
              radius: p.r,
              currency: currency,
              scale: progress,
              dim: selected != null && selected != slices[p.index].category,
              color: categoryInfo(slices[p.index].category).colorFor(theme.brightness),
              onTap: () => onSelect(slices[p.index].category),
            ),
          ),
      ]);
    });
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.slice,
    required this.radius,
    required this.currency,
    required this.scale,
    required this.dim,
    required this.color,
    required this.onTap,
  });

  final CategorySlice slice;
  final double radius;
  final String currency;
  final double scale;
  final bool dim;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = categoryInfo(slice.category);
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87;
    return Semantics(
      button: true,
      label: '${info.label}, ${formatMoney(slice.total, currency: currency)}',
      child: Transform.scale(
        scale: scale,
        child: Material(
          color: dim ? color.withValues(alpha: 0.3) : color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: radius < 22
                  ? null
                  : Padding(
                      padding: EdgeInsets.all(radius * 0.25),
                      child: FittedBox(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(info.icon, color: onColor, size: 20),
                          Text(info.label, style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
                          Text(formatCompact(slice.total, currency: currency),
                              style: TextStyle(color: onColor, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Jar: budget left

class JarChart extends StatelessWidget {
  const JarChart({
    super.key,
    required this.budget,
    required this.currency,
    required this.progress,
    required this.onSetBudget,
  });

  final BudgetInfo? budget;
  final String currency;
  final double progress;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = budget;
    if (b == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.savings_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Set a monthly budget to fill your jar', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onSetBudget, child: const Text('Set budget')),
        ]),
      );
    }
    final fill = b.leftFraction * progress;
    final liquid = b.overBudget
        ? theme.colorScheme.error
        : (b.leftFraction < 0.2 ? const Color(0xFFE67700) : theme.colorScheme.primary);

    return Semantics(
      label: b.overBudget
          ? 'Over budget by ${formatMoney(-b.remaining, currency: currency)}'
          : '${formatMoney(b.remaining, currency: currency)} left of ${formatMoney(b.budget, currency: currency)}. '
              'Safe to spend ${formatMoney(b.safePerDay, currency: currency)} a day.',
      child: ExcludeSemantics(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: CustomPaint(
              painter: _JarPainter(
                fill: fill,
                liquid: liquid,
                glass: theme.colorScheme.outline,
                back: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.overBudget ? 'Over budget' : 'Left this month',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              FittedBox(
                child: Text(formatMoney(b.remaining.abs(), currency: currency, decimals: false),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800,
                        color: b.overBudget ? theme.colorScheme.error : null)),
              ),
              const SizedBox(height: 4),
              Text('of ${formatMoney(b.budget, currency: currency, decimals: false)}', style: theme.textTheme.bodyMedium),
              const Divider(height: 24),
              Text('Safe per day', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(formatMoney(b.safePerDay, currency: currency, decimals: false), style: theme.textTheme.titleLarge),
              Text('${b.daysLeft} ${b.daysLeft == 1 ? 'day' : 'days'} left', style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _JarPainter extends CustomPainter {
  _JarPainter({required this.fill, required this.liquid, required this.glass, required this.back});

  final double fill;
  final Color liquid;
  final Color glass;
  final Color back;

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.min(size.width, size.height * 0.8);
    final h = math.min(size.height, w * 1.25);
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final neckW = w * 0.62;
    final neckH = h * 0.1;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top + neckH, w, h - neckH),
      Radius.circular(w * 0.22),
    );
    final neck = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + (w - neckW) / 2, top, neckW, neckH + 6),
      const Radius.circular(6),
    );

    canvas.drawRRect(body, Paint()..color = back);

    // Liquid with a gentle curved surface.
    final inner = body.deflate(5);
    final level = inner.bottom - inner.height * fill.clamp(0.0, 1.0);
    canvas.save();
    canvas.clipRRect(inner);
    final path = Path()
      ..moveTo(inner.left, level)
      ..quadraticBezierTo(inner.center.dx, level + (fill > 0.02 ? 8 : 0), inner.right, level)
      ..lineTo(inner.right, inner.bottom)
      ..lineTo(inner.left, inner.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = liquid.withValues(alpha: 0.85));
    canvas.restore();

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = glass;
    canvas.drawRRect(body, stroke);
    canvas.drawRRect(neck, stroke);
    canvas.drawRRect(neck, Paint()..color = glass.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_JarPainter old) =>
      old.fill != fill || old.liquid != liquid || old.glass != glass || old.back != back;
}

// ---------------------------------------------------------------- Classic: category list

class ClassicChart extends StatelessWidget {
  const ClassicChart({
    super.key,
    required this.slices,
    required this.currency,
    required this.progress,
    required this.selected,
    required this.onSelect,
  });

  final List<CategorySlice> slices;
  final String currency;
  final double progress;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final s in slices)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(s.category),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Opacity(
                  opacity: selected != null && selected != s.category ? 0.4 : 1,
                  child: Row(children: [
                    Icon(categoryInfo(s.category).icon, color: categoryInfo(s.category).colorFor(theme.brightness)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(categoryInfo(s.category).label, style: theme.textTheme.titleSmall)),
                          Text(formatMoney(s.total, currency: currency, decimals: false), style: theme.textTheme.titleSmall),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: s.fraction * progress,
                            minHeight: 8,
                            color: categoryInfo(s.category).colorFor(theme.brightness),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
