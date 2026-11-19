import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One body shape: xyz positions (metres, feet at y = 0) and unit normals
/// per vertex, in the asset's vertex order.
@immutable
class BodyGeometry {
  const new({required this.positions, required this.normals});

  /// Builds a geometry with smooth, area-weighted normals.
  factory withNormals(Float32List positions, Uint32List indices) =>
      BodyGeometry(
        positions: positions,
        normals: computeNormals(positions, indices),
      );

  final Float32List positions;
  final Float32List normals;

  int get vertexCount => positions.length ~/ 3;

  double get minY => _extentY(math.min, double.infinity);
  double get maxY => _extentY(math.max, -double.infinity);

  double _extentY(double Function(double, double) pick, double start) {
    var m = start;
    for (var i = 1; i < positions.length; i += 3) {
      m = pick(m, positions[i]);
    }
    return m;
  }

  /// Smooth, area-weighted vertex normals.
  static Float32List computeNormals(Float32List p, Uint32List idx) {
    final out = Float32List(p.length);
    for (var t = 0; t < idx.length; t += 3) {
      final a = idx[t] * 3;
      final b = idx[t + 1] * 3;
      final c = idx[t + 2] * 3;
      final e1x = p[b] - p[a];
      final e1y = p[b + 1] - p[a + 1];
      final e1z = p[b + 2] - p[a + 2];
      final e2x = p[c] - p[a];
      final e2y = p[c + 1] - p[a + 1];
      final e2z = p[c + 2] - p[a + 2];
      // The asset build mirrored z and swapped the winding together, so the
      // plain cross product e1 x e2 still points outward.
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      for (final v in [a, b, c]) {
        out[v] += nx;
        out[v + 1] += ny;
        out[v + 2] += nz;
      }
    }
    for (var i = 0; i < out.length; i += 3) {
      final l = math.sqrt(
        out[i] * out[i] + out[i + 1] * out[i + 1] + out[i + 2] * out[i + 2],
      );
      if (l > 0) {
        out[i] /= l;
        out[i + 1] /= l;
        out[i + 2] /= l;
      }
    }
    return out;
  }
}
