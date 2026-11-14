import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'body_asset.dart';
import 'body_shaper.dart';
import 'dexa_scan.dart';

/// The visual styles Abel can try.
enum BodyStyle { studio, heatmap, midnight }

/// The flutter_scene side: one node per region (so each region can carry its
/// own colour and be told apart when tapped), each a morphed mesh with a
/// single target that blends scan A into scan B.
class BodyScene {
  BodyScene(this.asset) : shaper = BodyShaper(asset) {
    _splitRegions();
  }

  final BodyAsset asset;
  final BodyShaper shaper;
  final Scene scene = Scene();

  final Map<Region, Node> _nodes = {};
  final Map<Region, Uint32List> _regionVerts = {}; // local -> global vertex
  final Map<Region, Uint32List> _regionIndices = {}; // local triangles
  final Map<Region, PhysicallyBasedMaterial> _materials = {};
  late Float32List _triRegion; // region index per triangle, for picking

  DexaScan? _a, _b;
  Float32List? _posA, _posB;
  double _t = 0;
  BodyStyle _style = BodyStyle.studio;
  Region? _selected;

  double get t => _t;
  BodyStyle get style => _style;
  Region? get selected => _selected;

  /// Height of the shown body's top, metres (for camera framing).
  double get topY {
    final p = _posA;
    if (p == null) return 1.8;
    var m = -1e9;
    for (var i = 1; i < p.length; i += 3) {
      m = math.max(m, p[i]);
    }
    return m;
  }

  double get bottomY {
    final p = _posA;
    if (p == null) return 0;
    var m = 1e9;
    for (var i = 1; i < p.length; i += 3) {
      m = math.min(m, p[i]);
    }
    return m;
  }

  void _splitRegions() {
    final idx = asset.indices;
    final masks = asset.masks;
    final triCount = asset.triangleCount;
    _triRegion = Float32List(triCount);
    final tris = {for (final r in Region.values) r: <int>[]};
    for (var t = 0; t < triCount; t++) {
      var best = 0;
      var bestW = -1.0;
      for (var r = 0; r < 6; r++) {
        final w =
            masks[idx[t * 3] * 8 + r] +
            masks[idx[t * 3 + 1] * 8 + r] +
            masks[idx[t * 3 + 2] * 8 + r];
        if (w > bestW) {
          bestW = w;
          best = r;
        }
      }
      _triRegion[t] = best.toDouble();
      tris[Region.values[best]]!.add(t);
    }
    for (final r in Region.values) {
      final map = <int, int>{};
      final verts = <int>[];
      final local = Uint32List(tris[r]!.length * 3);
      var k = 0;
      for (final t in tris[r]!) {
        for (var j = 0; j < 3; j++) {
          final g = idx[t * 3 + j];
          local[k++] = map.putIfAbsent(g, () {
            verts.add(g);
            return verts.length - 1;
          });
        }
      }
      _regionVerts[r] = Uint32List.fromList(verts);
      _regionIndices[r] = local;
    }
  }

  /// Shows scan [a] blending to scan [b] (b may equal a).
  void setScans(DexaScan a, DexaScan b) {
    _a = a;
    _b = b;
    final posA = shaper.positionsFor(a);
    final posB = identical(a, b) ? posA : shaper.positionsFor(b);
    final nA = shaper.normalsFor(posA);
    final nB = identical(a, b) ? nA : shaper.normalsFor(posB);
    _posA = posA;
    _posB = posB;

    for (final r in Region.values) {
      final verts = _regionVerts[r]!;
      final n = verts.length;
      // Standard unskinned layout: position 3, normal 3, uv0 2, uv1 2,
      // color 4, tangent 4 = 18 floats (72 bytes).
      final vb = Float32List(n * 18);
      final dPos = Float32List(n * 3);
      final dNrm = Float32List(n * 3);
      for (var i = 0; i < n; i++) {
        final g = verts[i] * 3;
        final o = i * 18;
        for (var j = 0; j < 3; j++) {
          vb[o + j] = posA[g + j];
          vb[o + 3 + j] = nA[g + j];
          dPos[i * 3 + j] = posB[g + j] - posA[g + j];
          dNrm[i * 3 + j] = nB[g + j] - nA[g + j];
        }
        vb[o + 10] = 1;
        vb[o + 11] = 1;
        vb[o + 12] = 1;
        vb[o + 13] = 1; // vertex colour white
        vb[o + 14] = 1;
        vb[o + 17] = 1; // tangent (1,0,0,+1)
      }
      final geometry = MorphedUnskinnedGeometry(
        MorphTargetData(
          vertexCount: n,
          targetCount: 1,
          positionDeltas: dPos,
          normalDeltas: dNrm,
          targetNames: const ['scanB'],
        ),
      );
      geometry.uploadVertexData(
        vb,
        n,
        _regionIndices[r]!,
        indexType: gpu.IndexType.int32,
      );

      final material = _materials.putIfAbsent(r, PhysicallyBasedMaterial.new);
      final old = _nodes[r];
      if (old != null) scene.remove(old);
      final node = Node(name: r.name, mesh: Mesh(geometry, material));
      scene.add(node);
      _nodes[r] = node;
    }
    _applyT();
    _applyStyle();
    _applySelection();
  }

  /// 0 shows scan A, 1 shows scan B.
  set t(double value) {
    _t = value.clamp(0.0, 1.0);
    _applyT();
    if (_style == BodyStyle.heatmap) _applyStyle();
  }

  set style(BodyStyle s) {
    _style = s;
    _applyStyle();
  }

  set selected(Region? r) {
    _selected = r;
    _applySelection();
  }

  void _applyT() {
    for (final node in _nodes.values) {
      node.setMorphWeight(0, _t);
    }
  }

  /// Fat % of [r] at the current blend.
  double fatPctAt(Region r) {
    final a = _a!.regions[r]!, b = _b!.regions[r]!;
    return a.fatPct + (b.fatPct - a.fatPct) * _t;
  }

  static vm.Vector3 _heat(double fatPct) {
    // 8% teal -> 18% amber -> 30% coral.
    const stops = [
      (8.0, (0.10, 0.72, 0.66)),
      (18.0, (0.98, 0.74, 0.20)),
      (30.0, (0.93, 0.28, 0.24)),
    ];
    if (fatPct <= stops.first.$1) {
      final c = stops.first.$2;
      return vm.Vector3(c.$1, c.$2, c.$3);
    }
    for (var i = 0; i < stops.length - 1; i++) {
      final (x0, c0) = stops[i];
      final (x1, c1) = stops[i + 1];
      if (fatPct <= x1) {
        final f = (fatPct - x0) / (x1 - x0);
        return vm.Vector3(
          c0.$1 + (c1.$1 - c0.$1) * f,
          c0.$2 + (c1.$2 - c0.$2) * f,
          c0.$3 + (c1.$3 - c0.$3) * f,
        );
      }
    }
    final c = stops.last.$2;
    return vm.Vector3(c.$1, c.$2, c.$3);
  }

  static vm.Vector4 _lin(double r, double g, double b) {
    // sRGB-ish authoring colours to linear.
    double l(double c) => math.pow(c, 2.2).toDouble();
    return vm.Vector4(l(r), l(g), l(b), 1);
  }

  void _applyStyle() {
    switch (_style) {
      case BodyStyle.studio:
        scene.directionalLight = DirectionalLight(
          direction: vm.Vector3(0.4, -0.7, 0.6),
          color: vm.Vector3(1.0, 0.97, 0.92),
          intensity: 2.2,
        );
        scene.environmentIntensity = 1.0;
        for (final m in _materials.values) {
          m.baseColorFactor = _lin(0.86, 0.83, 0.80);
          m.metallicFactor = 0;
          m.roughnessFactor = 0.62;
          m.clearcoat = 0;
          m.emissiveFactor = vm.Vector4.zero();
        }
      case BodyStyle.heatmap:
        scene.directionalLight = DirectionalLight(
          direction: vm.Vector3(0.3, -0.6, 0.7),
          color: vm.Vector3(1, 1, 1),
          intensity: 1.8,
        );
        scene.environmentIntensity = 0.9;
        for (final e in _materials.entries) {
          final m = e.value;
          if (e.key == Region.head) {
            m.baseColorFactor = _lin(0.62, 0.64, 0.68);
          } else {
            final c = _heat(fatPctAt(e.key));
            m.baseColorFactor = _lin(c.x, c.y, c.z);
          }
          m.metallicFactor = 0;
          m.roughnessFactor = 0.5;
          m.clearcoat = 0;
          m.emissiveFactor = vm.Vector4.zero();
        }
      case BodyStyle.midnight:
        scene.directionalLight = DirectionalLight(
          direction: vm.Vector3(-0.5, -0.4, 0.75),
          color: vm.Vector3(0.75, 0.88, 1.0),
          intensity: 3.0,
        );
        scene.environmentIntensity = 0.55;
        for (final m in _materials.values) {
          m.baseColorFactor = _lin(0.20, 0.22, 0.26);
          m.metallicFactor = 0.0;
          m.roughnessFactor = 0.28;
          m.clearcoat = 1.0;
          m.clearcoatRoughness = 0.15;
          m.emissiveFactor = vm.Vector4.zero();
        }
    }
  }

  void _applySelection() {
    for (final e in _nodes.entries) {
      e.value.highlightColor = e.key == _selected
          ? (_style == BodyStyle.studio
                ? vm.Vector4(0.15, 0.45, 1.0, 1)
                : vm.Vector4(1, 1, 1, 1))
          : null;
    }
  }

  /// The region under a tap at [point] in a view of [size], or null.
  Region? pick(Camera camera, Offset point, Size size) {
    final pa = _posA, pb = _posB;
    if (pa == null || pb == null) return null;
    final ray = camera.screenPointToRay(point, size);
    final o = ray.origin;
    final d = ray.direction.normalized();
    final idx = asset.indices;
    double px(int v, int j) =>
        pa[v * 3 + j] + (pb[v * 3 + j] - pa[v * 3 + j]) * _t;
    var best = double.infinity;
    var bestTri = -1;
    for (var t = 0; t < asset.triangleCount; t++) {
      final i0 = idx[t * 3], i1 = idx[t * 3 + 1], i2 = idx[t * 3 + 2];
      final ax = px(i0, 0), ay = px(i0, 1), az = px(i0, 2);
      final e1x = px(i1, 0) - ax, e1y = px(i1, 1) - ay, e1z = px(i1, 2) - az;
      final e2x = px(i2, 0) - ax, e2y = px(i2, 1) - ay, e2z = px(i2, 2) - az;
      // Moller-Trumbore.
      final hx = d.y * e2z - d.z * e2y;
      final hy = d.z * e2x - d.x * e2z;
      final hz = d.x * e2y - d.y * e2x;
      final det = e1x * hx + e1y * hy + e1z * hz;
      if (det.abs() < 1e-9) continue;
      final inv = 1 / det;
      final sx = o.x - ax, sy = o.y - ay, sz = o.z - az;
      final u = inv * (sx * hx + sy * hy + sz * hz);
      if (u < 0 || u > 1) continue;
      final qx = sy * e1z - sz * e1y;
      final qy = sz * e1x - sx * e1z;
      final qz = sx * e1y - sy * e1x;
      final v = inv * (d.x * qx + d.y * qy + d.z * qz);
      if (v < 0 || u + v > 1) continue;
      final dist = inv * (e2x * qx + e2y * qy + e2z * qz);
      if (dist > 0 && dist < best) {
        best = dist;
        bestTri = t;
      }
    }
    if (bestTri < 0) return null;
    return Region.values[_triRegion[bestTri].toInt()];
  }
}
