import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/src/body_asset.dart';
import 'package:body_mapping/src/body_geometry.dart';
import 'package:body_mapping/src/body_scan.dart';

/// What a tap can select: a DEXA region, or the belly or hip band.
enum BodyPart {
  leftArm,
  rightArm,
  leftLeg,
  rightLeg,
  trunk,
  belly,
  hips;

  /// The region this part reads its numbers from, or null for a band.
  BodyRegion? get region => switch (this) {
    leftArm => BodyRegion.leftArm,
    rightArm => BodyRegion.rightArm,
    leftLeg => BodyRegion.leftLeg,
    rightLeg => BodyRegion.rightLeg,
    trunk => BodyRegion.trunk,
    belly || hips => null,
  };

  /// The band this part reads its numbers from, or null for a region.
  FatBand? get band => switch (this) {
    belly => FatBand.android,
    hips => FatBand.gynoid,
    _ => null,
  };
}

/// A ray in body space (metres): origin and direction.
typedef Ray3 = ({
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
});

/// Resolves taps to body parts with a CPU ray test, so picking works the
/// same with any renderer. A tap picks the strongest mask under the finger,
/// bands included: the belly opens Belly, the chest opens Trunk.
class BodyPicker {
  new(this.asset) : _parts = _partsPerTriangle(asset);

  final BodyAsset asset;

  /// Part index per triangle, -1 for the head.
  final Int8List _parts;

  /// Which part each triangle belongs to (for splitting the mesh per part).
  BodyPart? partOfTriangle(int t) =>
      _parts[t] < 0 ? null : BodyPart.values[_parts[t]];

  static Int8List _partsPerTriangle(BodyAsset a) {
    final out = Int8List(a.triangleCount);
    double sum(int t, int slot) =>
        a.mask(a.indices[t * 3], slot) +
        a.mask(a.indices[t * 3 + 1], slot) +
        a.mask(a.indices[t * 3 + 2], slot);
    for (var t = 0; t < a.triangleCount; t++) {
      var best = -1;
      var bestW = sum(t, MaskSlot.head);
      for (final r in BodyRegion.values) {
        final w = sum(t, r.index);
        if (w > bestW) {
          bestW = w;
          best = r.index;
        }
      }
      // Bands sit on top of the trunk and legs; a band wins where it is at
      // least half on.
      for (final (slot, part) in [
        (MaskSlot.android, BodyPart.belly),
        (MaskSlot.gynoid, BodyPart.hips),
      ]) {
        if (best >= 0 && sum(t, slot) >= 1.5) best = part.index;
      }
      out[t] = best;
    }
    return out;
  }

  /// The vertices of each part, for placing a label on it.
  late final Map<BodyPart, Int32List> verticesByPart = _verticesByPart();

  Map<BodyPart, Int32List> _verticesByPart() {
    final sets = [for (final _ in BodyPart.values) <int>{}];
    final idx = asset.indices;
    for (var t = 0; t < asset.triangleCount; t++) {
      final p = _parts[t];
      if (p < 0) continue;
      sets[p]
        ..add(idx[t * 3])
        ..add(idx[t * 3 + 1])
        ..add(idx[t * 3 + 2]);
    }
    return {
      for (final part in BodyPart.values)
        part: Int32List.fromList(sets[part.index].toList()..sort()),
    };
  }

  /// Where a label for [part] sits: the point of the part nearest a viewer
  /// looking from direction ([towardX], 0, [towardZ]) (a unit vector from
  /// the body toward the camera), on the shape blended from [a] to [b] at
  /// [t]. It favours the middle of the part over its edges, so the point
  /// stays on the arm or leg as the body turns.
  ({double x, double y, double z}) anchorOf(
    BodyPart part,
    BodyGeometry a,
    BodyGeometry b,
    double t, {
    required double towardX,
    required double towardZ,
  }) {
    final verts = verticesByPart[part]!;
    final pa = a.positions;
    final pb = b.positions;
    double p(int v, int j) =>
        pa[v * 3 + j] + (pb[v * 3 + j] - pa[v * 3 + j]) * t;
    // The middle of the part's bounding box, not the vertex average: hands
    // and feet have many small vertices and would pull it to the ends.
    final lo = [double.infinity, double.infinity, double.infinity];
    final hi = [-double.infinity, -double.infinity, -double.infinity];
    for (final v in verts) {
      for (var j = 0; j < 3; j++) {
        lo[j] = math.min(lo[j], p(v, j));
        hi[j] = math.max(hi[j], p(v, j));
      }
    }
    final cx = (lo[0] + hi[0]) / 2;
    final cy = (lo[1] + hi[1]) / 2;
    final cz = (lo[2] + hi[2]) / 2;
    var best = -double.infinity;
    var out = (x: cx, y: cy, z: cz);
    for (final v in verts) {
      final dx = p(v, 0) - cx;
      final dy = p(v, 1) - cy;
      final dz = p(v, 2) - cz;
      final along = dx * towardX + dz * towardZ;
      final sideX = dx - along * towardX;
      final sideZ = dz - along * towardZ;
      final off = math.sqrt(sideX * sideX + dy * dy + sideZ * sideZ);
      final score = along - 2 * off;
      if (score > best) {
        best = score;
        out = (x: cx + dx, y: cy + dy, z: cz + dz);
      }
    }
    return out;
  }

  /// The part hit by [ray] on the shape blended from [a] to [b] at [t], or
  /// null for a miss or the head.
  BodyPart? pick(Ray3 ray, BodyGeometry a, BodyGeometry b, double t) {
    final pa = a.positions;
    final pb = b.positions;
    final idx = asset.indices;
    double p(int v, int j) =>
        pa[v * 3 + j] + (pb[v * 3 + j] - pa[v * 3 + j]) * t;
    final (:ox, :oy, :oz, :dx, :dy, :dz) = ray;
    var best = double.infinity;
    var hit = -1;
    for (var tri = 0; tri < asset.triangleCount; tri++) {
      final i0 = idx[tri * 3];
      final i1 = idx[tri * 3 + 1];
      final i2 = idx[tri * 3 + 2];
      final ax = p(i0, 0);
      final ay = p(i0, 1);
      final az = p(i0, 2);
      final e1x = p(i1, 0) - ax;
      final e1y = p(i1, 1) - ay;
      final e1z = p(i1, 2) - az;
      final e2x = p(i2, 0) - ax;
      final e2y = p(i2, 1) - ay;
      final e2z = p(i2, 2) - az;
      // Moller-Trumbore.
      final hx = dy * e2z - dz * e2y;
      final hy = dz * e2x - dx * e2z;
      final hz = dx * e2y - dy * e2x;
      final det = e1x * hx + e1y * hy + e1z * hz;
      if (det.abs() < 1e-12) continue;
      final inv = 1 / det;
      final sx = ox - ax;
      final sy = oy - ay;
      final sz = oz - az;
      final u = inv * (sx * hx + sy * hy + sz * hz);
      if (u < 0 || u > 1) continue;
      final qx = sy * e1z - sz * e1y;
      final qy = sz * e1x - sx * e1z;
      final qz = sx * e1y - sy * e1x;
      final v = inv * (dx * qx + dy * qy + dz * qz);
      if (v < 0 || u + v > 1) continue;
      final dist = inv * (e2x * qx + e2y * qy + e2z * qz);
      if (dist > 0 && dist < best) {
        best = dist;
        hit = tri;
      }
    }
    return hit < 0 ? null : partOfTriangle(hit);
  }
}
