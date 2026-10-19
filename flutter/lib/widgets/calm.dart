import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../logic/format.dart';
import '../theme/app_theme.dart';

/// The "Calm Future" building blocks. Every screen is made from these few pieces.

/// Near-black (or off-white) background with one soft accent glow in the top corner.
class CalmBackground extends StatelessWidget {
  const CalmBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1.1, -1.05),
            radius: 1.25,
            colors: [t.glow, t.glow.withValues(alpha: 0)],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Frosted glass card: faint fill, hairline border, big radius.
/// Keep [blur] for at most two surfaces per screen (it is expensive).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.blur = false,
    this.onTap,
    this.fill,
    this.borderColor,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    final shape = BorderRadius.circular(radius);
    Widget body = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: shape,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? t.glassFill,
        borderRadius: shape,
        border: Border.all(color: borderColor ?? t.glassBorder),
      ),
      child: body,
    );
    if (blur) {
      body = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: body);
    }
    body = ClipRRect(borderRadius: shape, child: body);
    if (semanticLabel != null) body = Semantics(label: semanticLabel, button: onTap != null, child: body);
    return body;
  }
}

/// Paints [child] with the accent gradient (used for the hero number and icons).
class AccentGradient extends StatelessWidget {
  const AccentGradient({super.key, required this.child, this.colors});
  final Widget child;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    final g = colors == null ? t.accent : LinearGradient(colors: colors!);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => g.createShader(r),
      child: child,
    );
  }
}

/// Money with tabular digits that counts up when the value changes.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    required this.currency,
    this.style,
    this.gradient = false,
    this.decimals = false,
  });

  final double value;
  final String currency;
  final TextStyle? style;
  final bool gradient;
  final bool decimals;

  @override
  Widget build(BuildContext context) {
    final label = formatMoney(value, currency: currency, decimals: decimals);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: Motion.of(context, Motion.long),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) {
          final text = Text(
            formatMoney(v, currency: currency, decimals: decimals),
            style: style,
            maxLines: 1,
          );
          final fitted = FittedBox(fit: BoxFit.scaleDown, child: text);
          return gradient ? AccentGradient(child: fitted) : fitted;
        },
      ),
    );
  }
}

enum OrbMode { idle, thinking }

/// The single "AI" visual in the app: a glowing orb that breathes when idle
/// and swirls faster while the assistant is thinking. Static when "reduce motion" is on.
class Orb extends StatefulWidget {
  const Orb({super.key, this.size = 64, this.mode = OrbMode.idle});
  final double size;
  final OrbMode mode;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _durationFor(widget.mode));

  static Duration _durationFor(OrbMode m) =>
      m == OrbMode.thinking ? const Duration(milliseconds: 1400) : const Duration(seconds: 5);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Orb old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _c.duration = _durationFor(widget.mode);
      if (_c.isAnimating) _c.repeat();
    }
  }

  void _sync() {
    if (Motion.reduced(context)) {
      _c.stop();
      _c.value = 0.25;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _OrbPainter(_c, CalmTokens.of(context), widget.mode)),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.anim, this.t, this.mode) : super(repaint: anim);

  final Animation<double> anim;
  final CalmTokens t;
  final OrbMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    final v = anim.value;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final wave = math.sin(v * 2 * math.pi);
    final breathe = mode == OrbMode.idle ? 0.94 + 0.06 * wave : 1.0;

    // Outer halo.
    final haloRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          t.accentA.withValues(alpha: 0.32 + 0.08 * wave),
          t.accentA.withValues(alpha: 0),
        ]).createShader(haloRect),
    );

    // Core sphere with a slowly rotating colour sweep.
    final core = r * 0.6 * breathe;
    final coreRect = Rect.fromCircle(center: c, radius: core);
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = SweepGradient(
          colors: [t.accentA, t.accentB, t.support, t.accentA],
          transform: GradientRotation(v * 2 * math.pi),
        ).createShader(coreRect),
    );

    // Soft inner shading so it reads as a sphere, not a flat disc.
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.35, 0.45),
          colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.28)],
        ).createShader(coreRect),
    );

    // Specular highlight.
    final hl = c + Offset(-core * 0.32, -core * 0.36);
    final hlRect = Rect.fromCircle(center: hl, radius: core * 0.5);
    canvas.drawCircle(
      hl,
      core * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.6),
          Colors.white.withValues(alpha: 0),
        ]).createShader(hlRect),
    );

    // Thinking: a thin orbit arc spinning around the core.
    if (mode == OrbMode.thinking) {
      final orbit = Rect.fromCircle(center: c, radius: core + r * 0.18);
      canvas.drawArc(
        orbit,
        v * 2 * math.pi,
        math.pi * 0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.05)
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [t.accentB.withValues(alpha: 0), t.accentB],
            transform: GradientRotation(v * 2 * math.pi),
          ).createShader(orbit),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.mode != mode || old.t != t;
}

/// Full-width pill button filled with the accent gradient: the one primary action on a screen.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    final on = Theme.of(context).colorScheme.onPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: t.accent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: t.glow, blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onPressed,
            child: SizedBox(
              height: 56,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: on),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: on, fontSize: 16)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase section label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = CalmTokens.of(context);
    return Row(children: [
      Expanded(
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: t.muted, letterSpacing: 1.4),
        ),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}
