import 'dart:math' as math;

class PackedCircle {
  const PackedCircle(this.index, this.x, this.y, this.r);

  /// Index into the input values.
  final int index;
  final double x;
  final double y;
  final double r;
}

class _C {
  _C(this.index, this.x, this.y, this.r);
  final int index;
  double x;
  double y;
  final double r;
}

/// Packs one circle per value (area proportional to value) inside a [width] x [height] box,
/// biggest in the middle, with [gap] logical pixels between circles. Circles never overlap and
/// always stay inside the box. Zero or negative values are skipped.
List<PackedCircle> packBubbles(List<double> values, double width, double height, {double gap = 4}) {
  if (width <= 0 || height <= 0) return const [];
  final order = [for (var i = 0; i < values.length; i++) if (values[i] > 0) i]
    ..sort((a, b) => values[b].compareTo(values[a]));
  if (order.isEmpty) return const [];

  // Work in unit space with radius = sqrt(value), then scale to fit.
  final maxV = values[order.first];
  const pad = 0.08; // relative spacing used while placing
  final placed = <_C>[];
  final aspect = width / height;

  double score(double x, double y) => (x / aspect) * (x / aspect) + y * y;

  bool fits(double x, double y, double r) {
    for (final c in placed) {
      final dx = c.x - x, dy = c.y - y;
      final min = c.r + r + pad;
      if (dx * dx + dy * dy < min * min - 1e-9) return false;
    }
    return true;
  }

  for (final i in order) {
    final r = math.sqrt(values[i] / maxV);
    if (placed.isEmpty) {
      placed.add(_C(i, 0, 0, r));
      continue;
    }
    double? bestX, bestY;
    var best = double.infinity;

    void consider(double x, double y) {
      final s = score(x, y);
      if (s < best && fits(x, y, r)) {
        best = s;
        bestX = x;
        bestY = y;
      }
    }

    // Touching one circle, at several angles.
    for (final c in placed) {
      final d = c.r + r + pad;
      for (var k = 0; k < 16; k++) {
        final a = k * math.pi / 8;
        consider(c.x + d * math.cos(a), c.y + d * math.sin(a));
      }
    }
    // Touching two circles at once (tightest packing).
    for (var a = 0; a < placed.length; a++) {
      for (var b = a + 1; b < placed.length; b++) {
        final p = placed[a], q = placed[b];
        final ra = p.r + r + pad, rb = q.r + r + pad;
        final dx = q.x - p.x, dy = q.y - p.y;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d == 0 || d > ra + rb || d < (ra - rb).abs()) continue;
        final along = (ra * ra - rb * rb + d * d) / (2 * d);
        final h = math.sqrt(math.max(0, ra * ra - along * along));
        final mx = p.x + along * dx / d, my = p.y + along * dy / d;
        consider(mx + h * dy / d, my - h * dx / d);
        consider(mx - h * dy / d, my + h * dx / d);
      }
    }
    placed.add(_C(i, bestX ?? 0, bestY ?? 0, r));
  }

  // Bounding box in unit space.
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final c in placed) {
    minX = math.min(minX, c.x - c.r);
    maxX = math.max(maxX, c.x + c.r);
    minY = math.min(minY, c.y - c.r);
    maxY = math.max(maxY, c.y + c.r);
  }
  final bw = maxX - minX, bh = maxY - minY;
  final scale = math.min(width / bw, height / bh);
  final offX = (width - bw * scale) / 2 - minX * scale;
  final offY = (height - bh * scale) / 2 - minY * scale;

  // Shrink each circle by half the gap so neighbours never touch.
  final shrink = math.min(gap / 2, 0.25 * scale * pad);
  return [
    for (final c in placed)
      PackedCircle(c.index, c.x * scale + offX, c.y * scale + offY, math.max(1.0, c.r * scale - shrink)),
  ];
}
