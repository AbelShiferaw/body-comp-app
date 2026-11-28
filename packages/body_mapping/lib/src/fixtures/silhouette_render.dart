import 'dart:math' as math;
import 'dart:typed_data';

import 'package:body_mapping/src/body_asset.dart';
import 'package:body_mapping/src/body_scan.dart';
import 'package:body_mapping/src/silhouette.dart';

/// Renders a body shape's silhouette the way a far-away camera sees it
/// (orthographic), as a [PersonMask] with a margin, at [pxPerM].
///
/// [side] looks along x (the body in profile) and leaves the arms out, as
/// arms relaxed at the sides sit inside the torso's outline.
PersonMask renderSilhouette(
  BodyAsset asset,
  Float32List p, {
  required bool side,
  double pxPerM = 400,
}) {
  final axis = side ? 2 : 0;
  var minA = double.infinity;
  var maxA = -double.infinity;
  var minY = double.infinity;
  var maxY = -double.infinity;
  for (var v = 0; v < asset.vertexCount; v++) {
    minA = math.min(minA, p[v * 3 + axis]);
    maxA = math.max(maxA, p[v * 3 + axis]);
    minY = math.min(minY, p[v * 3 + 1]);
    maxY = math.max(maxY, p[v * 3 + 1]);
  }
  const margin = 12;
  final w = ((maxA - minA) * pxPerM).ceil() + 2 * margin;
  final h = ((maxY - minY) * pxPerM).ceil() + 2 * margin;
  final data = Uint8List(w * h);
  double sx(int v) => (p[v * 3 + axis] - minA) * pxPerM + margin;
  double sy(int v) => h - margin - (p[v * 3 + 1] - minY) * pxPerM;
  bool isArm(int v) =>
      asset.mask(v, BodyRegion.leftArm.index) +
          asset.mask(v, BodyRegion.rightArm.index) >
      0.5;

  final idx = asset.indices;
  for (var t = 0; t < idx.length; t += 3) {
    final a = idx[t];
    final b = idx[t + 1];
    final c = idx[t + 2];
    if (side && (isArm(a) || isArm(b) || isArm(c))) continue;
    final xs = [sx(a), sx(b), sx(c)];
    final ys = [sy(a), sy(b), sy(c)];
    double edge(int i, int j, double px, double py) =>
        (xs[j] - xs[i]) * (py - ys[i]) - (ys[j] - ys[i]) * (px - xs[i]);
    final area = edge(0, 1, xs[2], ys[2]);
    if (area.abs() < 1e-9) continue;
    final x0 = math.max(0, xs.reduce(math.min).floor());
    final x1 = math.min(w - 1, xs.reduce(math.max).ceil());
    final y0 = math.max(0, ys.reduce(math.min).floor());
    final y1 = math.min(h - 1, ys.reduce(math.max).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        final w0 = edge(1, 2, px, py) / area;
        final w1 = edge(2, 0, px, py) / area;
        if (w0 >= 0 && w1 >= 0 && w0 + w1 <= 1) data[y * w + x] = 1;
      }
    }
  }
  return PersonMask(w, h, data);
}
