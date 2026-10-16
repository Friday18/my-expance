import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/format.dart';
import '../../logic/grouping.dart';
import '../../models/category.dart';

/// Shared painter for the Arc (half ring) and Donut (full ring) views.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.slices,
    required this.colors,
    required this.progress,
    required this.selected,
    required this.track,
    required this.half,
  });

  final List<CategorySlice> slices;
  final List<Color> colors;
  final double progress;
  final String? selected;
  final Color track;
  final bool half;

  static const double gapRadians = 0.035;

  static (Offset, double, double) geometry(Size size, bool half) {
    if (half) {
      final radius = math.min(size.width / 2, size.height) - 18;
      return (Offset(size.width / 2, size.height - 6), radius, 24.0);
    }
    final radius = math.min(size.width, size.height) / 2 - 16;
    return (Offset(size.width / 2, size.height / 2), radius, 26.0);
  }

  static double startAngle(bool half) => half ? math.pi : -math.pi / 2;
  static double sweepTotal(bool half) => half ? math.pi : 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final (center, radius, stroke) = geometry(size, half);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, startAngle(half), sweepTotal(half), false, base..color = track);
    if (slices.isEmpty) return;

    final total = sweepTotal(half) * progress;
    final gaps = slices.length > 1 ? gapRadians : 0.0;
    var angle = startAngle(half);
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].fraction * total;
      final drawn = math.max(0.0, sweep - gaps);
      final isSel = selected == slices[i].category;
      final dim = selected != null && !isSel;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? stroke + 8 : stroke
        ..color = dim ? colors[i].withValues(alpha: 0.28) : colors[i];
      if (drawn > 0) canvas.drawArc(rect, angle + gaps / 2, drawn, false, paint);
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.selected != selected || old.slices != slices || old.track != track;
}

String? _hitTest(Offset p, Size size, bool half, List<CategorySlice> slices) {
  final (center, radius, stroke) = _RingPainter.geometry(size, half);
  final d = (p - center).distance;
  if (d < radius - stroke - 10 || d > radius + stroke + 10) return null;
  final a = math.atan2(p.dy - center.dy, p.dx - center.dx); // -pi..pi, 0 = right, clockwise positive
  var rel = a - _RingPainter.startAngle(half);
  while (rel < 0) {
    rel += 2 * math.pi;
  }
  final total = _RingPainter.sweepTotal(half);
  if (rel > total) return null;
  var acc = 0.0;
  for (final s in slices) {
    acc += s.fraction * total;
    if (rel <= acc) return s.category;
  }
  return null;
}

class RingChart extends StatelessWidget {
  const RingChart({
    super.key,
    required this.half,
    required this.slices,
    required this.total,
    required this.currency,
    required this.progress,
    required this.selected,
    required this.onSelect,
    this.caption = 'spent this month',
  });

  final bool half;
  final List<CategorySlice> slices;
  final double total;
  final String currency;
  final double progress;
  final String? selected;
  final ValueChanged<String> onSelect;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [for (final s in slices) categoryInfo(s.category).colorFor(theme.brightness)];
    CategorySlice? sel;
    for (final s in slices) {
      if (s.category == selected) sel = s;
    }
    final headline = sel == null ? formatMoney(total * progress, currency: currency, decimals: false)
        : formatMoney(sel.total, currency: currency, decimals: false);
    final sub = sel == null ? caption : '${categoryInfo(sel.category).label} · ${(sel.fraction * 100).round()}%';

    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return Semantics(
        label: 'Spending by category: ${slices.map((s) => '${categoryInfo(s.category).label} '
            '${formatMoney(s.total, currency: currency)}').join(', ')}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final hit = _hitTest(d.localPosition, size, half, slices);
            if (hit != null) onSelect(hit);
          },
          child: CustomPaint(
            size: size,
            painter: _RingPainter(
              slices: slices,
              colors: colors,
              progress: progress,
              selected: selected,
              track: theme.colorScheme.surfaceContainerHighest,
              half: half,
            ),
            child: Align(
              alignment: half ? const Alignment(0, 0.75) : Alignment.center,
              child: ExcludeSemantics(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(child: Text(headline, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))),
                  const SizedBox(height: 2),
                  Text(sub, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}
