import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/src/body_asset.dart';
import 'package:body_mapping/src/body_measurements.dart';
import 'package:body_mapping/src/body_scan.dart';

/// Measures a body mesh the way a tape would: circumferences are the convex
/// hull of a thin slice through the body (a tape spans hollows), lengths go
/// between joint centres. Turns "does the belly look bigger" into a number.
class BodyMeasurer {
  new(this.asset) {
    for (var v = 0; v < asset.vertexCount; v++) {
      final arm =
          asset.mask(v, BodyRegion.leftArm.index) +
          asset.mask(v, BodyRegion.rightArm.index);
      if (arm < 0.5 && asset.mask(v, MaskSlot.head) < 0.5) _torso.add(v);
      for (final r in BodyRegion.values) {
        if (r != BodyRegion.trunk && asset.mask(v, r.index) > 0.5) {
          _limbs[r]!.add(v);
        }
      }
    }
  }

  final BodyAsset asset;
  final _torso = <int>[];
  final Map<BodyRegion, List<int>> _limbs = {
    for (final r in BodyRegion.values) r: <int>[],
  };

  /// Half thickness of a tape slice, metres.
  static const _slice = 0.008;

  Map<Measure, double> measureAll(Float32List x) => {
    for (final m in Measure.values) m: measure(x, m),
  };

  /// One measurement of [x] (metres, y up), in cm.
  double measure(Float32List x, Measure m) {
    final j = {
      for (final e in asset.joints.entries) e.key: _centroid(x, e.value),
    };
    double dist(String a, String b) => (j[a]! - j[b]!).length;
    double avg(
      double Function(String side, BodyRegion arm, BodyRegion leg) f,
    ) =>
        (f('l', BodyRegion.leftArm, BodyRegion.leftLeg) +
            f('r', BodyRegion.rightArm, BodyRegion.rightLeg)) /
        2;
    final hipY = (j['hip_l']!.y + j['hip_r']!.y) / 2;
    final shoulderY = (j['shoulder_l']!.y + j['shoulder_r']!.y) / 2;
    final span = shoulderY - hipY;
    final metres = switch (m) {
      Measure.height => _height(x),
      Measure.shoulders => _shoulderWidth(x),
      Measure.chest => _torsoCirc(x, hipY + 0.60 * span, hipY + 0.85 * span),
      Measure.waist => _torsoCirc(
        x,
        hipY + 0.25 * span,
        hipY + 0.55 * span,
        widest: false,
      ),
      Measure.hips => _torsoCirc(x, hipY - 0.15 * span, hipY + 0.10 * span),
      Measure.upperArm => avg(
        (s, arm, _) => _limbCirc(
          x,
          _limbs[arm]!,
          j['shoulder_$s']!,
          j['elbow_$s']!,
          0.45,
          0.65,
        ),
      ),
      Measure.thigh => avg(
        (s, _, leg) =>
            _limbCirc(x, _limbs[leg]!, j['hip_$s']!, j['knee_$s']!, 0.15, 0.45),
      ),
      Measure.calf => avg(
        (s, _, leg) => _limbCirc(
          x,
          _limbs[leg]!,
          j['knee_$s']!,
          j['ankle_$s']!,
          0.15,
          0.60,
        ),
      ),
      Measure.armLength => avg(
        (s, _, _) =>
            dist('shoulder_$s', 'elbow_$s') + dist('elbow_$s', 'wrist_$s'),
      ),
      Measure.legLength => avg(
        (s, _, _) => dist('hip_$s', 'knee_$s') + dist('knee_$s', 'ankle_$s'),
      ),
    };
    return metres * 100;
  }

  static _V _centroid(Float32List x, List<int> idx) {
    var cx = 0.0;
    var cy = 0.0;
    var cz = 0.0;
    for (final v in idx) {
      cx += x[v * 3];
      cy += x[v * 3 + 1];
      cz += x[v * 3 + 2];
    }
    return _V(cx / idx.length, cy / idx.length, cz / idx.length);
  }

  static double _height(Float32List x) {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (var i = 1; i < x.length; i += 3) {
      lo = math.min(lo, x[i]);
      hi = math.max(hi, x[i]);
    }
    return hi - lo;
  }

  double _shoulderWidth(Float32List x) {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final v in asset.joints['shoulder_l']!) {
      hi = math.max(hi, x[v * 3]);
    }
    for (final v in asset.joints['shoulder_r']!) {
      lo = math.min(lo, x[v * 3]);
    }
    return hi - lo;
  }

  /// Widest (or narrowest) torso hull perimeter over horizontal slices.
  double _torsoCirc(Float32List x, double y0, double y1, {bool widest = true}) {
    double? best;
    for (var y = y0; y <= y1; y += 0.01) {
      final pts = <(double, double)>[
        for (final v in _torso)
          if ((x[v * 3 + 1] - y).abs() < _slice) (x[v * 3], x[v * 3 + 2]),
      ];
      if (pts.length < 8) continue;
      final p = _hullPerimeter(pts);
      if (best == null || (widest ? p > best : p < best)) best = p;
    }
    return best ?? 0;
  }

  /// Widest hull perimeter of slices across the a-to-b limb axis, between
  /// fractions f0 and f1 of its length.
  static double _limbCirc(
    Float32List x,
    List<int> verts,
    _V a,
    _V b,
    double f0,
    double f1,
  ) {
    final axis = b - a;
    final len = axis.length;
    final d = axis.scale(1 / len);
    final ref = d.y.abs() < 0.9 ? const _V(0, 1, 0) : const _V(1, 0, 0);
    final u = d.cross(ref).normalized();
    final w = d.cross(u);
    var best = 0.0;
    for (var f = f0; f <= f1; f += 0.05) {
      final pts = <(double, double)>[];
      for (final v in verts) {
        final p = _V(x[v * 3], x[v * 3 + 1], x[v * 3 + 2]) - a;
        if ((p.dot(d) - f * len).abs() < _slice) pts.add((p.dot(u), p.dot(w)));
      }
      if (pts.length < 8) continue;
      best = math.max(best, _hullPerimeter(pts));
    }
    return best;
  }

  /// Perimeter of the convex hull (monotone chain).
  static double _hullPerimeter(List<(double, double)> pts) {
    pts.sort(
      (p, q) => p.$1 != q.$1 ? p.$1.compareTo(q.$1) : p.$2.compareTo(q.$2),
    );
    double cross((double, double) o, (double, double) a, (double, double) b) =>
        (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
    final hull = <(double, double)>[];
    for (final p in pts) {
      while (hull.length >= 2 &&
          cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }
    final lower = hull.length + 1;
    for (final p in pts.reversed.skip(1)) {
      while (hull.length >= lower &&
          cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }
    var per = 0.0;
    for (var i = 1; i < hull.length; i++) {
      final dx = hull[i].$1 - hull[i - 1].$1;
      final dy = hull[i].$2 - hull[i - 1].$2;
      per += math.sqrt(dx * dx + dy * dy);
    }
    return per;
  }
}

class _V {
  const new(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V scale(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _V normalized() => scale(1 / length);
}
