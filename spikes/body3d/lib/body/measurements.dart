import 'dart:math' as math;
import 'dart:typed_data';

import 'body_asset.dart';

/// Body measurements a user (or a photo SDK) can provide, in cm.
enum Measure {
  height('Height'),
  shoulders('Shoulder width'),
  chest('Chest'),
  waist('Waist'),
  hips('Hips'),
  upperArm('Upper arm'),
  thigh('Thigh'),
  calf('Calf'),
  armLength('Arm length'),
  legLength('Leg length');

  const Measure(this.label);
  final String label;

  String get hint => switch (this) {
    Measure.height => 'standing, no shoes',
    Measure.shoulders => 'outside of shoulder to shoulder',
    Measure.chest => 'around, at the nipples',
    Measure.waist => 'around, at the narrowest point',
    Measure.hips => 'around, at the widest point of the buttocks',
    Measure.upperArm => 'around, widest part, relaxed',
    Measure.thigh => 'around, just below the buttock',
    Measure.calf => 'around, widest part',
    Measure.armLength => 'shoulder joint to wrist',
    Measure.legLength => 'hip joint to ankle',
  };
}

/// Measurement shapes in body.glb and the measurement each one drives.
enum Proportion {
  shoulders(Measure.shoulders, ['shoulder-dist']),
  chest(Measure.chest, ['bust-circ']),
  waist(Measure.waist, ['waist-circ']),
  hips(Measure.hips, ['hips-circ']),
  upperArm(Measure.upperArm, ['upperarm-circ']),
  thigh(Measure.thigh, ['thigh-circ']),
  calf(Measure.calf, ['calf-circ']),
  armLength(Measure.armLength, ['upperarm-length', 'lowerarm-length']),
  legLength(Measure.legLength, ['upperleg-height', 'lowerleg-height']);

  const Proportion(this.measure, this.targets);
  final Measure measure;
  final List<String> targets;
}

/// Measures a body mesh the way a tape would: circumferences are the convex
/// hull of a thin slice through the body (a tape spans hollows), lengths go
/// between joint centres.
class BodyMeasurer {
  BodyMeasurer(this.asset) {
    final m = asset.masks;
    for (var v = 0; v < asset.vertexCount; v++) {
      final arm = m[v * 8 + 0] + m[v * 8 + 1];
      final head = m[v * 8 + 5];
      if (arm < 0.5 && head < 0.5) _torso.add(v);
      if (m[v * 8 + 0] > 0.5) _armL.add(v);
      if (m[v * 8 + 1] > 0.5) _armR.add(v);
      if (m[v * 8 + 2] > 0.5) _legL.add(v);
      if (m[v * 8 + 3] > 0.5) _legR.add(v);
    }
  }

  final BodyAsset asset;
  final _torso = <int>[], _armL = <int>[], _armR = <int>[];
  final _legL = <int>[], _legR = <int>[];

  static const _slice = 0.008;

  /// Prints limb slices (debugging aid for the spike).
  static bool debugLimb = false; // half-thickness of a tape slice, metres

  Map<Measure, double> measureAll(Float32List x) => {
    for (final m in Measure.values) m: measure(x, m),
  };

  /// One measurement of [x] (metres, y up), in cm.
  double measure(Float32List x, Measure m) {
    final j = _joints(x);
    double dist(String a, String b) => (j[a]! - j[b]!).length;
    double avg(double Function(String side) f) => (f('l') + f('r')) / 2;
    final hipY = (j['hip_l']!.y + j['hip_r']!.y) / 2;
    final shY = (j['shoulder_l']!.y + j['shoulder_r']!.y) / 2;
    final span = shY - hipY;
    final cm = switch (m) {
      Measure.height => _height(x),
      Measure.shoulders => _shoulderWidth(x),
      Measure.chest => _torsoCirc(
        x,
        hipY + 0.60 * span,
        hipY + 0.85 * span,
        true,
      ),
      Measure.waist => _torsoCirc(
        x,
        hipY + 0.25 * span,
        hipY + 0.55 * span,
        false,
      ),
      Measure.hips => _torsoCirc(
        x,
        hipY - 0.15 * span,
        hipY + 0.10 * span,
        true,
      ),
      Measure.upperArm => avg(
        (s) => _limbCirc(
          x,
          s == 'l' ? _armL : _armR,
          j['shoulder_$s']!,
          j['elbow_$s']!,
          0.45,
          0.65,
        ),
      ),
      Measure.thigh => avg(
        (s) => _limbCirc(
          x,
          s == 'l' ? _legL : _legR,
          j['hip_$s']!,
          j['knee_$s']!,
          0.15,
          0.45,
        ),
      ),
      Measure.calf => avg(
        (s) => _limbCirc(
          x,
          s == 'l' ? _legL : _legR,
          j['knee_$s']!,
          j['ankle_$s']!,
          0.15,
          0.60,
        ),
      ),
      Measure.armLength => avg(
        (s) => dist('shoulder_$s', 'elbow_$s') + dist('elbow_$s', 'wrist_$s'),
      ),
      Measure.legLength => avg(
        (s) => dist('hip_$s', 'knee_$s') + dist('knee_$s', 'ankle_$s'),
      ),
    };
    return cm * 100;
  }

  Map<String, _V> _joints(Float32List x) => {
    for (final e in asset.joints.entries) e.key: _centroid(x, e.value),
  };

  static _V _centroid(Float32List x, List<int> idx) {
    var cx = 0.0, cy = 0.0, cz = 0.0;
    for (final v in idx) {
      cx += x[v * 3];
      cy += x[v * 3 + 1];
      cz += x[v * 3 + 2];
    }
    return _V(cx / idx.length, cy / idx.length, cz / idx.length);
  }

  static double _height(Float32List x) {
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 1; i < x.length; i += 3) {
      lo = math.min(lo, x[i]);
      hi = math.max(hi, x[i]);
    }
    return hi - lo;
  }

  double _shoulderWidth(Float32List x) {
    var lo = double.infinity, hi = -double.infinity;
    for (final v in asset.joints['shoulder_l']!) {
      hi = math.max(hi, x[v * 3]);
    }
    for (final v in asset.joints['shoulder_r']!) {
      lo = math.min(lo, x[v * 3]);
    }
    return hi - lo;
  }

  /// Max (or min) torso hull perimeter over horizontal slices from y0 to y1.
  double _torsoCirc(Float32List x, double y0, double y1, bool max) {
    double? best;
    for (var y = y0; y <= y1; y += 0.01) {
      final pts = <(double, double)>[];
      for (final v in _torso) {
        if ((x[v * 3 + 1] - y).abs() < _slice)
          pts.add((x[v * 3], x[v * 3 + 2]));
      }
      if (pts.length < 8) continue;
      final p = _hullPerimeter(pts);
      if (best == null || (max ? p > best : p < best)) best = p;
    }
    return best ?? 0;
  }

  /// Max hull perimeter of slices perpendicular to the a->b limb axis,
  /// between fractions f0 and f1 of its length.
  double _limbCirc(
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
    // Orthonormal basis (u, w) perpendicular to d.
    final ref = d.y.abs() < 0.9 ? const _V(0, 1, 0) : const _V(1, 0, 0);
    final u = d.cross(ref).normalized();
    final w = d.cross(u);
    var best = 0.0;
    for (var f = f0; f <= f1; f += 0.05) {
      final pts = <(double, double)>[];
      for (final v in verts) {
        final p = _V(x[v * 3], x[v * 3 + 1], x[v * 3 + 2]) - a;
        final s = p.dot(d);
        if ((s - f * len).abs() < _slice) pts.add((p.dot(u), p.dot(w)));
      }
      if (pts.length < 8) continue;
      final per = _hullPerimeter(pts);
      if (debugLimb) {
        // ignore: avoid_print
        print(
          '  f=${f.toStringAsFixed(2)} n=${pts.length} per=${(per * 100).toStringAsFixed(1)}',
        );
      }
      best = math.max(best, per);
    }
    return best;
  }

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
      per += math.sqrt(
        math.pow(hull[i].$1 - hull[i - 1].$1, 2) +
            math.pow(hull[i].$2 - hull[i - 1].$2, 2),
      );
    }
    return per;
  }
}

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V scale(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  _V normalized() => scale(1 / length);
}
