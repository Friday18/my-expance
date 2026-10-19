import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/budget.dart';
import '../logic/format.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../services/auth_service.dart';
import '../state/expense_store.dart';
import '../theme/app_theme.dart';
import '../widgets/calm.dart';
import '../widgets/expense_tile.dart';
import '../widgets/proof_sheet.dart';
import 'expense_editor.dart';
import 'settings_screen.dart';

/// "Now": one big number, the ring around it, and the few things that matter today.
class NowScreen extends StatelessWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context);
    final t = CalmTokens.of(context);
    final recent = store.monthExpenses.take(6).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 128),
            children: [
              _Header(name: auth.displayName, store: store),
              if (store.error != null) ...[
                const SizedBox(height: 12),
                GlassCard(
                  borderColor: theme.colorScheme.error.withValues(alpha: 0.5),
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(children: [
                    Expanded(child: Text(store.error!, style: TextStyle(color: theme.colorScheme.error))),
                    TextButton(onPressed: store.load, child: const Text('Retry')),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              Center(child: _HeroRing(store: store)),
              const SizedBox(height: 28),
              if (store.isCurrentMonth)
                GradientButton(
                  label: 'Add expense',
                  icon: Icons.add_rounded,
                  onPressed: () => showExpenseEditor(context),
                ),
              if (store.slices.isNotEmpty) ...[
                const SizedBox(height: 32),
                const SectionLabel('Where it went · tap for proof'),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final s in store.slices)
                    _CategoryPill(
                      category: s.category,
                      total: s.total,
                      currency: store.currency,
                      onTap: () => showProofSheet(
                        context,
                        title: categoryInfo(s.category).label,
                        items: _itemsFor(store, s.category),
                        currency: store.currency,
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 32),
              const SectionLabel('Recent'),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: recent.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          store.loading ? 'Loading…' : 'Nothing yet. Tap Add, or hold the orb and say “chai 30”.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: t.muted),
                        ),
                      )
                    : Column(children: [
                        for (final e in recent)
                          ExpenseTile(
                            expense: e,
                            currency: store.currency,
                            onTap: () => showExpenseEditor(context, existing: e),
                          ),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Same grouping rule as the charts: "other" holds every category outside the top slices.
  static List<Expense> _itemsFor(ExpenseStore store, String category) {
    final items = store.monthExpenses;
    if (category != 'other') return items.where((e) => e.category == category).toList();
    final shown = store.slices.map((s) => s.category).where((c) => c != 'other').toSet();
    return items.where((e) => !shown.contains(e.category)).toList();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.store});
  final String name;
  final ExpenseStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = CalmTokens.of(context);
    final first = name.trim().isEmpty ? 'there' : name.trim().split(' ').first;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, $first', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _TinyIcon(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous month',
              onTap: () => store.changeMonth(-1),
            ),
            Text(DateFormat('MMMM yyyy').format(store.month),
                style: theme.textTheme.bodyMedium?.copyWith(color: t.muted)),
            _TinyIcon(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next month',
              onTap: store.isCurrentMonth ? null : () => store.changeMonth(1),
            ),
          ]),
        ]),
      ),
      Tooltip(
        message: 'Settings',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.glassFill,
              border: Border.all(color: t.glassBorder),
            ),
            child: Text(initial, style: theme.textTheme.titleMedium),
          ),
        ),
      ),
    ]);
  }
}

class _TinyIcon extends StatelessWidget {
  const _TinyIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      color: CalmTokens.of(context).muted,
    );
  }
}

/// The hero: a thin ring for budget used, a glowing dot for today, the big number inside.
class _HeroRing extends StatelessWidget {
  const _HeroRing({required this.store});
  final ExpenseStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = CalmTokens.of(context);
    final size = math.min(MediaQuery.sizeOf(context).width - 72, 300.0);
    final b = store.budget;
    final today = store.today;
    final dayFrac = store.isCurrentMonth
        ? (today.day - 0.5) / daysInMonth(today.year, today.month)
        : null;

    double used = 0;
    Color? solid; // null = accent gradient
    final String caption;
    final double hero;
    final String footer;

    if (b != null) {
      used = b.usedFraction;
      final ahead = dayFrac != null && used > dayFrac + 0.05;
      solid = b.overBudget ? theme.colorScheme.error : (ahead ? t.warn : null);
      caption = 'safe to spend';
      hero = math.max(b.remaining, 0);
      footer = b.overBudget
          ? 'Over by ${formatMoney(-b.remaining, currency: store.currency, decimals: false)}'
          : '≈ ${formatMoney(b.safePerDay, currency: store.currency, decimals: false)}/day · '
              '${b.daysLeft} ${b.daysLeft == 1 ? 'day' : 'days'} left';
    } else {
      caption = store.isCurrentMonth ? 'spent this month' : 'spent in ${DateFormat('MMMM').format(store.month)}';
      hero = store.monthTotal;
      footer = store.isCurrentMonth ? 'Set a budget to see what’s safe to spend' : '';
    }

    return Semantics(
      label: '$caption ${formatMoney(hero, currency: store.currency, decimals: false)}. $footer',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: used),
        duration: Motion.of(context, const Duration(milliseconds: 1100)),
        curve: Curves.easeOutCubic,
        builder: (context, p, _) => CustomPaint(
          painter: _CycleRingPainter(
            progress: p,
            today: dayFrac,
            tokens: t,
            solid: solid,
            track: theme.colorScheme.onSurface.withValues(alpha: 0.07),
          ),
          child: SizedBox.square(
            dimension: size,
            child: Padding(
              padding: EdgeInsets.all(size * 0.16),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(caption.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(color: t.muted, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                MoneyText(
                  hero,
                  currency: store.currency,
                  gradient: solid == null,
                  style: theme.textTheme.displayLarge?.copyWith(color: solid ?? theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                if (b == null && store.isCurrentMonth)
                  TextButton(onPressed: () => showBudgetDialog(context), child: const Text('Set a budget'))
                else if (footer.isNotEmpty)
                  Text(footer,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: solid ?? t.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  _CycleRingPainter({
    required this.progress,
    required this.today,
    required this.tokens,
    required this.solid,
    required this.track,
  });

  final double progress; // 0..1 of budget used
  final double? today; // 0..1 position of today in the month, null for past months
  final CalmTokens tokens;
  final Color? solid;
  final Color track;

  static const double _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 14;
    final rect = Rect.fromCircle(center: c, radius: r);
    const stroke = 10.0;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    // Faint tick marks every quarter: a quiet "instrument" feel.
    final tick = Paint()
      ..color = track
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final a = _start + i * math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - 22), c + dir * (r - 16), tick);
    }

    if (progress > 0.001) {
      final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
      final shader = SweepGradient(
        colors: solid == null ? [tokens.accentA, tokens.accentB, tokens.accentA] : [solid!, solid!],
        transform: const GradientRotation(_start),
      ).createShader(rect);
      // Glow underneath, then the crisp arc.
      canvas.drawArc(
        rect,
        _start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke + 6
          ..strokeCap = StrokeCap.round
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawArc(
        rect,
        _start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }

    if (today != null) {
      final a = _start + 2 * math.pi * today!;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(p, 11, Paint()..color = tokens.accentB.withValues(alpha: 0.25));
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = Colors.white
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_CycleRingPainter old) =>
      old.progress != progress || old.today != today || old.solid != solid || old.track != track || old.tokens != tokens;
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category, required this.total, required this.currency, required this.onTap});
  final String category;
  final double total;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = categoryInfo(category);
    final color = info.colorFor(theme.brightness);
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: onTap,
      semanticLabel: '${info.label} ${formatMoney(total, currency: currency)}. Show proof',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 8),
        Text(info.label, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 8),
        Text(formatCompact(total, currency: currency), style: theme.textTheme.titleSmall),
      ]),
    );
  }
}
